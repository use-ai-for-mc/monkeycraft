import { useSignal } from "@preact/signals";
import { useEffect } from "preact/hooks";
import type { ServerListEntry } from "../../protocol/messages.ts";
import type { AppContext } from "../app.tsx";

interface Props {
  ctx: AppContext;
  onDisconnect: () => void;
}

/** Shown while the Minecraft client sits at its menu: pick a saved server or type one. */
export function PickerPanel({ ctx, onDisconnect }: Props) {
  const controller = ctx.controller;
  const servers = useSignal<ServerListEntry[] | null>(null);
  const address = useSignal("");
  const acceptPack = useSignal(true);
  const joining = useSignal<string | null>(null);
  const error = useSignal<string | null>(null);

  const refresh = () => {
    servers.value = null;
    controller.send({ type: "LIST_SERVERS" });
  };

  useEffect(() => {
    refresh();
    return controller.onEvent((ev) => {
      if (ev.kind !== "message") return;
      if (ev.msg.type === "SERVER_LIST") servers.value = ev.msg.servers;
      if (ev.msg.type === "JOIN_RESULT" && !ev.msg.ok) {
        joining.value = null;
        error.value = ev.msg.error ?? "Failed to join server";
      }
      if (ev.msg.type === "WORLD_STATE" && ev.msg.phase === "MENU" && joining.value) {
        joining.value = null;
        error.value = "Could not connect to that server";
      }
    });
  }, [controller, servers, joining, error]);

  const join = (addr: string, name?: string) => {
    const a = addr.trim();
    if (!a) return;
    error.value = null;
    joining.value = name ?? a;
    controller.send({
      type: "JOIN_SERVER",
      address: a,
      ...(name ? { name } : {}),
      acceptResourcePack: acceptPack.value,
    });
  };

  return (
    <section class="picker" data-testid="picker-panel">
      <header>
        <h2>Choose a server</h2>
        <button type="button" onClick={refresh} aria-label="Refresh">
          ↻
        </button>
        <button type="button" onClick={onDisconnect} aria-label="Disconnect">
          ✕
        </button>
      </header>
      <label class="row">
        <input
          type="checkbox"
          checked={acceptPack.value}
          onChange={(e) => (acceptPack.value = (e.currentTarget as HTMLInputElement).checked)}
        />
        Accept server resource pack
      </label>
      <div class="servers">
        {servers.value === null && <p class="muted">Loading…</p>}
        {servers.value?.length === 0 && (
          <p class="muted">No saved servers on this Minecraft client.</p>
        )}
        {servers.value?.map((s) => (
          <button
            type="button"
            key={s.index}
            class="server"
            onClick={() => join(s.address, s.name)}
          >
            <span class="name">{s.name}</span>
            <span class="addr">{s.address}</span>
          </button>
        ))}
      </div>
      <form
        class="direct"
        onSubmit={(e) => {
          e.preventDefault();
          join(address.value);
        }}
      >
        <input
          type="text"
          value={address.value}
          placeholder="play.example.com or 192.168.1.5:25565"
          autocapitalize="off"
          autocorrect="off"
          onInput={(e) => (address.value = (e.currentTarget as HTMLInputElement).value)}
        />
        <button type="submit" class="primary">
          Join
        </button>
      </form>
      {error.value && <p class="error">{error.value}</p>}
      {joining.value && (
        <div class="overlay scrim">
          <p class="big">Joining {joining.value}…</p>
        </div>
      )}
    </section>
  );
}
