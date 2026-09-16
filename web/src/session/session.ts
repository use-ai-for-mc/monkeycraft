// Session state: a pure reducer over connection events and user intents.
// The UI subscribes to the state; the controller (session/controller.ts, M2+)
// owns the Connection and feeds this reducer.

import type {
  ClientMode,
  ServerMessage,
  TimedNotification,
  WorldPhase,
} from "../protocol/messages.ts";
import type { ConnectionEvent } from "../transport/connection.ts";
import type { HandshakeFailure } from "../transport/handshake.ts";
import type { StreamSize } from "./resolution.ts";

export type LinkState =
  | { phase: "idle" }
  | { phase: "connecting" }
  | { phase: "pairing"; code: string; expiresAt: number }
  | { phase: "connected" }
  | { phase: "reconnecting"; attempt: number }
  | { phase: "failed"; failure: HandshakeFailure | null; message: string };

export interface SessionState {
  link: LinkState;
  mode: ClientMode;
  hibernating: boolean;
  hibernationMessage: string | null;
  timed: TimedNotification | null;
  screenOpen: boolean;
  world: { phase: WorldPhase; serverName: string | null; serverAddress: string | null } | null;
  capabilities: string[];
  keyId: string | null;
  /** Size announced by the last MC header; what the server is actually encoding. */
  serverSize: StreamSize | null;
  /** Size the client last asked for. */
  requestedSize: StreamSize | null;
  /** Last NUDGE, for an in-app banner. */
  nudge: { title: string | null; body: string | null; at: number } | null;
  /** Reason the server closed the session, when it told us. */
  disconnectReason: string | null;
}

export const initialSession: SessionState = {
  link: { phase: "idle" },
  mode: "STREAMING",
  hibernating: false,
  hibernationMessage: null,
  timed: null,
  screenOpen: false,
  world: null,
  capabilities: [],
  keyId: null,
  serverSize: null,
  requestedSize: null,
  nudge: null,
  disconnectReason: null,
};

export type SessionAction =
  | { type: "connect" }
  | { type: "connection"; event: ConnectionEvent; now: number }
  | { type: "reconnecting"; attempt: number }
  | { type: "failed"; failure: HandshakeFailure | null; message: string }
  | { type: "set-mode"; mode: ClientMode }
  | { type: "requested-size"; size: StreamSize }
  | { type: "dismiss-nudge" }
  | { type: "reset" };

export function reduceSession(state: SessionState, action: SessionAction): SessionState {
  switch (action.type) {
    case "connect":
      return { ...state, link: { phase: "connecting" }, disconnectReason: null };
    case "reconnecting":
      return { ...state, link: { phase: "reconnecting", attempt: action.attempt } };
    case "failed":
      return {
        ...state,
        link: { phase: "failed", failure: action.failure, message: action.message },
      };
    case "set-mode":
      return { ...state, mode: action.mode };
    case "requested-size":
      return { ...state, requestedSize: action.size };
    case "dismiss-nudge":
      return { ...state, nudge: null };
    case "reset":
      return initialSession;
    case "connection":
      return reduceConnection(state, action.event, action.now);
  }
}

function reduceConnection(state: SessionState, ev: ConnectionEvent, now: number): SessionState {
  switch (ev.kind) {
    case "pairing":
      return { ...state, link: { phase: "pairing", code: ev.code, expiresAt: now + ev.ttlMs } };
    case "paired":
      return { ...state, keyId: ev.keyId };
    case "authenticated":
      return {
        ...state,
        link: { phase: "connected" },
        capabilities: ev.capabilities,
        keyId: ev.keyId,
        disconnectReason: null,
      };
    case "video":
      if (ev.frame.width !== undefined && ev.frame.height !== undefined) {
        const size = { width: ev.frame.width, height: ev.frame.height };
        if (state.serverSize?.width !== size.width || state.serverSize.height !== size.height) {
          return { ...state, serverSize: size };
        }
      }
      return state;
    case "map":
    case "heartbeat-lost":
      return state;
    case "closed":
      if (state.link.phase === "failed" || state.link.phase === "reconnecting") return state;
      return {
        ...state,
        link: ev.failure
          ? { phase: "failed", failure: ev.failure, message: ev.failure.message }
          : { phase: "idle" },
      };
    case "message":
      return reduceMessage(state, ev.msg);
  }
}

function reduceMessage(state: SessionState, msg: ServerMessage): SessionState {
  switch (msg.type) {
    case "SERVER_STATUS":
      return {
        ...state,
        hibernating: msg.videoState === "HIBERNATING",
        hibernationMessage: msg.videoState === "HIBERNATING" ? msg.message : null,
        timed: msg.timed,
      };
    case "HIBERNATION_STATUS":
      return { ...state, hibernating: msg.active, hibernationMessage: msg.message || null };
    case "TIMED_STATUS":
      return { ...state, timed: msg.timed };
    case "SCREEN_STATE":
      return { ...state, screenOpen: msg.isOpen };
    case "WORLD_STATE":
      return {
        ...state,
        world: { phase: msg.phase, serverName: msg.serverName, serverAddress: msg.serverAddress },
      };
    case "NUDGE":
      return { ...state, nudge: { title: msg.title, body: msg.body, at: Date.now() } };
    case "IMMEDIATE":
      return { ...state, nudge: { title: null, body: msg.body, at: Date.now() } };
    case "DISCONNECT":
      return { ...state, disconnectReason: msg.reason || "server_disconnect" };
    default:
      return state;
  }
}

/** Derived flags the stream screen keys off. */
export function deriveView(state: SessionState) {
  const connected = state.link.phase === "connected";
  return {
    connected,
    showVideo: connected && state.mode !== "CHAT" && !state.hibernating,
    showHibernation: connected && state.mode === "STREAMING" && state.hibernating,
    showReconnecting: state.link.phase === "reconnecting",
    showPairing: state.link.phase === "pairing",
    inWorld: state.world?.phase === "IN_WORLD",
    atMenu: state.world?.phase === "MENU",
    serverSupports: (cap: string) => state.capabilities.includes(cap),
  };
}
