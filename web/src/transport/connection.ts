// One authenticated WebSocket session with the mod. Owns the socket, runs the
// handshake, answers video frames with ACK, drives the heartbeat, and hands
// everything else to listeners as typed events. No reconnect logic here; the
// session layer decides whether to open a new Connection.

import { encodeClientMessage, parseServerMessage } from "../protocol/codec.ts";
import { type MapFrame, splitBinaryFrame, type VideoFrame } from "../protocol/frames.ts";
import type { ClientMessage, ServerMessage } from "../protocol/messages.ts";
import { Handshake, type HandshakeFailure, type HandshakeOptions } from "./handshake.ts";
import { Heartbeat, type HeartbeatOptions } from "./heartbeat.ts";

/** The subset of WebSocket this class needs; lets tests inject a fake. */
export interface SocketLike {
  binaryType: string;
  readyState: number;
  send(data: string): void;
  close(code?: number, reason?: string): void;
  addEventListener(type: "open", listener: () => void): void;
  addEventListener(type: "message", listener: (ev: { data: unknown }) => void): void;
  addEventListener(type: "close", listener: (ev: { code: number; reason: string }) => void): void;
  addEventListener(type: "error", listener: () => void): void;
}

export interface ConnectionOptions {
  url: string;
  handshake: HandshakeOptions;
  createSocket?: (url: string) => SocketLike;
  heartbeat?: HeartbeatOptions;
  /** Time allowed for the socket to open and HELLO to arrive. */
  connectTimeoutMs?: number;
  /** Time allowed for the whole handshake; pairing needs a human, so default is long. */
  authTimeoutMs?: number;
}

export type ConnectionEvent =
  | { kind: "message"; msg: ServerMessage }
  | { kind: "video"; frame: VideoFrame; bytes: number }
  | { kind: "map"; frame: MapFrame }
  | { kind: "pairing"; code: string; ttlMs: number }
  | { kind: "paired"; keyId: string | null; password: string }
  | { kind: "authenticated"; keyId: string | null; capabilities: string[] }
  | { kind: "heartbeat-lost" }
  | {
      kind: "closed";
      code: number;
      reason: string;
      wasAuthenticated: boolean;
      failure: HandshakeFailure | null;
    };

export type ConnectionListener = (ev: ConnectionEvent) => void;

export class ConnectionError extends Error {
  constructor(
    readonly code: "timeout" | "closed" | "handshake",
    message: string,
    readonly failure: HandshakeFailure | null = null,
  ) {
    super(message);
    this.name = "ConnectionError";
  }
}

const OPEN = 1;

export class Connection {
  readonly url: string;
  private readonly socket: SocketLike;
  private readonly handshake: Handshake;
  private readonly heartbeat: Heartbeat;
  private readonly listeners = new Set<ConnectionListener>();
  private queue: Promise<void> = Promise.resolve();
  private heartbeatTimer: ReturnType<typeof setInterval> | null = null;
  private closed = false;
  private failure: HandshakeFailure | null = null;
  private authResolve: (() => void) | null = null;
  private authReject: ((err: ConnectionError) => void) | null = null;
  authenticated = false;
  keyId: string | null = null;
  capabilities: string[] = [];
  boundPassword: string | null = null;
  private readonly connectTimeoutMs: number;
  private readonly authTimeoutMs: number;

  constructor(opts: ConnectionOptions) {
    this.url = opts.url;
    this.connectTimeoutMs = opts.connectTimeoutMs ?? 5000;
    this.authTimeoutMs = opts.authTimeoutMs ?? 240_000;
    this.handshake = new Handshake(opts.handshake);
    this.heartbeat = new Heartbeat(opts.heartbeat);
    const create = opts.createSocket ?? ((url: string) => new WebSocket(url) as SocketLike);
    this.socket = create(opts.url);
    this.socket.binaryType = "arraybuffer";
    this.socket.addEventListener("message", (ev) => this.onMessage(ev.data));
    this.socket.addEventListener("close", (ev) => this.onClose(ev.code, ev.reason));
    this.socket.addEventListener("error", () => {
      // The close event that follows carries the useful information.
    });
  }

  on(listener: ConnectionListener): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  /** Resolves once AUTH_OK is verified; rejects on timeout, close, or handshake failure. */
  connect(): Promise<void> {
    return new Promise<void>((resolve, reject) => {
      const connectTimer = setTimeout(() => {
        if (!this.helloSeen) this.abort(new ConnectionError("timeout", "Connection timed out"));
      }, this.connectTimeoutMs);
      const authTimer = setTimeout(() => {
        this.abort(new ConnectionError("timeout", "Authentication timed out"));
      }, this.authTimeoutMs);
      this.authResolve = () => {
        clearTimeout(connectTimer);
        clearTimeout(authTimer);
        resolve();
      };
      this.authReject = (err) => {
        clearTimeout(connectTimer);
        clearTimeout(authTimer);
        reject(err);
      };
    });
  }

  private helloSeen = false;

  serverSupports(capability: string): boolean {
    return this.capabilities.includes(capability);
  }

  /** Sends a message once authenticated. Returns false when it could not be sent. */
  send(msg: ClientMessage): boolean {
    if (!this.authenticated || this.closed || this.socket.readyState !== OPEN) return false;
    try {
      this.socket.send(encodeClientMessage(msg));
      return true;
    } catch {
      return false;
    }
  }

  /** Tell the heartbeat whether the page is hidden. */
  setHidden(hidden: boolean): void {
    this.heartbeat.onVisibility(hidden);
  }

  close(code = 1000, reason = "client close"): void {
    if (this.closed) return;
    this.closed = true;
    this.stopHeartbeat();
    try {
      this.socket.close(code, reason);
    } catch {
      // already closed
    }
  }

  private abort(err: ConnectionError): void {
    const reject = this.authReject;
    this.authReject = null;
    this.authResolve = null;
    this.close(1000, err.message);
    reject?.(err);
  }

  private emit(ev: ConnectionEvent): void {
    for (const l of this.listeners) l(ev);
  }

  private onMessage(data: unknown): void {
    if (this.closed) return;
    this.heartbeat.onServerMessage();
    if (typeof data === "string") {
      this.helloSeen = true;
      const msg = parseServerMessage(data);
      if (!msg) return;
      if (this.handshake.state === "done") {
        this.dispatch(msg);
      } else {
        // Handshake steps are async (WebCrypto); keep them in order.
        this.queue = this.queue.then(() => this.runHandshake(msg));
      }
      return;
    }
    if (!this.authenticated) return;
    const bytes =
      data instanceof ArrayBuffer ? new Uint8Array(data) : (data as Uint8Array | undefined);
    if (!bytes) return;
    const frame = splitBinaryFrame(bytes);
    if (frame.kind === "video") {
      this.rawSend('{"type":"ACK"}');
      this.emit({ kind: "video", frame, bytes: bytes.length });
    } else if (frame.kind === "map") {
      this.emit({ kind: "map", frame });
    }
  }

  private dispatch(msg: ServerMessage): void {
    if (msg.type === "HEARTBEAT_ACK") this.heartbeat.onAck();
    this.emit({ kind: "message", msg });
  }

  private async runHandshake(msg: ServerMessage): Promise<void> {
    if (this.closed) return;
    const events = await this.handshake.handle(msg);
    for (const ev of events) {
      switch (ev.kind) {
        case "send":
          this.rawSend(ev.text);
          break;
        case "pairing":
          this.emit({ kind: "pairing", code: ev.code, ttlMs: ev.ttlMs });
          break;
        case "paired":
          this.emit({ kind: "paired", keyId: ev.keyId, password: ev.password });
          break;
        case "authenticated": {
          this.authenticated = true;
          this.keyId = ev.keyId;
          this.capabilities = ev.capabilities;
          this.boundPassword = ev.password;
          this.startHeartbeat();
          this.emit({ kind: "authenticated", keyId: ev.keyId, capabilities: ev.capabilities });
          const resolve = this.authResolve;
          this.authResolve = null;
          this.authReject = null;
          resolve?.();
          break;
        }
        case "failed":
          this.failure = ev.failure;
          this.abort(new ConnectionError("handshake", ev.failure.message, ev.failure));
          break;
      }
    }
  }

  private rawSend(text: string): void {
    if (this.closed || this.socket.readyState !== OPEN) return;
    try {
      this.socket.send(text);
    } catch {
      // the close handler will report it
    }
  }

  private startHeartbeat(): void {
    this.stopHeartbeat();
    this.heartbeatTimer = setInterval(() => {
      const action = this.heartbeat.tick();
      if (action === "send") this.rawSend('{"type":"HEARTBEAT"}');
      else if (action === "lost") {
        this.emit({ kind: "heartbeat-lost" });
        this.close(1000, "heartbeat timeout");
      }
    }, 1000);
  }

  private stopHeartbeat(): void {
    if (this.heartbeatTimer !== null) {
      clearInterval(this.heartbeatTimer);
      this.heartbeatTimer = null;
    }
  }

  private onClose(code: number, reason: string): void {
    const wasAuthenticated = this.authenticated;
    this.authenticated = false;
    this.closed = true;
    this.stopHeartbeat();
    const reject = this.authReject;
    this.authReject = null;
    this.authResolve = null;
    reject?.(
      new ConnectionError(
        this.failure ? "handshake" : "closed",
        this.failure?.message ?? `Connection closed (${code}${reason ? ` ${reason}` : ""})`,
        this.failure,
      ),
    );
    this.emit({ kind: "closed", code, reason, wasAuthenticated, failure: this.failure });
  }
}
