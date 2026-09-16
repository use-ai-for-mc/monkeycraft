// JSON <-> typed messages. Parsing is tolerant: missing fields get defaults,
// unknown types are preserved as UNKNOWN so callers can log them.

import type {
  ChatClickAction,
  ChatMessage,
  ChatSegment,
  ClientMessage,
  ServerListEntry,
  ServerMessage,
  TimedNotification,
  VideoState,
  WorldPhase,
} from "./messages.ts";

type Raw = Record<string, unknown>;

const str = (v: unknown, fallback = ""): string => (typeof v === "string" ? v : fallback);
const strOrNull = (v: unknown): string | null => (typeof v === "string" && v.length > 0 ? v : null);
const num = (v: unknown, fallback = 0): number =>
  typeof v === "number" && Number.isFinite(v) ? v : fallback;
const bool = (v: unknown, fallback = false): boolean => (typeof v === "boolean" ? v : fallback);
const isRaw = (v: unknown): v is Raw => typeof v === "object" && v !== null && !Array.isArray(v);

const CLICK_ACTIONS: ReadonlySet<string> = new Set([
  "open_url",
  "run_command",
  "suggest_command",
  "copy_to_clipboard",
]);

export function parseSegment(v: unknown, allowHover = true): ChatSegment {
  const r = isRaw(v) ? v : {};
  let clickEvent: ChatSegment["clickEvent"] = null;
  if (isRaw(r.clickEvent)) {
    const action = str(r.clickEvent.action);
    if (CLICK_ACTIONS.has(action)) {
      clickEvent = { action: action as ChatClickAction, value: str(r.clickEvent.value) };
    }
  }
  let hoverEvent: ChatSegment["hoverEvent"] = null;
  if (allowHover && isRaw(r.hoverEvent) && r.hoverEvent.action === "show_text") {
    const value = r.hoverEvent.value;
    const segments = Array.isArray(value)
      ? value.map((s) => parseSegment(s, false))
      : typeof value === "string"
        ? [parseSegment({ text: value }, false)]
        : [];
    hoverEvent = { action: "show_text", segments };
  }
  return {
    text: str(r.text),
    color: strOrNull(r.color),
    bold: bool(r.bold),
    italic: bool(r.italic),
    underlined: bool(r.underlined),
    strikethrough: bool(r.strikethrough),
    obfuscated: bool(r.obfuscated),
    clickEvent,
    hoverEvent,
  };
}

export function parseChatMessage(v: unknown): ChatMessage {
  const r = isRaw(v) ? v : {};
  const segments = Array.isArray(r.segments)
    ? r.segments.map((s) => parseSegment(s))
    : typeof r.message === "string"
      ? [parseSegment({ text: r.message })]
      : [];
  return {
    sender: str(r.sender, "System"),
    senderUuid: strOrNull(r.senderUuid),
    segments,
    timestamp: num(r.timestamp),
  };
}

/** Reads either the unprefixed (TIMED_STATUS) or `timed`-prefixed (SERVER_STATUS) spelling. */
export function parseTimed(r: Raw, prefixed: boolean): TimedNotification | null {
  const k = (name: string) =>
    prefixed ? `timed${name.charAt(0).toUpperCase()}${name.slice(1)}` : name;
  const fireAt = r[k("fireAtEpochMs")];
  if (typeof fireAt !== "number" || !Number.isFinite(fireAt)) return null;
  return {
    fireAtEpochMs: fireAt,
    title: strOrNull(r[k("title")]),
    body: strOrNull(r[k("body")]),
    sound: bool(r[k("sound")], true),
    countDownText: strOrNull(r[k("countDownText")]),
  };
}

function parseVideoState(v: unknown): VideoState {
  return v === "HIBERNATING" ? "HIBERNATING" : "ACTIVE";
}

function parsePhase(v: unknown): WorldPhase {
  return v === "IN_WORLD" || v === "CONNECTING" ? v : "MENU";
}

function parseServers(v: unknown): ServerListEntry[] {
  if (!Array.isArray(v)) return [];
  return v.map((e, i) => {
    const r = isRaw(e) ? e : {};
    return { index: num(r.index, i), name: str(r.name), address: str(r.address) };
  });
}

/** Returns null for invalid JSON, non-objects, or a missing/non-string `type`. */
export function parseServerMessage(text: string): ServerMessage | null {
  let raw: unknown;
  try {
    raw = JSON.parse(text);
  } catch {
    return null;
  }
  if (!isRaw(raw) || typeof raw.type !== "string") return null;
  return fromRaw(raw, raw.type);
}

function fromRaw(r: Raw, type: string): ServerMessage {
  switch (type) {
    case "HELLO":
      return { type, salt: str(r.salt), pairing: bool(r.pairing), keyId: strOrNull(r.keyId) };
    case "ERROR":
      return { type, message: str(r.message) };
    case "PAIR_WAITING":
      return { type, code: str(r.code), ttlMs: num(r.ttlMs, 180_000) };
    case "PAIR_FAILED":
      return { type, message: str(r.message) };
    case "PAIR_OK":
      return { type, password: str(r.password) };
    case "AUTH_OK":
      return {
        type,
        signature: str(r.signature),
        protocolVersion: num(r.protocolVersion),
        capabilities: Array.isArray(r.capabilities) ? r.capabilities.map((c) => str(c)) : [],
        versionWarning: strOrNull(r.versionWarning),
      };
    case "AUTH_RESPONSE":
      return { type, success: bool(r.success), message: str(r.message) };
    case "SERVER_STATUS":
      return {
        type,
        videoState: parseVideoState(r.videoState),
        message: strOrNull(r.message),
        timed: parseTimed(r, true),
      };
    case "SCREEN_STATE":
      return { type, isOpen: bool(r.isOpen) };
    case "WORLD_STATE":
      return {
        type,
        phase: parsePhase(r.phase),
        serverName: strOrNull(r.serverName),
        serverAddress: strOrNull(r.serverAddress),
        singleplayer: bool(r.singleplayer),
      };
    case "NUDGE":
      return {
        type,
        title: strOrNull(r.title),
        body: strOrNull(r.body),
        sound: bool(r.sound, true),
      };
    case "IMMEDIATE":
      return { type, body: strOrNull(r.body) };
    case "DISCONNECT":
      return { type, reason: str(r.reason) };
    case "HIBERNATION_STATUS":
      return { type, active: bool(r.active, true), message: str(r.message) };
    case "TIMED_STATUS": {
      const timed = parseTimed(r, false);
      if (!timed) return { type: "UNKNOWN", rawType: type, raw: r };
      return { type, timed };
    }
    case "CACHED_CHAT_MESSAGES":
      return {
        type,
        messages: Array.isArray(r.messages) ? r.messages.map(parseChatMessage) : [],
      };
    case "CHAT_MESSAGE":
      return { type, message: parseChatMessage(r) };
    case "CHAT_DENIED":
      return { type, reason: str(r.reason) };
    case "COMMAND_DENIED":
      return { type, command: str(r.command) };
    case "HEARTBEAT_ACK":
    case "CHAT_MODE_STARTED":
    case "CHAT_MODE_ENDED":
      return { type };
    case "PLAYER_POSE":
      return { type, yaw: num(r.yaw), pitch: num(r.pitch) };
    case "PLAYER_LIST":
      return {
        type,
        count: num(r.count),
        players: Array.isArray(r.players) ? r.players.map((p) => str(p)) : [],
      };
    case "PLAYER_COUNT":
      return { type, count: num(r.count) };
    case "SERVER_LIST":
      return { type, servers: parseServers(r.servers) };
    case "JOIN_RESULT":
      return { type, ok: bool(r.ok), error: strOrNull(r.error) };
    default:
      return { type: "UNKNOWN", rawType: type, raw: r };
  }
}

/** Wire form of a client message. Undefined fields are dropped by JSON.stringify. */
export function encodeClientMessage(msg: ClientMessage): string {
  return JSON.stringify(msg);
}
