import { createHmac } from "node:crypto";
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import {
  Connection,
  ConnectionError,
  type ConnectionEvent,
} from "../../src/transport/connection.ts";
import { FakeSocket, waitFor } from "../helpers/fake-socket.ts";

const password = "secret";
const serverSalt = "c2VydmVyc2FsdHNlcnZlcnNhbA==";
const hmac = (key: string, msg: string) =>
  createHmac("sha256", key).update(msg, "utf8").digest("base64");

const SC = [0, 0, 0, 1];
const idrAu = Uint8Array.from([
  ...SC,
  0x67,
  0x42,
  0x00,
  0x28,
  ...SC,
  0x68,
  0xce,
  ...SC,
  0x65,
  0x88,
]);
const pAu = Uint8Array.from([...SC, 0x41, 0x9a]);

function setup(overrides: Partial<ConstructorParameters<typeof Connection>[0]> = {}) {
  let socket!: FakeSocket;
  const events: ConnectionEvent[] = [];
  const conn = new Connection({
    url: "ws://127.0.0.1:9600/",
    handshake: { password, pairIfNeeded: false, deviceName: "test" },
    createSocket: (url) => {
      socket = new FakeSocket(url);
      return socket;
    },
    ...overrides,
  });
  conn.on((ev) => events.push(ev));
  return { conn, socket, events };
}

async function authenticate(conn: Connection, socket: FakeSocket): Promise<void> {
  const connected = conn.connect();
  socket.open();
  socket.receiveText({ type: "HELLO", salt: serverSalt, pairing: true, keyId: "k1" });
  await waitFor(() => socket.sent.length >= 1);
  const auth = socket.sentJson()[0];
  socket.receiveText({
    type: "AUTH_OK",
    signature: hmac(password, `${auth?.salt as string}${serverSalt}`),
    protocolVersion: 2,
    capabilities: ["PLAYER_LIST", "DATA_SAVER"],
  });
  await waitFor(() => conn.authenticated);
  await connected;
}

describe("Connection", () => {
  beforeEach(() => {
    vi.useFakeTimers({
      toFake: ["setTimeout", "clearTimeout", "setInterval", "clearInterval", "Date"],
    });
  });
  afterEach(() => {
    vi.useRealTimers();
  });

  it("sets arraybuffer, authenticates, and exposes capabilities", async () => {
    const { conn, socket, events } = setup();
    expect(socket.binaryType).toBe("arraybuffer");
    await authenticate(conn, socket);
    expect(conn.authenticated).toBe(true);
    expect(conn.keyId).toBe("k1");
    expect(conn.serverSupports("DATA_SAVER")).toBe(true);
    expect(conn.boundPassword).toBe(password);
    expect(events.map((e) => e.kind)).toEqual(["authenticated"]);
  });

  it("refuses to send before authentication and sends after", async () => {
    const { conn, socket } = setup();
    expect(conn.send({ type: "PING" })).toBe(false);
    await authenticate(conn, socket);
    expect(conn.send({ type: "PING" })).toBe(true);
    expect(socket.sent.at(-1)).toBe('{"type":"PING"}');
  });

  it("ACKs every video frame on receipt, never map frames, and ignores binary before auth", async () => {
    const { conn, socket, events } = setup();
    socket.open();
    socket.receiveBinary(idrAu);
    expect(socket.sent).toEqual([]);
    await authenticate(conn, socket);
    const before = socket.sent.length;
    socket.receiveBinary(Uint8Array.from([0x4d, 0x43, 0x01, 0x68, 0x02, 0x80, ...idrAu]));
    socket.receiveBinary(pAu);
    const map = new Uint8Array(30);
    map[0] = 0x4d;
    map[1] = 0x4d;
    socket.receiveBinary(map);
    expect(socket.sent.slice(before)).toEqual(['{"type":"ACK"}', '{"type":"ACK"}']);
    const video = events.filter((e) => e.kind === "video");
    expect(video).toHaveLength(2);
    expect(video[0]).toMatchObject({ frame: { width: 360, height: 640 } });
    expect(events.some((e) => e.kind === "map")).toBe(true);
  });

  it("dispatches post-auth messages and feeds HEARTBEAT_ACK to the heartbeat", async () => {
    const { conn, socket, events } = setup();
    await authenticate(conn, socket);
    socket.receiveText({ type: "SCREEN_STATE", isOpen: true });
    expect(events.at(-1)).toEqual({ kind: "message", msg: { type: "SCREEN_STATE", isOpen: true } });

    vi.advanceTimersByTime(3000);
    expect(socket.sent.at(-1)).toBe('{"type":"HEARTBEAT"}');
    socket.receiveText({ type: "HEARTBEAT_ACK" });
    vi.advanceTimersByTime(5000);
    expect(events.some((e) => e.kind === "heartbeat-lost")).toBe(false);
    expect(conn.authenticated).toBe(true);
  });

  it("closes with heartbeat-lost when the ack never comes", async () => {
    const { conn, socket, events } = setup();
    await authenticate(conn, socket);
    vi.advanceTimersByTime(3000);
    vi.advanceTimersByTime(5000);
    expect(events.map((e) => e.kind).slice(-2)).toEqual(["heartbeat-lost", "closed"]);
    expect(events.at(-1)).toMatchObject({ kind: "closed", wasAuthenticated: true, failure: null });
    expect(conn.authenticated).toBe(false);
    expect(socket.closedWith?.reason).toBe("heartbeat timeout");
  });

  it("does not heartbeat while hidden", async () => {
    const { conn, socket } = setup();
    await authenticate(conn, socket);
    conn.setHidden(true);
    vi.advanceTimersByTime(60_000);
    expect(socket.sent.filter((s) => s.includes("HEARTBEAT"))).toEqual([]);
    conn.setHidden(false);
    vi.advanceTimersByTime(3000);
    expect(socket.sent.at(-1)).toBe('{"type":"HEARTBEAT"}');
  });

  it("rejects connect() with the handshake failure and closes the socket", async () => {
    const { conn, socket, events } = setup();
    const connected = conn.connect();
    connected.catch(() => {});
    socket.open();
    socket.receiveText({ type: "HELLO", salt: serverSalt, pairing: true, keyId: "k1" });
    await waitFor(() => socket.sent.length >= 1);
    socket.receiveText({ type: "AUTH_RESPONSE", success: false, message: "Invalid signature" });
    await waitFor(() => socket.readyState === 3);
    await expect(connected).rejects.toMatchObject({
      code: "handshake",
      failure: { code: "invalid-signature", keyId: "k1" },
    });
    expect(socket.readyState).toBe(3);
    expect(events.at(-1)).toMatchObject({
      kind: "closed",
      wasAuthenticated: false,
      failure: { code: "invalid-signature" },
    });
  });

  it("surfaces pairing events and completes after PAIR_OK", async () => {
    const { conn, socket, events } = setup({
      handshake: { password: "", pairIfNeeded: true },
    });
    const connected = conn.connect();
    socket.open();
    socket.receiveText({ type: "HELLO", salt: serverSalt, pairing: true, keyId: "k1" });
    await waitFor(() => socket.sent.length >= 1);
    expect(socket.sentJson()[0]).toMatchObject({ type: "AUTH", mode: "PAIR" });
    socket.receiveText({ type: "PAIR_WAITING", code: "ABCD2345", ttlMs: 180000 });
    await waitFor(() => events.some((e) => e.kind === "pairing"));
    expect(events.at(-1)).toEqual({ kind: "pairing", code: "ABCD2345", ttlMs: 180000 });
    socket.receiveText({ type: "PAIR_OK", password: "granted" });
    await waitFor(() => socket.sent.length >= 2);
    expect(events.at(-1)).toEqual({ kind: "paired", keyId: "k1", password: "granted" });
    const auth = socket.sentJson()[1];
    socket.receiveText({
      type: "AUTH_OK",
      signature: hmac("granted", `${auth?.salt as string}${serverSalt}`),
      protocolVersion: 2,
      capabilities: [],
    });
    await waitFor(() => conn.authenticated);
    await expect(connected).resolves.toBeUndefined();
    expect(conn.boundPassword).toBe("granted");
  });

  it("times out when HELLO never arrives", async () => {
    const { conn, socket } = setup({ connectTimeoutMs: 5000 });
    const connected = conn.connect();
    connected.catch(() => {});
    socket.open();
    vi.advanceTimersByTime(5000);
    await expect(connected).rejects.toBeInstanceOf(ConnectionError);
    await expect(connected).rejects.toMatchObject({ code: "timeout" });
    expect(socket.readyState).toBe(3);
  });

  it("rejects connect() when the server closes first", async () => {
    const { conn, socket } = setup();
    const connected = conn.connect();
    connected.catch(() => {});
    socket.open();
    socket.serverClose(1000, "Connection not allowed");
    await expect(connected).rejects.toMatchObject({ code: "closed" });
  });

  it("reports a server-initiated close after auth", async () => {
    const { conn, socket, events } = setup();
    await authenticate(conn, socket);
    socket.serverClose(1006, "");
    expect(events.at(-1)).toEqual({
      kind: "closed",
      code: 1006,
      reason: "",
      wasAuthenticated: true,
      failure: null,
    });
    expect(conn.send({ type: "PING" })).toBe(false);
  });
});
