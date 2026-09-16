import { createHmac } from "node:crypto";
import { describe, expect, it } from "vitest";
import { parseServerMessage } from "../../src/protocol/codec.ts";
import type { ServerMessage } from "../../src/protocol/messages.ts";
import { Handshake, type HandshakeEvent } from "../../src/transport/handshake.ts";

const password = "pw-🐒";
const serverSalt = "c2VydmVyc2FsdHNlcnZlcnNhbA==";
const keyId = "1jKl6SV7Dk7zx-ID";

function hmac(key: string, msg: string): string {
  return createHmac("sha256", key).update(msg, "utf8").digest("base64");
}

function msg(obj: Record<string, unknown>): ServerMessage {
  const parsed = parseServerMessage(JSON.stringify(obj));
  if (!parsed) throw new Error("bad test message");
  return parsed;
}

function sent(events: HandshakeEvent[]): Record<string, unknown>[] {
  return events
    .filter((e): e is Extract<HandshakeEvent, { kind: "send" }> => e.kind === "send")
    .map((e) => JSON.parse(e.text) as Record<string, unknown>);
}

const hello = (pairing = true) => msg({ type: "HELLO", salt: serverSalt, pairing, keyId });

describe("Handshake, password path", () => {
  it("signs serverSalt+clientSalt and verifies AUTH_OK", async () => {
    const hs = new Handshake({ password, pairIfNeeded: false, deviceName: " Browser " });
    const events = await hs.handle(hello());
    const [auth] = sent(events);
    expect(auth).toMatchObject({ type: "AUTH", protocolVersion: 2, deviceName: "Browser" });
    const clientSalt = auth?.salt as string;
    expect(auth?.signature).toBe(hmac(password, serverSalt + clientSalt));
    expect(hs.state).toBe("authenticating");

    const ok = await hs.handle(
      msg({
        type: "AUTH_OK",
        signature: hmac(password, clientSalt + serverSalt),
        protocolVersion: 2,
        capabilities: ["PAIRING"],
      }),
    );
    expect(ok).toEqual([
      {
        kind: "authenticated",
        keyId,
        password,
        capabilities: ["PAIRING"],
        versionWarning: null,
      },
    ]);
    expect(hs.state).toBe("done");
    expect(await hs.handle(msg({ type: "HEARTBEAT_ACK" }))).toEqual([]);
  });

  it("rejects a forged AUTH_OK signature", async () => {
    const hs = new Handshake({ password, pairIfNeeded: false });
    await hs.handle(hello());
    const events = await hs.handle(
      msg({ type: "AUTH_OK", signature: "AAAA", protocolVersion: 2, capabilities: [] }),
    );
    expect(events[0]).toMatchObject({ kind: "failed", failure: { code: "server-signature" } });
    expect(hs.state).toBe("failed");
  });

  it("prefers the password saved for the server keyId", async () => {
    const hs = new Handshake({
      password: "typed",
      pairIfNeeded: false,
      lookupPassword: (id) => (id === keyId ? "saved" : null),
    });
    const [auth] = sent(await hs.handle(hello()));
    expect(auth?.signature).toBe(hmac("saved", serverSalt + (auth?.salt as string)));
  });

  it("classifies AUTH_RESPONSE failures", async () => {
    for (const [message, code] of [
      ["Invalid signature", "invalid-signature"],
      ["Logged in from another location", "replaced"],
      ["Missing salt or signature", "auth-failed"],
    ] as const) {
      const hs = new Handshake({ password, pairIfNeeded: false });
      await hs.handle(hello());
      const events = await hs.handle(msg({ type: "AUTH_RESPONSE", success: false, message }));
      expect(events[0]).toEqual({ kind: "failed", failure: { code, message, keyId } });
    }
  });

  it("accepts the legacy AUTH_RESPONSE success", async () => {
    const hs = new Handshake({ password, pairIfNeeded: false });
    await hs.handle(hello());
    const events = await hs.handle(msg({ type: "AUTH_RESPONSE", success: true }));
    expect(events[0]).toMatchObject({ kind: "authenticated", capabilities: [] });
  });

  it("fails without a server salt", async () => {
    const hs = new Handshake({ password, pairIfNeeded: false });
    const events = await hs.handle(msg({ type: "HELLO", pairing: true }));
    expect(events[0]).toMatchObject({ kind: "failed", failure: { code: "missing-salt" } });
  });
});

describe("Handshake, pairing path", () => {
  it("pairs, then authenticates with the returned password and the same server salt", async () => {
    const hs = new Handshake({ password: "", pairIfNeeded: true, deviceName: "Phone" });
    const [pair] = sent(await hs.handle(hello(true)));
    expect(pair).toEqual({ type: "AUTH", mode: "PAIR", protocolVersion: 2, deviceName: "Phone" });
    expect(hs.state).toBe("pairing");

    const waiting = await hs.handle(msg({ type: "PAIR_WAITING", code: "ABCD2345", ttlMs: 180000 }));
    expect(waiting).toEqual([{ kind: "pairing", code: "ABCD2345", ttlMs: 180000 }]);

    const events = await hs.handle(msg({ type: "PAIR_OK", password: "granted" }));
    expect(events[0]).toEqual({ kind: "paired", keyId, password: "granted" });
    const [auth] = sent(events);
    expect(auth?.signature).toBe(hmac("granted", serverSalt + (auth?.salt as string)));
    expect(hs.state).toBe("authenticating");

    const ok = await hs.handle(
      msg({
        type: "AUTH_OK",
        signature: hmac("granted", (auth?.salt as string) + serverSalt),
        protocolVersion: 2,
        capabilities: [],
      }),
    );
    expect(ok[0]).toMatchObject({ kind: "authenticated", password: "granted" });
  });

  it("does not pair when the server forbids it", async () => {
    const hs = new Handshake({ password: "", pairIfNeeded: true });
    const events = await hs.handle(hello(false));
    expect(events).toEqual([
      {
        kind: "failed",
        failure: {
          code: "pairing-unavailable",
          message: "This address requires a password",
          keyId,
        },
      },
    ]);
  });

  it("does not pair when the caller did not ask for it", async () => {
    const hs = new Handshake({ password: "", pairIfNeeded: false });
    const events = await hs.handle(hello(true));
    expect(events[0]).toMatchObject({ kind: "failed", failure: { code: "pairing-unavailable" } });
  });

  it("surfaces PAIR_FAILED", async () => {
    const hs = new Handshake({ password: "", pairIfNeeded: true });
    await hs.handle(hello(true));
    const events = await hs.handle(
      msg({ type: "PAIR_FAILED", message: "Pairing declined on the computer" }),
    );
    expect(events[0]).toMatchObject({
      kind: "failed",
      failure: { code: "pair-failed", message: "Pairing declined on the computer" },
    });
  });

  it("rejects PAIR_OK without a password", async () => {
    const hs = new Handshake({ password: "", pairIfNeeded: true });
    await hs.handle(hello(true));
    const events = await hs.handle(msg({ type: "PAIR_OK" }));
    expect(events[0]).toMatchObject({ kind: "failed", failure: { code: "pair-failed" } });
  });
});
