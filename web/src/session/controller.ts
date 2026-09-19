// Owns the Connection for one login, reconnects on loss, keeps SessionState,
// and turns settings/mode/size into CLIENT_STATUS. Video access units are
// fanned out to a listener (the stream page feeds them to the decoder).

import { batch, signal } from "@preact/signals";
import type { ClientMessage, ClientMode } from "../protocol/messages.ts";
import { Connection, type ConnectionEvent, type SocketLike } from "../transport/connection.ts";
import { serverToWsUrl } from "../transport/endpoint.ts";
import type { HandshakeFailure } from "../transport/handshake.ts";
import { ReconnectPolicy } from "../transport/reconnect.ts";
import type { StreamSize } from "./resolution.ts";
import { initialSession, reduceSession, type SessionAction, type SessionState } from "./session.ts";
import type { Settings } from "./settings.ts";
import type { CredentialStore } from "./storage.ts";

export interface ControllerOptions {
  credentials: CredentialStore;
  settings: () => Settings;
  createSocket?: (url: string) => SocketLike;
  now?: () => number;
}

export interface ConnectRequest {
  server: string;
  password: string;
  pairIfNeeded: boolean;
}

export type VideoListener = (au: Uint8Array, header: StreamSize | null) => void;

export class SessionController {
  readonly state = signal<SessionState>(initialSession);
  private conn: Connection | null = null;
  private server = "";
  private password = "";
  private intentionalClose = false;
  private reconnect = new ReconnectPolicy();
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private reconnectPending = false;
  private generation = 0;
  private readonly videoListeners = new Set<VideoListener>();
  private readonly messageListeners = new Set<(ev: ConnectionEvent) => void>();
  private readonly now: () => number;
  private hidden = false;

  constructor(private readonly opts: ControllerOptions) {
    this.now = opts.now ?? (() => Date.now());
  }

  onVideo(listener: VideoListener): () => void {
    this.videoListeners.add(listener);
    return () => this.videoListeners.delete(listener);
  }

  /** Raw connection events, for screens that need messages (chat, picker). */
  onEvent(listener: (ev: ConnectionEvent) => void): () => void {
    this.messageListeners.add(listener);
    return () => this.messageListeners.delete(listener);
  }

  get snapshot(): SessionState {
    return this.state.value;
  }

  private dispatch(action: SessionAction): void {
    this.state.value = reduceSession(this.state.value, action);
  }

  /** Connect and authenticate. Resolves on AUTH_OK; rejects with ConnectionError. */
  async connect(req: ConnectRequest): Promise<void> {
    this.disconnect();
    this.intentionalClose = false;
    const generation = this.generation;
    this.server = req.server;
    this.password = req.password;
    this.reconnect.reset();
    this.dispatch({ type: "reset" });
    this.dispatch({ type: "connect" });
    await this.open(req.pairIfNeeded, generation, false);
  }

  private async open(
    pairIfNeeded: boolean,
    generation: number,
    reconnecting: boolean,
  ): Promise<void> {
    const settings = this.opts.settings();
    const conn = new Connection({
      url: `${serverToWsUrl(this.server)}`,
      handshake: {
        password: this.password,
        pairIfNeeded,
        lookupPassword: (keyId) => this.opts.credentials.lookup(this.server, keyId),
        deviceName: settings.deviceName || defaultDeviceName(),
      },
      ...(this.opts.createSocket ? { createSocket: this.opts.createSocket } : {}),
    });
    this.conn = conn;
    conn.setHidden(this.hidden);
    conn.on((ev) => this.onConnectionEvent(conn, ev, generation, reconnecting));
    try {
      await conn.connect();
    } catch (err) {
      if (this.conn === conn) this.conn = null;
      throw err;
    }
  }

  private onConnectionEvent(
    conn: Connection,
    ev: ConnectionEvent,
    generation: number,
    reconnecting: boolean,
  ): void {
    if (!this.isCurrent(generation) || this.conn !== conn) return;
    if (
      ev.kind === "closed" &&
      !this.snapshot.disconnectReason &&
      (ev.wasAuthenticated || reconnecting) &&
      (!ev.failure || ev.failure.code === "server-signature")
    ) {
      batch(() => {
        this.dispatch({ type: "connection", event: ev, now: this.now() });
        this.conn = null;
        if (ev.failure?.code === "invalid-signature") {
          this.opts.credentials.forget(this.server, ev.failure.keyId);
        }
        this.scheduleReconnect(generation);
      });
      for (const l of this.messageListeners) l(ev);
      return;
    }
    this.dispatch({ type: "connection", event: ev, now: this.now() });
    switch (ev.kind) {
      case "authenticated": {
        if (conn.boundPassword) {
          this.password = conn.boundPassword;
          this.opts.credentials.bind(ev.keyId, conn.boundPassword, this.server);
        }
        this.syncStatus();
        break;
      }
      case "video": {
        const header =
          ev.frame.width !== undefined && ev.frame.height !== undefined
            ? { width: ev.frame.width, height: ev.frame.height }
            : null;
        for (const l of this.videoListeners) l(ev.frame.au, header);
        break;
      }
      case "message":
        if (ev.msg.type === "HEARTBEAT_ACK") this.reconnect.reset();
        break;
      case "closed":
        this.conn = null;
        if (ev.failure?.code === "invalid-signature") {
          this.opts.credentials.forget(this.server, ev.failure.keyId);
        }
        break;
      default:
        break;
    }
    for (const l of this.messageListeners) l(ev);
  }

  private scheduleReconnect(generation: number): void {
    if (!this.isCurrent(generation)) return;
    const delay = this.reconnect.nextDelay();
    if (delay === null) {
      this.dispatch({
        type: "failed",
        failure: null,
        message: "Connection lost. Please log in again.",
      });
      return;
    }
    this.dispatch({ type: "reconnecting", attempt: this.reconnect.attempts + 1 });
    if (this.hidden) {
      this.reconnectPending = true;
      return;
    }
    this.reconnectTimer = setTimeout(() => {
      this.reconnectTimer = null;
      if (this.hidden) {
        this.reconnectPending = true;
        return;
      }
      if (!this.isCurrent(generation) || this.reconnect.next() === null) return;
      void this.open(false, generation, true).catch(() => {});
    }, delay);
  }

  /** Close without reconnecting. */
  disconnect(): void {
    this.generation += 1;
    this.intentionalClose = true;
    if (this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.reconnectPending = false;
    const conn = this.conn;
    this.conn = null;
    conn?.close();
  }

  private isCurrent(generation: number): boolean {
    return this.generation === generation && !this.intentionalClose;
  }

  send(msg: ClientMessage): boolean {
    return this.conn?.send(msg) ?? false;
  }

  setHidden(hidden: boolean): void {
    if (this.hidden === hidden) return;
    this.hidden = hidden;
    this.conn?.setHidden(hidden);
    if (hidden && this.reconnectTimer !== null) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
      this.reconnectPending = true;
      return;
    }
    if (!hidden && this.reconnectPending && !this.intentionalClose) {
      this.reconnectPending = false;
      this.scheduleReconnect(this.generation);
    }
  }

  setMode(mode: ClientMode): void {
    if (this.snapshot.mode === mode) return;
    this.dispatch({ type: "set-mode", mode });
    this.syncStatus();
  }

  setRequestedSize(size: StreamSize): void {
    const cur = this.snapshot.requestedSize;
    if (cur && cur.width === size.width && cur.height === size.height) return;
    this.dispatch({ type: "requested-size", size });
    this.syncStatus();
  }

  /** Re-send CLIENT_STATUS from current mode, size and settings. */
  syncStatus(): void {
    const s = this.snapshot;
    const settings = this.opts.settings();
    const msg: ClientMessage = { type: "CLIENT_STATUS", mode: s.mode };
    if (s.mode !== "CHAT" && s.requestedSize) {
      Object.assign(msg, {
        width: s.requestedSize.width,
        height: s.requestedSize.height,
        colorMode: settings.colorMode,
        fps: settings.fps,
        dataSaver: settings.dataSaver && this.serverSupports("DATA_SAVER"),
      });
    }
    Object.assign(msg, { autoFaceMovement: settings.autoFaceMovement });
    this.send(msg);
  }

  requestKeyframe(): void {
    this.send({ type: "REQUEST_KEYFRAME" });
  }

  dismissNudge(): void {
    this.dispatch({ type: "dismiss-nudge" });
  }

  serverSupports(capability: string): boolean {
    return this.snapshot.capabilities.includes(capability);
  }

  get failure(): HandshakeFailure | null {
    const link = this.snapshot.link;
    return link.phase === "failed" ? link.failure : null;
  }
}

export function defaultDeviceName(): string {
  if (typeof navigator === "undefined") return "Browser";
  const ua = navigator.userAgent;
  if (/iPhone|iPad/.test(ua)) return "iPhone Safari";
  if (/Android/.test(ua)) return /Chrome/.test(ua) ? "Android Chrome" : "Android Browser";
  if (/Edg\//.test(ua)) return "Edge";
  if (/Firefox\//.test(ua)) return "Firefox";
  if (/Chrome\//.test(ua)) return "Chrome";
  if (/Safari\//.test(ua)) return "Safari";
  return "Browser";
}
