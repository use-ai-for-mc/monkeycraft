// Fake mod: replays a recorded fixture over ws:// so the whole app can be
// driven without Minecraft. Speaks the same handshake as the real server
// (docs/PROTOCOL.md), honours ACK backpressure, and exposes test controls.
//
//   node tools/replay-server.ts --port 9601 --fixture streaming-360x640 --password test
//
// HTTP on the same port:
//   GET /health            -> ok
//   GET /log               -> JSON array of client messages received since the last /log
//   GET /state             -> JSON {clients, streaming, framesSent, dropped}
// Test controls, sent by the client as RUN_COMMAND:
//   /replay screen open|close   /replay hibernate on|off   /replay nudge <text>
//   /replay disconnect          /replay close <code>       /replay world menu|inworld

import { createHmac, randomBytes } from "node:crypto";
import { createServer } from "node:http";
import { WebSocket, WebSocketServer } from "ws";
import { containsIdr } from "../src/protocol/h264.ts";
import { listFixtures, loadFixture } from "../test/helpers/fixture.ts";
import { parseArgs } from "./lib/session.ts";

const args = parseArgs(process.argv.slice(2));
const port = Number(args.port ?? 9601);
const password = args.password ?? "test";
const fps = Number(args.fps ?? 10);
const fixtureName = args.fixture ?? "streaming-360x640";
if (!listFixtures().includes(fixtureName)) {
  console.error(`unknown fixture ${fixtureName}; have ${listFixtures().join(", ")}`);
  process.exit(2);
}
const fixture = loadFixture(fixtureName);

interface Frame {
  au: Uint8Array;
  idr: boolean;
  width: number;
  height: number;
}
const frames: Frame[] = [];
let lastSize = { width: 360, height: 640 };
for (const line of fixture.lines) {
  if ("text" in line || line.bin.kind !== "video") continue;
  const bytes = fixture.binary.subarray(line.bin.offset, line.bin.offset + line.bin.length);
  const header = line.bin.header;
  if (header) lastSize = { width: header[0], height: header[1] };
  const au = header ? bytes.subarray(6) : bytes;
  frames.push({ au, idr: containsIdr(au), ...lastSize });
}
if (frames.length === 0) {
  console.error("fixture has no video frames");
  process.exit(2);
}

const hmac = (key: string, msg: string) =>
  createHmac("sha256", key).update(msg, "utf8").digest("base64");

const log: Array<{ t: number; tag: string; msg: Record<string, unknown> }> = [];
const state = { clients: 0, streaming: false, framesSent: 0, dropped: 0 };

class Client {
  serverSalt = randomBytes(16).toString("base64");
  authed = false;
  streaming = false;
  hibernating = false;
  screenOpen = false;
  pending = 0;
  needsIdr = true;
  cursor = 0;
  timer: ReturnType<typeof setInterval> | null = null;

  readonly ws: WebSocket;
  readonly tag: string;

  constructor(ws: WebSocket, tag: string) {
    this.ws = ws;
    this.tag = tag;
  }

  send(obj: Record<string, unknown>) {
    if (this.ws.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(obj));
  }

  serverStatus() {
    this.send({
      type: "SERVER_STATUS",
      videoState: this.hibernating ? "HIBERNATING" : "ACTIVE",
      ...(this.hibernating ? { message: "Riding Test Ride (10%)\n1m left" } : {}),
      timedFireAtEpochMs: null,
    });
  }

  tick() {
    if (!this.streaming || this.hibernating || this.ws.readyState !== WebSocket.OPEN) return;
    if (this.pending > 1) {
      this.needsIdr = true;
      state.dropped += 1;
      return;
    }
    let frame = frames[this.cursor % frames.length] as Frame;
    if (this.needsIdr) {
      // Advance to the next IDR, like a freshly created encoder.
      let guard = 0;
      while (!frame.idr && guard++ < frames.length) {
        this.cursor += 1;
        frame = frames[this.cursor % frames.length] as Frame;
      }
    }
    this.cursor += 1;
    let payload: Uint8Array = frame.au;
    if (this.needsIdr && frame.idr) {
      const out = new Uint8Array(6 + frame.au.length);
      out.set([
        0x4d,
        0x43,
        frame.width >> 8,
        frame.width & 0xff,
        frame.height >> 8,
        frame.height & 0xff,
      ]);
      out.set(frame.au, 6);
      payload = out;
      this.needsIdr = false;
    }
    this.ws.send(payload);
    this.pending += 1;
    state.framesSent += 1;
  }

  onMessage(raw: string) {
    let msg: Record<string, unknown>;
    try {
      msg = JSON.parse(raw) as Record<string, unknown>;
    } catch {
      this.send({ type: "ERROR", message: "Invalid JSON" });
      return;
    }
    log.push({ t: Date.now(), tag: this.tag, msg });
    const type = String(msg.type);
    if (type === "AUTH") return this.onAuth(msg);
    if (!this.authed) {
      this.send({ type: "ERROR", message: "Unauthorized" });
      this.ws.close(1000);
      return;
    }
    switch (type) {
      case "ACK":
        this.pending = Math.max(0, this.pending - 1);
        break;
      case "CLIENT_STATUS": {
        const mode = msg.mode === "CHAT" || msg.mode === "MAP" ? msg.mode : "STREAMING";
        this.streaming = mode !== "CHAT";
        state.streaming = this.streaming;
        this.pending = 0;
        this.needsIdr = true;
        this.serverStatus();
        break;
      }
      case "REQUEST_KEYFRAME":
        this.pending = 0;
        this.needsIdr = true;
        break;
      case "HEARTBEAT":
        this.send({ type: "HEARTBEAT_ACK" });
        break;
      case "PING":
        this.serverStatus();
        break;
      case "SUBSCRIBE_CHAT":
        this.send({
          type: "CACHED_CHAT_MESSAGES",
          messages: [
            {
              sender: "System",
              segments: [{ text: "Welcome to the replay server" }],
              timestamp: 1,
            },
            {
              sender: "Alice",
              senderUuid: "u-alice",
              segments: [
                { text: "hi ", color: "#55FF55", bold: true },
                { text: "click me", clickEvent: { action: "suggest_command", value: "/warp hub" } },
              ],
              timestamp: 2,
            },
          ],
        });
        break;
      case "GET_PLAYER_COUNT":
        this.send({ type: "PLAYER_COUNT", count: 42 });
        break;
      case "GET_PLAYER_LIST":
        this.send({ type: "PLAYER_LIST", count: 2, players: ["Alice", "Bob"] });
        break;
      case "LIST_SERVERS":
        this.send({
          type: "SERVER_LIST",
          servers: [{ index: 0, name: "Replay", address: "replay.example:25565" }],
        });
        break;
      case "JOIN_SERVER":
        this.send({ type: "JOIN_RESULT", ok: true });
        this.send({
          type: "WORLD_STATE",
          phase: "IN_WORLD",
          serverName: "Replay",
          singleplayer: false,
        });
        break;
      case "LOOK_DELTA":
      case "GET_PLAYER_POSE":
        this.send({ type: "PLAYER_POSE", yaw: 0, pitch: 0 });
        break;
      case "SEND_CHAT":
        this.send({
          type: "CHAT_MESSAGE",
          sender: "You",
          senderUuid: "u-you",
          segments: [{ text: String(msg.message ?? "") }],
          timestamp: Date.now(),
        });
        break;
      case "RUN_COMMAND":
        this.control(String(msg.command ?? ""));
        break;
      default:
        break;
    }
  }

  onAuth(msg: Record<string, unknown>) {
    if (msg.mode === "PAIR") {
      this.send({ type: "PAIR_WAITING", code: "ABCD2345", ttlMs: 180000 });
      setTimeout(() => this.send({ type: "PAIR_OK", password }), 300);
      return;
    }
    const clientSalt = String(msg.salt ?? "");
    if (!clientSalt || msg.signature !== hmac(password, this.serverSalt + clientSalt)) {
      this.send({ type: "AUTH_RESPONSE", success: false, message: "Invalid signature" });
      this.ws.close(1000);
      return;
    }
    this.authed = true;
    this.send({
      type: "AUTH_OK",
      signature: hmac(password, clientSalt + this.serverSalt),
      protocolVersion: 2,
      capabilities: ["PLAYER_LIST", "DATA_SAVER", "PAIRING", "KEY_ID"],
    });
    this.send({ type: "SCREEN_STATE", isOpen: this.screenOpen });
    this.send({
      type: "WORLD_STATE",
      phase: "IN_WORLD",
      serverName: "Replay",
      singleplayer: false,
    });
    this.timer = setInterval(() => this.tick(), Math.round(1000 / fps));
  }

  control(command: string) {
    const [head, verb, ...rest] = command.trim().split(/\s+/);
    if (head !== "/replay") return;
    switch (verb) {
      case "screen":
        this.screenOpen = rest[0] === "open";
        this.pending = 0;
        this.needsIdr = true;
        this.send({ type: "SCREEN_STATE", isOpen: this.screenOpen });
        break;
      case "hibernate":
        this.hibernating = rest[0] === "on";
        if (!this.hibernating) this.needsIdr = true;
        this.serverStatus();
        break;
      case "world":
        this.send({
          type: "WORLD_STATE",
          phase: rest[0] === "menu" ? "MENU" : "IN_WORLD",
          serverName: rest[0] === "menu" ? undefined : "Replay",
          singleplayer: false,
        });
        break;
      case "nudge":
        this.send({ type: "NUDGE", title: "Replay", body: rest.join(" ") || "nudge", sound: true });
        break;
      case "disconnect":
        this.send({ type: "DISCONNECT", reason: "server_disconnect" });
        this.ws.close(1000);
        break;
      case "close":
        this.ws.close(Number(rest[0] ?? 1006));
        break;
      default:
        this.send({ type: "COMMAND_DENIED", command });
    }
  }

  dispose() {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
    if (this.authed) state.streaming = false;
  }
}

const http = createServer((req, res) => {
  const url = req.url ?? "/";
  res.setHeader("Access-Control-Allow-Origin", "*");
  if (url.startsWith("/health")) {
    res.end("ok");
  } else if (url.startsWith("/log")) {
    // Drain messages for one tag (connections are tagged by ?tag= on the ws URL).
    const tag = new URL(url, "http://x").searchParams.get("tag") ?? "";
    const out: typeof log = [];
    for (let i = log.length - 1; i >= 0; i--) {
      if ((log[i] as { tag: string }).tag === tag) out.unshift(...log.splice(i, 1));
    }
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify(out));
  } else if (url.startsWith("/state")) {
    res.setHeader("Content-Type", "application/json");
    res.end(JSON.stringify(state));
  } else {
    res.statusCode = 404;
    res.end("Not Found");
  }
});

const wss = new WebSocketServer({ server: http });
wss.on("connection", (ws, req) => {
  const tag = new URL(req.url ?? "/", "http://x").searchParams.get("tag") ?? "";
  const client = new Client(ws, tag);
  state.clients += 1;
  client.send({ type: "HELLO", salt: client.serverSalt, pairing: true, keyId: "replay-key" });
  ws.on("message", (data, isBinary) => {
    if (!isBinary) client.onMessage(data.toString());
  });
  ws.on("close", () => {
    state.clients -= 1;
    client.dispose();
  });
});

http.listen(port, "127.0.0.1", () => {
  console.log(
    `replay server on ws://127.0.0.1:${port}/ fixture=${fixtureName} frames=${frames.length} fps=${fps} password=${password}`,
  );
});
