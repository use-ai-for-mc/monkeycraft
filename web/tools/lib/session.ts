// Minimal Node session used by the recorder and the probe. Runs with plain
// `node tools/*.ts` (Node >= 22.6 type stripping); keep this file free of
// TypeScript-only runtime syntax (no enums, no parameter properties).

import { clientSignature, generateSalt, verifyServerSignature } from "../../src/protocol/auth.ts";
import { splitBinaryFrame } from "../../src/protocol/frames.ts";

export interface SessionEvents {
  onText?: (msg: Record<string, unknown>, raw: string, t: number) => void;
  onBinary?: (bytes: Uint8Array, t: number) => void;
  onSend?: (raw: string, t: number) => void;
  onClose?: (code: number, reason: string) => void;
}

export interface SessionOptions extends SessionEvents {
  url: string;
  password: string;
  deviceName?: string;
  timeoutMs?: number;
}

export interface Session {
  send: (obj: Record<string, unknown>) => void;
  close: () => void;
  capabilities: string[];
  keyId: string | null;
  startedAt: number;
}

export function openSession(opts: SessionOptions): Promise<Session> {
  const startedAt = Date.now();
  const now = () => Date.now() - startedAt;
  const ws = new WebSocket(opts.url);
  ws.binaryType = "arraybuffer";

  const session: Session = {
    send(obj) {
      const raw = JSON.stringify(obj);
      ws.send(raw);
      opts.onSend?.(raw, now());
    },
    close() {
      ws.close(1000, "done");
    },
    capabilities: [],
    keyId: null,
    startedAt,
  };

  return new Promise<Session>((resolve, reject) => {
    let serverSalt = "";
    let clientSalt = "";
    let settled = false;
    const timer = setTimeout(() => {
      if (!settled) {
        settled = true;
        ws.close();
        reject(new Error(`no AUTH_OK within ${opts.timeoutMs ?? 10000} ms`));
      }
    }, opts.timeoutMs ?? 10000);

    ws.addEventListener("error", (ev) => {
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(new Error(`websocket error: ${String((ev as ErrorEvent).message ?? ev.type)}`));
      }
    });
    ws.addEventListener("close", (ev) => {
      opts.onClose?.(ev.code, ev.reason);
      if (!settled) {
        settled = true;
        clearTimeout(timer);
        reject(new Error(`closed before auth: ${ev.code} ${ev.reason}`));
      }
    });
    ws.addEventListener("message", async (ev) => {
      const t = now();
      if (typeof ev.data === "string") {
        let msg: Record<string, unknown>;
        try {
          msg = JSON.parse(ev.data) as Record<string, unknown>;
        } catch {
          return;
        }
        opts.onText?.(msg, ev.data, t);
        switch (msg.type) {
          case "HELLO": {
            serverSalt = String(msg.salt ?? "");
            session.keyId = typeof msg.keyId === "string" ? msg.keyId : null;
            clientSalt = generateSalt();
            const signature = await clientSignature(opts.password, serverSalt, clientSalt);
            session.send({
              type: "AUTH",
              salt: clientSalt,
              signature,
              protocolVersion: 2,
              deviceName: opts.deviceName ?? "web-tools",
            });
            break;
          }
          case "AUTH_OK": {
            const ok = await verifyServerSignature(
              opts.password,
              serverSalt,
              clientSalt,
              String(msg.signature ?? ""),
            );
            if (!ok) {
              settled = true;
              clearTimeout(timer);
              ws.close();
              reject(new Error("server signature did not verify"));
              return;
            }
            session.capabilities = Array.isArray(msg.capabilities)
              ? msg.capabilities.map(String)
              : [];
            if (!settled) {
              settled = true;
              clearTimeout(timer);
              resolve(session);
            }
            break;
          }
          case "AUTH_RESPONSE": {
            if (msg.success !== true && !settled) {
              settled = true;
              clearTimeout(timer);
              reject(new Error(`auth failed: ${String(msg.message ?? "")}`));
            }
            break;
          }
          default:
            break;
        }
        return;
      }
      const bytes = new Uint8Array(ev.data as ArrayBuffer);
      opts.onBinary?.(bytes, t);
      if (splitBinaryFrame(bytes).kind === "video") session.send({ type: "ACK" });
    });
  });
}

export function parseArgs(argv: string[]): Record<string, string> {
  const out: Record<string, string> = {};
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a?.startsWith("--")) {
      const next = argv[i + 1];
      if (next !== undefined && !next.startsWith("--")) {
        out[a.slice(2)] = next;
        i++;
      } else {
        out[a.slice(2)] = "true";
      }
    }
  }
  return out;
}

export function clientStatus(args: Record<string, string>): Record<string, unknown> {
  return {
    type: "CLIENT_STATUS",
    mode: "STREAMING",
    width: Number(args.width ?? 360),
    height: Number(args.height ?? 640),
    colorMode: Number(args.colorMode ?? 0),
    fps: Number(args.fps ?? 10),
    dataSaver: args.dataSaver === "true",
    autoFaceMovement: false,
  };
}
