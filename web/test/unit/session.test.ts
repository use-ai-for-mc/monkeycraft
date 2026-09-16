import { describe, expect, it } from "vitest";
import { parseServerMessage } from "../../src/protocol/codec.ts";
import type { ServerMessage } from "../../src/protocol/messages.ts";
import { computeStreamSize, containRect, shouldRenegotiate } from "../../src/session/resolution.ts";
import {
  deriveView,
  initialSession,
  reduceSession,
  type SessionState,
} from "../../src/session/session.ts";
import type { ConnectionEvent } from "../../src/transport/connection.ts";
import { isText, loadFixture } from "../helpers/fixture.ts";

const now = 1_000_000;

function apply(state: SessionState, ...events: ConnectionEvent[]): SessionState {
  return events.reduce((s, event) => reduceSession(s, { type: "connection", event, now }), state);
}

function message(msg: ServerMessage): ConnectionEvent {
  return { kind: "message", msg };
}

describe("computeStreamSize", () => {
  it("applies DPR and preset scale and rounds down to even", () => {
    expect(
      computeStreamSize({ cssWidth: 393, cssHeight: 852, devicePixelRatio: 3, preset: "high" }),
    ).toEqual({ width: 590, height: 1280 });
    expect(
      computeStreamSize({ cssWidth: 393, cssHeight: 852, devicePixelRatio: 3, preset: "medium" }),
    ).toEqual({ width: 442, height: 960 });
    expect(
      computeStreamSize({ cssWidth: 393, cssHeight: 852, devicePixelRatio: 3, preset: "low" }),
    ).toEqual({ width: 294, height: 640 });
  });

  it("caps the long edge and keeps aspect", () => {
    const s = computeStreamSize({
      cssWidth: 1920,
      cssHeight: 1080,
      devicePixelRatio: 2,
      preset: "high",
    });
    expect(s).toEqual({ width: 1280, height: 720 });
  });

  it("never goes below 2 or above 1920", () => {
    expect(
      computeStreamSize({ cssWidth: 1, cssHeight: 1, devicePixelRatio: 1, preset: "low" }),
    ).toEqual({
      width: 2,
      height: 2,
    });
    expect(
      computeStreamSize({ cssWidth: 0, cssHeight: 0, devicePixelRatio: 0, preset: "high" }),
    ).toEqual({ width: 2, height: 2 });
  });
});

describe("shouldRenegotiate", () => {
  const base = { cssWidth: 400, cssHeight: 800, devicePixelRatio: 2, preset: "medium" as const };
  const baseSize = computeStreamSize(base);

  it("always on first call", () => {
    expect(shouldRenegotiate(null, null, base)).toBe(true);
  });

  it("ignores small jitter even when the even size would change", () => {
    expect(shouldRenegotiate(base, baseSize, { ...base, cssWidth: 430 })).toBe(false);
  });

  it("renegotiates on a large change that yields a new size", () => {
    expect(shouldRenegotiate(base, baseSize, { ...base, cssWidth: 800 })).toBe(true);
  });

  it("does not renegotiate a large change that lands on the same size", () => {
    const capped = { cssWidth: 2000, cssHeight: 4000, devicePixelRatio: 1, preset: "low" as const };
    const cappedSize = computeStreamSize(capped);
    expect(
      shouldRenegotiate(capped, cappedSize, { ...capped, cssWidth: 2500, cssHeight: 5000 }),
    ).toBe(false);
  });
});

describe("containRect", () => {
  it("letterboxes and pillarboxes", () => {
    expect(containRect({ width: 360, height: 640 }, { width: 1000, height: 1000 })).toEqual({
      x: 218.75,
      y: 0,
      width: 562.5,
      height: 1000,
    });
    expect(containRect({ width: 640, height: 360 }, { width: 1000, height: 1000 })).toEqual({
      x: 0,
      y: 218.75,
      width: 1000,
      height: 562.5,
    });
    expect(containRect({ width: 0, height: 0 }, { width: 10, height: 10 }).width).toBe(0);
  });
});

describe("reduceSession", () => {
  it("walks connect → pairing → authenticated", () => {
    let s = reduceSession(initialSession, { type: "connect" });
    expect(s.link).toEqual({ phase: "connecting" });
    s = apply(s, { kind: "pairing", code: "ABCD2345", ttlMs: 180000 });
    expect(s.link).toEqual({ phase: "pairing", code: "ABCD2345", expiresAt: now + 180000 });
    s = apply(s, { kind: "authenticated", keyId: "k", capabilities: ["PAIRING"] });
    expect(s.link).toEqual({ phase: "connected" });
    expect(s.capabilities).toEqual(["PAIRING"]);
    expect(deriveView(s).serverSupports("PAIRING")).toBe(true);
  });

  it("tracks server size only from headers and only on change", () => {
    const au = new Uint8Array(0);
    let s = apply(initialSession, { kind: "video", frame: { kind: "video", au }, bytes: 0 });
    expect(s.serverSize).toBeNull();
    s = apply(s, {
      kind: "video",
      frame: { kind: "video", au, width: 360, height: 640 },
      bytes: 0,
    });
    const ref = s;
    s = apply(s, {
      kind: "video",
      frame: { kind: "video", au, width: 360, height: 640 },
      bytes: 0,
    });
    expect(s).toBe(ref);
    s = apply(s, {
      kind: "video",
      frame: { kind: "video", au, width: 720, height: 1280 },
      bytes: 0,
    });
    expect(s.serverSize).toEqual({ width: 720, height: 1280 });
  });

  it("closed after failure keeps the failure; plain close goes idle", () => {
    const failure = {
      code: "invalid-signature" as const,
      message: "Invalid signature",
      keyId: "k",
    };
    let s = apply(initialSession, {
      kind: "closed",
      code: 1000,
      reason: "",
      wasAuthenticated: false,
      failure,
    });
    expect(s.link).toEqual({ phase: "failed", failure, message: "Invalid signature" });
    s = apply(apply(initialSession, { kind: "authenticated", keyId: null, capabilities: [] }), {
      kind: "closed",
      code: 1006,
      reason: "",
      wasAuthenticated: true,
      failure: null,
    });
    expect(s.link).toEqual({ phase: "idle" });
  });

  it("a close while reconnecting does not override the reconnecting phase", () => {
    let s = reduceSession(initialSession, { type: "reconnecting", attempt: 1 });
    s = apply(s, {
      kind: "closed",
      code: 1006,
      reason: "",
      wasAuthenticated: false,
      failure: null,
    });
    expect(s.link).toEqual({ phase: "reconnecting", attempt: 1 });
  });

  it("derives hibernation, timed, screen and world from messages", () => {
    const connected = apply(initialSession, {
      kind: "authenticated",
      keyId: null,
      capabilities: [],
    });
    const s = apply(
      connected,
      message({ type: "SCREEN_STATE", isOpen: true }),
      message({
        type: "WORLD_STATE",
        phase: "IN_WORLD",
        serverName: "ImagineFun!",
        serverAddress: "mp",
        singleplayer: false,
      }),
      message({
        type: "SERVER_STATUS",
        videoState: "HIBERNATING",
        message: "Riding",
        timed: { fireAtEpochMs: 5, title: "t", body: null, sound: true, countDownText: null },
      }),
    );
    expect(s.screenOpen).toBe(true);
    expect(s.world).toEqual({ phase: "IN_WORLD", serverName: "ImagineFun!", serverAddress: "mp" });
    expect(s.hibernating).toBe(true);
    expect(s.hibernationMessage).toBe("Riding");
    expect(s.timed?.fireAtEpochMs).toBe(5);
    const view = deriveView(s);
    expect(view.showVideo).toBe(false);
    expect(view.showHibernation).toBe(true);
    expect(view.inWorld).toBe(true);

    const active = apply(
      s,
      message({ type: "SERVER_STATUS", videoState: "ACTIVE", message: null, timed: null }),
    );
    expect(active.hibernating).toBe(false);
    expect(active.hibernationMessage).toBeNull();
    expect(active.timed).toBeNull();
    expect(deriveView(active).showVideo).toBe(true);
    expect(deriveView(reduceSession(active, { type: "set-mode", mode: "CHAT" })).showVideo).toBe(
      false,
    );
  });

  it("records DISCONNECT and nudges", () => {
    let s = apply(initialSession, message({ type: "DISCONNECT", reason: "server_disconnect" }));
    expect(s.disconnectReason).toBe("server_disconnect");
    s = apply(s, message({ type: "NUDGE", title: "Hi", body: "there", sound: true }));
    expect(s.nudge).toMatchObject({ title: "Hi", body: "there" });
    expect(reduceSession(s, { type: "dismiss-nudge" }).nudge).toBeNull();
  });

  it("replays the hibernating fixture into a hibernating, in-world state", () => {
    const fixture = loadFixture("hibernating");
    let s = apply(initialSession, { kind: "authenticated", keyId: "k", capabilities: [] });
    for (const line of fixture.lines) {
      if (!isText(line) || line.dir !== "in") continue;
      const msg = parseServerMessage(line.text);
      if (msg) s = apply(s, message(msg));
    }
    expect(s.hibernating).toBe(true);
    expect(s.hibernationMessage).toMatch(/Riding/);
    expect(s.timed?.title).toBe("Ride finished");
    expect(s.world?.phase).toBe("IN_WORLD");
    expect(s.screenOpen).toBe(false);
  });
});
