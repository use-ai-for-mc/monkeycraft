import { useSignal } from "@preact/signals";
import { useEffect } from "preact/hooks";
import {
  defaultLoginMode,
  isPairingEligibleServer,
  type LoginMode,
} from "../../session/pairing.ts";
import { ConnectionError } from "../../transport/connection.ts";
import { insecureWebSocketMessage, webOriginServer } from "../../transport/endpoint.ts";
import type { AppContext } from "../app.tsx";
import { QrScan } from "./qr-scan.tsx";

interface Props {
  ctx: AppContext;
  notice: string | null;
  onConnected: () => void;
}

function describeError(err: unknown): string {
  if (err instanceof ConnectionError) {
    switch (err.failure?.code) {
      case "pairing-unavailable":
        return "This address needs a password. Enter it or scan the QR code.";
      case "invalid-signature":
        return "Saved password did not match this computer. Enter the current password or pair again.";
      case "pair-failed":
        return `Pairing failed: ${err.failure.message}`;
      case "replaced":
        return "Another device logged in.";
      default:
        break;
    }
    if (err.code === "timeout")
      return "Connection timed out. Check the server address and try again.";
    return `Connection failed: ${err.message}`;
  }
  return `Connection failed: ${String(err)}`;
}

export function LoginPage({ ctx, notice, onConnected }: Props) {
  const origin = webOriginServer(new URL(window.location.href));
  const server = useSignal(ctx.credentials.server ?? origin);
  const latest = ctx.credentials.latest(server.value);
  const password = useSignal(latest?.password ?? "");
  const remember = useSignal(ctx.credentials.remember);
  const mode = useSignal<LoginMode>(defaultLoginMode(password.value !== "", server.value));
  const busy = useSignal(false);
  const error = useSignal<string | null>(null);
  const pairingCode = useSignal<string | null>(null);
  const pairingLeft = useSignal<number | null>(null);
  const scanning = useSignal(false);

  const selectServer = (value: string) => {
    server.value = value;
    const saved = ctx.credentials.latest(value);
    password.value = saved?.password ?? "";
    mode.value = defaultLoginMode(password.value !== "", value);
  };

  useEffect(() => {
    let expiresAt = 0;
    const tick = setInterval(() => {
      if (pairingCode.value && expiresAt > 0) {
        pairingLeft.value = Math.max(0, Math.round((expiresAt - Date.now()) / 1000));
      }
    }, 1000);
    const off = ctx.controller.onEvent((ev) => {
      if (ev.kind === "pairing") {
        pairingCode.value = `${ev.code.slice(0, 4)}-${ev.code.slice(4)}`;
        expiresAt = Date.now() + ev.ttlMs;
        pairingLeft.value = Math.round(ev.ttlMs / 1000);
      }
      if (ev.kind === "authenticated") pairingCode.value = null;
    });
    return () => {
      clearInterval(tick);
      off();
    };
  }, [ctx, pairingCode, pairingLeft]);

  if (scanning.value) {
    return (
      <QrScan
        onResult={(value) => {
          password.value = value.trim();
          mode.value = "password";
          scanning.value = false;
        }}
        onClose={() => {
          scanning.value = false;
        }}
      />
    );
  }

  const submit = async (e: Event) => {
    e.preventDefault();
    if (busy.value) return;
    error.value = null;
    const target = server.value.trim();
    if (target === "") {
      error.value = "Server address is required.";
      return;
    }
    const insecureMessage = insecureWebSocketMessage(new URL(window.location.href), target);
    if (insecureMessage) {
      error.value = insecureMessage;
      return;
    }
    if (mode.value === "password" && password.value === "") {
      error.value = "Enter the password or scan the QR code.";
      return;
    }
    ctx.credentials.remember = remember.value;
    ctx.credentials.server = target === origin ? null : target;
    busy.value = true;
    try {
      await ctx.controller.connect({
        server: target,
        password: mode.value === "pair" ? "" : password.value,
        pairIfNeeded: mode.value === "pair",
      });
      onConnected();
    } catch (err) {
      error.value = describeError(err);
      if (err instanceof ConnectionError && err.failure?.code === "pairing-unavailable") {
        mode.value = "password";
      }
    } finally {
      busy.value = false;
      pairingCode.value = null;
    }
  };

  const cancel = () => {
    ctx.controller.disconnect();
  };

  const pairEligible = isPairingEligibleServer(server.value);

  return (
    <main class="login">
      <form class="card" onSubmit={submit}>
        <h1>MonkeyCraft</h1>
        {notice && <p class="notice">{notice}</p>}
        <label>
          Server address
          <input
            type="text"
            value={server.value}
            placeholder="192.168.0.3:9600 or https://pc.tailnet.ts.net:10800"
            autocapitalize="off"
            autocorrect="off"
            spellcheck={false}
            onInput={(e) => {
              selectServer((e.currentTarget as HTMLInputElement).value);
            }}
            disabled={busy.value}
          />
        </label>
        {mode.value === "password" && (
          <label>
            Password
            <div class="password-row">
              <input
                type="password"
                value={password.value}
                autocomplete="current-password"
                onInput={(e) => {
                  password.value = (e.currentTarget as HTMLInputElement).value;
                }}
                disabled={busy.value}
              />
              <button
                type="button"
                class="icon"
                title="Scan QR code"
                aria-label="Scan QR code"
                onClick={() => {
                  scanning.value = true;
                }}
                disabled={busy.value}
              >
                ▣
              </button>
            </div>
          </label>
        )}
        <label class="row">
          <input
            type="checkbox"
            checked={remember.value}
            onChange={(e) => {
              remember.value = (e.currentTarget as HTMLInputElement).checked;
            }}
          />
          Remember password in this browser
        </label>
        {mode.value === "password" ? (
          pairEligible && (
            <button
              type="button"
              class="link"
              onClick={() => {
                mode.value = "pair";
              }}
            >
              Pair instead (same Wi-Fi or Tailscale)
            </button>
          )
        ) : (
          <button
            type="button"
            class="link"
            onClick={() => {
              mode.value = "password";
            }}
          >
            Use password instead
          </button>
        )}
        {pairingCode.value && (
          <div class="pairing">
            <p>On the computer, allow this device.</p>
            <p>
              Or run <code>/monkey accept {pairingCode.value}</code>
            </p>
            {pairingLeft.value !== null && (
              <p class="muted">
                Expires in {Math.floor(pairingLeft.value / 60)}:
                {String(pairingLeft.value % 60).padStart(2, "0")}
              </p>
            )}
          </div>
        )}
        {error.value && <p class="error">{error.value}</p>}
        <div class="actions">
          <button type="submit" class="primary" disabled={busy.value}>
            {busy.value ? "Connecting…" : mode.value === "pair" ? "Pair" : "Connect"}
          </button>
          {busy.value && (
            <button type="button" onClick={cancel}>
              Cancel
            </button>
          )}
        </div>
      </form>
    </main>
  );
}
