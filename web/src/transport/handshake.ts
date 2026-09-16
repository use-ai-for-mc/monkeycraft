// HELLO -> AUTH / PAIR -> AUTH_OK state machine (docs/PROTOCOL.md section 2).
// Pure: it consumes parsed server messages and returns events, one of which
// is "send". The socket layer owns I/O and timers (pairing TTL).

import { clientSignature, generateSalt, verifyServerSignature } from "../protocol/auth.ts";
import { encodeClientMessage } from "../protocol/codec.ts";
import type { ClientMessage, ServerMessage } from "../protocol/messages.ts";

export type HandshakeFailureCode =
  | "pairing-unavailable"
  | "pair-failed"
  | "invalid-signature"
  | "auth-failed"
  | "server-signature"
  | "missing-salt"
  | "replaced";

export interface HandshakeFailure {
  code: HandshakeFailureCode;
  message: string;
  keyId: string | null;
}

export type HandshakeEvent =
  | { kind: "send"; text: string }
  | { kind: "pairing"; code: string; ttlMs: number }
  | { kind: "paired"; keyId: string | null; password: string }
  | {
      kind: "authenticated";
      keyId: string | null;
      password: string;
      capabilities: string[];
      versionWarning: string | null;
    }
  | { kind: "failed"; failure: HandshakeFailure };

export interface HandshakeOptions {
  /** Password typed or saved for this server; may be empty when pairing. */
  password: string;
  /** Whether to attempt PAIR when there is no password and the server allows it. */
  pairIfNeeded: boolean;
  /** Saved password for the server's keyId; overrides `password` when present. */
  lookupPassword?: (keyId: string | null) => string | null;
  deviceName?: string;
}

export type HandshakeState = "hello" | "authenticating" | "pairing" | "done" | "failed";

export class Handshake {
  state: HandshakeState = "hello";
  keyId: string | null = null;
  private serverSalt = "";
  private clientSalt = "";
  private password: string;

  constructor(private readonly opts: HandshakeOptions) {
    this.password = opts.password;
  }

  async handle(msg: ServerMessage): Promise<HandshakeEvent[]> {
    if (this.state === "done" || this.state === "failed") return [];
    switch (msg.type) {
      case "HELLO":
        return this.onHello(msg);
      case "PAIR_WAITING":
        this.state = "pairing";
        return [{ kind: "pairing", code: msg.code, ttlMs: msg.ttlMs }];
      case "PAIR_OK":
        return this.onPairOk(msg.password);
      case "PAIR_FAILED":
        return this.fail("pair-failed", msg.message || "Pairing failed");
      case "AUTH_OK":
        return this.onAuthOk(msg);
      case "AUTH_RESPONSE":
        if (msg.success) return this.succeed([], null);
        return this.fail(classifyAuthFailure(msg.message), msg.message || "Authentication failed");
      case "ERROR":
        return this.fail("auth-failed", msg.message || "Server error");
      default:
        return [];
    }
  }

  private async onHello(msg: Extract<ServerMessage, { type: "HELLO" }>) {
    if (!msg.salt) return this.fail("missing-salt", "Server did not provide a salt");
    this.serverSalt = msg.salt;
    this.keyId = msg.keyId;
    const saved = this.opts.lookupPassword?.(msg.keyId);
    if (saved) this.password = saved;

    if (this.password === "") {
      if (this.opts.pairIfNeeded && msg.pairing) {
        this.state = "pairing";
        return [this.send({ type: "AUTH", mode: "PAIR", ...this.device() })];
      }
      return this.fail("pairing-unavailable", "This address requires a password");
    }
    return this.sendAuth();
  }

  private async onPairOk(password: string) {
    if (!password) return this.fail("pair-failed", "Pairing did not return a password");
    this.password = password;
    const events: HandshakeEvent[] = [{ kind: "paired", keyId: this.keyId, password }];
    return events.concat(await this.sendAuth());
  }

  private async sendAuth(): Promise<HandshakeEvent[]> {
    this.state = "authenticating";
    this.clientSalt = generateSalt();
    const signature = await clientSignature(this.password, this.serverSalt, this.clientSalt);
    return [this.send({ type: "AUTH", salt: this.clientSalt, signature, ...this.device() })];
  }

  private async onAuthOk(msg: Extract<ServerMessage, { type: "AUTH_OK" }>) {
    const ok = await verifyServerSignature(
      this.password,
      this.serverSalt,
      this.clientSalt,
      msg.signature,
    );
    if (!ok) return this.fail("server-signature", "Server signature did not verify");
    return this.succeed(msg.capabilities, msg.versionWarning);
  }

  private succeed(capabilities: string[], versionWarning: string | null): HandshakeEvent[] {
    this.state = "done";
    return [
      {
        kind: "authenticated",
        keyId: this.keyId,
        password: this.password,
        capabilities,
        versionWarning,
      },
    ];
  }

  private fail(code: HandshakeFailureCode, message: string): HandshakeEvent[] {
    this.state = "failed";
    return [{ kind: "failed", failure: { code, message, keyId: this.keyId } }];
  }

  private device(): { protocolVersion: 2; deviceName?: string } {
    const deviceName = this.opts.deviceName?.trim();
    return deviceName ? { protocolVersion: 2, deviceName } : { protocolVersion: 2 };
  }

  private send(msg: ClientMessage): HandshakeEvent {
    return { kind: "send", text: encodeClientMessage(msg) };
  }
}

export function classifyAuthFailure(message: string): HandshakeFailureCode {
  const m = message.toLowerCase();
  if (m.includes("invalid signature")) return "invalid-signature";
  if (m.includes("another location")) return "replaced";
  return "auth-failed";
}
