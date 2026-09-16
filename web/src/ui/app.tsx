import { effect, type Signal, signal } from "@preact/signals";
import { useEffect } from "preact/hooks";
import { listenVisibility } from "../platform/visibility.ts";
import { SessionController } from "../session/controller.ts";
import { loadSettings, type Settings, saveSettings } from "../session/settings.ts";
import { browserStorage, CredentialStore } from "../session/storage.ts";
import { LoginPage } from "./login/login-page.tsx";
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

const screen = signal<"login" | "stream">("login");
const loginNotice = signal<string | null>(null);

export function App({ ctx }: { ctx: AppContext }) {
  useEffect(() => listenVisibility((hidden) => ctx.controller.setHidden(hidden)), [ctx]);

  useEffect(() => {
    return effect(() => {
      const link = ctx.controller.state.value.link;
      const reason = ctx.controller.state.value.disconnectReason;
      if (screen.value !== "stream") return;
      if (link.phase === "failed") {
        loginNotice.value = link.message;
        screen.value = "login";
      } else if (link.phase === "idle") {
        loginNotice.value = reason ? "Disconnected by the computer." : "Disconnected.";
        screen.value = "login";
      }
    });
  }, [ctx]);

  if (screen.value === "stream") {
    return (
      <StreamPage
        ctx={ctx}
        onLeave={() => {
          ctx.controller.disconnect();
          loginNotice.value = null;
          screen.value = "login";
        }}
      />
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
