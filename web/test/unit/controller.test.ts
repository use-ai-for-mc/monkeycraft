import { createHmac } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { SessionController } from "../../src/session/controller.ts";
import { defaultSettings, type Settings } from "../../src/session/settings.ts";
import { CredentialStore, MemoryStorage } from "../../src/session/storage.ts";
import { FakeSocket, waitFor } from "../helpers/fake-socket.ts";

const serverSalt = "c2VydmVyc2FsdHNlcnZlcnNhbA==";
const flush = async () => {
  for (let i = 0; i < 10; i++) await Promise.resolve();
};
const hmac = (key: string, msg: string) =>
  createHmac("sha256", key).update(msg, "utf8").digest("base64");

function harness(settings: Partial<Settings> = {}) {
  const sockets: FakeSocket[] = [];
  const store = new CredentialStore(new MemoryStorage());
  const ctl = new SessionController({
    credentials: store,
    settings: () => ({ ...defaultSettings, ...settings }),
    createSocket: (url) => {
      const s = new FakeSocket(url);
      sockets.push(s);
      return s;
    },
  });
  return { ctl, store, sockets, last: () => sockets[sockets.length - 1] as FakeSocket };
}

async function serverAuth(socket: FakeSocket, password: string, keyId = "k1"): Promise<void> {
  socket.open();
  socket.receiveText({ type: "HELLO", salt: serverSalt, pairing: true, keyId });
  await waitFor(() => socket.sent.length >= 1);
  const auth = socket.sentJson()[0];
  socket.receiveText({
    type: "AUTH_OK",
    signature: hmac(password, `${auth?.salt as string}${serverSalt}`),
    protocolVersion: 2,
    capabilities: ["DATA_SAVER"],
  });
  await waitFor(() => socket.sent.length >= 2);
}

describe("SessionController", () => {
  beforeEach(() => {
    vi.useFakeTimers({
      toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("dials the ws URL, binds the password, and sends CLIENT_STATUS once a size is known", async () => {
    const { ctl, store, last } = harness({ fps: 15, dataSaver: true });
    const connected = ctl.connect({
      server: "192.168.0.3:9600",
      password: "pw",
      pairIfNeeded: false,
    });
    expect(last().url).toBe("ws://192.168.0.3:9600");
    await serverAuth(last(), "pw");
    await connected;
    expect(ctl.snapshot.link).toEqual({ phase: "connected" });
    expect(store.lookup("192.168.0.3:9600", "k1")).toBe("pw");
    // Without a requested size the status carries only mode + autoFaceMovement.
    expect(last().sentJson()[1]).toEqual({
      type: "CLIENT_STATUS",
      mode: "STREAMING",
      autoFaceMovement: false,
    });
    ctl.setRequestedSize({ width: 360, height: 640 });
    expect(last().sentJson()[2]).toEqual({
      type: "CLIENT_STATUS",
      mode: "STREAMING",
      width: 360,
      height: 640,
      colorMode: 0,
      fps: 15,
      dataSaver: true,
      autoFaceMovement: false,
    });
    ctl.setMode("CHAT");
    expect(last().sentJson()[3]).toEqual({
      type: "CLIENT_STATUS",
      mode: "CHAT",
      autoFaceMovement: false,
    });
  });

  it("fans out video access units with the header size", async () => {
    const { ctl, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;
    const seen: Array<[number, { width: number; height: number } | null]> = [];
    ctl.onVideo((au, header) => seen.push([au.length, header]));
    last().receiveBinary(Uint8Array.from([0x4d, 0x43, 0x01, 0x68, 0x02, 0x80, 0, 0, 0, 1, 0x65]));
    last().receiveBinary(Uint8Array.from([0, 0, 0, 1, 0x41]));
    expect(seen).toEqual([
      [5, { width: 360, height: 640 }],
      [5, null],
    ]);
    expect(ctl.snapshot.serverSize).toEqual({ width: 360, height: 640 });
  });

  it("reconnects with backoff after an authenticated close and re-syncs status", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;
    ctl.setRequestedSize({ width: 360, height: 640 });

    last().serverClose(1006, "");
    expect(ctl.snapshot.link).toEqual({ phase: "reconnecting", attempt: 1 });
    expect(sockets).toHaveLength(1);
    vi.advanceTimersByTime(1000);
    expect(sockets).toHaveLength(2);
    await serverAuth(last(), "pw");
    expect(ctl.snapshot.link).toEqual({ phase: "connected" });
    expect(last().sentJson()[1]).toMatchObject({ type: "CLIENT_STATUS", width: 360, height: 640 });
  });

  it("gives up after three failed reconnects", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;
    last().serverClose(1006, "");
    for (const delay of [1000, 2000, 4000]) {
      vi.advanceTimersByTime(delay);
      last().serverClose(1006, "");
      await flush();
    }
    expect(sockets).toHaveLength(4);
    expect(ctl.snapshot.link).toMatchObject({ phase: "failed", failure: null });
  });

  it("does not reconnect after a server DISCONNECT or an intentional close", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;
    last().receiveText({ type: "DISCONNECT", reason: "server_disconnect" });
    last().serverClose(1000, "");
    vi.advanceTimersByTime(10_000);
    expect(sockets).toHaveLength(1);
    expect(ctl.snapshot.disconnectReason).toBe("server_disconnect");

    const again = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await again;
    ctl.disconnect();
    vi.advanceTimersByTime(10_000);
    expect(sockets).toHaveLength(2);
    expect(last().closedWith?.code).toBe(1000);
  });

  it("forgets a saved password the server rejects", async () => {
    const { ctl, store, last } = harness();
    store.bind("k1", "stale", "a:1");
    const connected = ctl.connect({ server: "a:1", password: "", pairIfNeeded: false });
    connected.catch(() => {});
    last().open();
    last().receiveText({ type: "HELLO", salt: serverSalt, pairing: true, keyId: "k1" });
    await waitFor(() => last().sent.length >= 1);
    last().receiveText({ type: "AUTH_RESPONSE", success: false, message: "Invalid signature" });
    await waitFor(() => last().readyState === 3);
    await expect(connected).rejects.toMatchObject({ failure: { code: "invalid-signature" } });
    expect(store.lookup("a:1", "k1")).toBeNull();
    expect(ctl.snapshot.link).toMatchObject({ phase: "failed" });
  });
  it("pauses a hidden reconnect without spending the retry budget", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;

    ctl.setHidden(true);
    last().serverClose(1006, "");
    expect(ctl.snapshot.link).toEqual({ phase: "reconnecting", attempt: 1 });
    vi.advanceTimersByTime(60_000);
    expect(sockets).toHaveLength(1);

    ctl.setHidden(false);
    vi.advanceTimersByTime(999);
    expect(sockets).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(sockets).toHaveLength(2);
  });

  it("restarts a pending delay when the page hides midway through reconnecting", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;

    last().serverClose(1006, "");
    vi.advanceTimersByTime(500);
    ctl.setHidden(true);
    vi.advanceTimersByTime(60_000);
    expect(sockets).toHaveLength(1);

    ctl.setHidden(false);
    vi.advanceTimersByTime(999);
    expect(sockets).toHaveLength(1);
    vi.advanceTimersByTime(1);
    expect(sockets).toHaveLength(2);
  });

  it("does not resume a hidden reconnect after explicit disconnect", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;

    ctl.setHidden(true);
    last().serverClose(1006, "");
    ctl.disconnect();
    ctl.setHidden(false);
    vi.advanceTimersByTime(60_000);
    expect(sockets).toHaveLength(1);
  });

  it("keeps reconnecting when an in-flight retry closes while hidden", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;

    last().serverClose(1006, "");
    vi.advanceTimersByTime(1000);
    expect(sockets).toHaveLength(2);
    ctl.setHidden(true);
    last().serverClose(1006, "");
    expect(ctl.snapshot.link).toEqual({ phase: "reconnecting", attempt: 2 });
    vi.advanceTimersByTime(60_000);
    expect(sockets).toHaveLength(2);

    ctl.setHidden(false);
    vi.advanceTimersByTime(2000);
    expect(sockets).toHaveLength(3);
  });

  it("does not schedule after disconnect during an in-flight retry", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;

    last().serverClose(1006, "");
    vi.advanceTimersByTime(1000);
    expect(sockets).toHaveLength(2);
    ctl.disconnect();
    last().serverClose(1006, "");
    vi.advanceTimersByTime(60_000);
    expect(sockets).toHaveLength(2);
  });

  it("ignores a late retry close after connecting to a new target", async () => {
    const { ctl, sockets, last } = harness();
    const connected = ctl.connect({ server: "a:1", password: "pw", pairIfNeeded: false });
    await serverAuth(last(), "pw");
    await connected;

    last().serverClose(1006, "");
    vi.advanceTimersByTime(1000);
    const stale = last();
    const replacement = ctl.connect({ server: "b:2", password: "next", pairIfNeeded: false });
    expect(sockets).toHaveLength(3);
    stale.serverClose(1006, "");
    await serverAuth(last(), "next");
    await replacement;
    vi.advanceTimersByTime(2000);
    expect(sockets).toHaveLength(3);
    expect(ctl.snapshot.link).toEqual({ phase: "connected" });
  });
});
