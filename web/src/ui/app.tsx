import { effect, type Signal, signal } from "@preact/signals";
import { useEffect } from "preact/hooks";
import { ensureNotificationPermission, notifyIfHidden } from "../platform/notifications.ts";
import { acquireTabLock } from "../platform/tab-lock.ts";
import { listenVisibility } from "../platform/visibility.ts";
import { SessionController } from "../session/controller.ts";
import { loadSettings, type Settings, saveSettings } from "../session/settings.ts";
import { browserStorage, CredentialStore } from "../session/storage.ts";
import { ChatPanel } from "./chat/chat-panel.tsx";
import { LoginPage } from "./login/login-page.tsx";
import { PickerPanel } from "./picker/picker-panel.tsx";
import { SettingsPanel } from "./settings/settings-panel.tsx";
import { StreamPage } from "./stream/stream-page.tsx";

export interface AppContext {
  controller: SessionController;
  credentials: CredentialStore;
  settings: Signal<Settings>;
  updateSettings: (patch: Partial<Settings>) => void;
}

export function createAppContext(): AppContext {
  const storage = browserStorage();
  const credentials = new CredentialStore(storage);
  const settings = signal<Settings>(loadSettings(storage));
  const controller = new SessionController({
    credentials,
    settings: () => settings.value,
  });
  effect(() => saveSettings(storage, settings.value));
  return {
    controller,
    credentials,
    settings,
    updateSettings: (patch) => {
      settings.value = { ...settings.value, ...patch };
    },
  };
}

export type Panel = "chat" | "settings" | null;

const screen = signal<"login" | "stream">("login");
const panel = signal<Panel>(null);
const loginNotice = signal<string | null>(null);

export function App({ ctx }: { ctx: AppContext }) {
  useEffect(() => listenVisibility((hidden) => ctx.controller.setHidden(hidden)), [ctx]);

  useEffect(() => {
    void acquireTabLock().then((r) => {
      if (r === "busy") loginNotice.value = "MonkeyCraft is already open in another tab.";
    });
    // The reducer runs before listeners, so track hibernation transitions here.
    let wasHibernating = ctx.controller.snapshot.hibernating;
    return ctx.controller.onEvent((ev) => {
      if (ev.kind === "authenticated") void ensureNotificationPermission();
      if (ev.kind === "message" && ev.msg.type === "NUDGE") {
        notifyIfHidden(ev.msg.title ?? "MonkeyCraft", ev.msg.body);
      }
      if (ev.kind === "message" && ev.msg.type === "SERVER_STATUS") {
        const hibernating = ev.msg.videoState === "HIBERNATING";
        if (wasHibernating && !hibernating) notifyIfHidden("Ride finished", "Video is back.");
        wasHibernating = hibernating;
      }
    });
  }, [ctx]);

  useEffect(() => {
    return effect(() => {
      const link = ctx.controller.state.value.link;
      const reason = ctx.controller.state.value.disconnectReason;
      if (screen.value !== "stream") return;
      if (link.phase === "failed") {
        loginNotice.value = link.message;
        panel.value = null;
        screen.value = "login";
      } else if (link.phase === "idle") {
        loginNotice.value = reason ? "Disconnected by the computer." : "Disconnected.";
        panel.value = null;
        screen.value = "login";
      }
    });
  }, [ctx]);

  const leave = () => {
    ctx.controller.disconnect();
    loginNotice.value = null;
    panel.value = null;
    screen.value = "login";
  };

  if (screen.value === "stream") {
    const atMenu = ctx.controller.state.value.world?.phase === "MENU";
    return (
      <>
        <StreamPage
          ctx={ctx}
          onLeave={leave}
          onOpenChat={() => (panel.value = "chat")}
          onOpenSettings={() => (panel.value = "settings")}
        />
        {panel.value === "chat" && <ChatPanel ctx={ctx} onClose={() => (panel.value = null)} />}
        {panel.value === "settings" && (
          <SettingsPanel
            ctx={ctx}
            onClose={() => (panel.value = null)}
            onLogout={() => {
              ctx.credentials.clearPasswords();
              leave();
            }}
          />
        )}
        {atMenu && <PickerPanel ctx={ctx} onDisconnect={leave} />}
      </>
    );
  }
  return (
    <LoginPage
      ctx={ctx}
      notice={loginNotice.value}
      onConnected={() => {
        loginNotice.value = null;
        screen.value = "stream";
      }}
    />
  );
}
