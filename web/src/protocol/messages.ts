// Typed view of the JSON messages in docs/PROTOCOL.md. Parsing lives in codec.ts.

export type VideoState = "ACTIVE" | "HIBERNATING";
export type WorldPhase = "MENU" | "CONNECTING" | "IN_WORLD";
export type ClientMode = "STREAMING" | "CHAT" | "MAP";

export interface TimedNotification {
  fireAtEpochMs: number;
  title: string | null;
  body: string | null;
  sound: boolean;
  countDownText: string | null;
}

export type ChatClickAction = "open_url" | "run_command" | "suggest_command" | "copy_to_clipboard";

export interface ChatClickEvent {
  action: ChatClickAction;
  value: string;
}

export interface ChatHoverEvent {
  action: "show_text";
  segments: ChatSegment[];
}

export interface ChatSegment {
  text: string;
  color: string | null;
  bold: boolean;
  italic: boolean;
  underlined: boolean;
  strikethrough: boolean;
  obfuscated: boolean;
  clickEvent: ChatClickEvent | null;
  hoverEvent: ChatHoverEvent | null;
}

export interface ChatMessage {
  sender: string;
  senderUuid: string | null;
  segments: ChatSegment[];
  timestamp: number;
}

export interface ServerListEntry {
  index: number;
  name: string;
  address: string;
}

export type ServerMessage =
  | { type: "HELLO"; salt: string; pairing: boolean; keyId: string | null }
  | { type: "ERROR"; message: string }
  | { type: "PAIR_WAITING"; code: string; ttlMs: number }
  | { type: "PAIR_FAILED"; message: string }
  | { type: "PAIR_OK"; password: string }
  | {
      type: "AUTH_OK";
      signature: string;
      protocolVersion: number;
      capabilities: string[];
      versionWarning: string | null;
    }
  | { type: "AUTH_RESPONSE"; success: boolean; message: string }
  | {
      type: "SERVER_STATUS";
      videoState: VideoState;
      message: string | null;
      /** null means "no timed notification" (also sent as an explicit cancellation). */
      timed: TimedNotification | null;
    }
  | { type: "SCREEN_STATE"; isOpen: boolean }
  | {
      type: "WORLD_STATE";
      phase: WorldPhase;
      serverName: string | null;
      serverAddress: string | null;
      singleplayer: boolean;
    }
  | { type: "NUDGE"; title: string | null; body: string | null; sound: boolean }
  | { type: "IMMEDIATE"; body: string | null }
  | { type: "DISCONNECT"; reason: string }
  | { type: "HIBERNATION_STATUS"; active: boolean; message: string }
  | { type: "TIMED_STATUS"; timed: TimedNotification }
  | { type: "CACHED_CHAT_MESSAGES"; messages: ChatMessage[] }
  | { type: "CHAT_MESSAGE"; message: ChatMessage }
  | { type: "CHAT_DENIED"; reason: string }
  | { type: "COMMAND_DENIED"; command: string }
  | { type: "HEARTBEAT_ACK" }
  | { type: "PLAYER_POSE"; yaw: number; pitch: number }
  | { type: "PLAYER_LIST"; count: number; players: string[] }
  | { type: "PLAYER_COUNT"; count: number }
  | { type: "SERVER_LIST"; servers: ServerListEntry[] }
  | { type: "JOIN_RESULT"; ok: boolean; error: string | null }
  | { type: "CHAT_MODE_STARTED" }
  | { type: "CHAT_MODE_ENDED" }
  | { type: "UNKNOWN"; rawType: string; raw: Record<string, unknown> };

export type ServerMessageType = ServerMessage["type"];

export interface ClientStatusFields {
  mode: ClientMode;
  width?: number;
  height?: number;
  colorMode?: number;
  fps?: number;
  dataSaver?: boolean;
  autoFaceMovement?: boolean;
}

export type InputKey =
  | "W"
  | "A"
  | "S"
  | "D"
  | "SPACE"
  | "SHIFT"
  | "Q"
  | "E"
  | "F"
  | "LEFT"
  | "RIGHT"
  | "UP"
  | "DOWN";

export type ClientMessage =
  | {
      type: "AUTH";
      salt: string;
      signature: string;
      protocolVersion: 2;
      deviceName?: string;
    }
  | { type: "AUTH"; mode: "PAIR"; protocolVersion: 2; deviceName?: string }
  | ({ type: "CLIENT_STATUS" } & ClientStatusFields)
  | { type: "INPUT"; key: InputKey; pressed: boolean }
  | { type: "LOOK_DELTA"; yaw: number; pitch: number }
  | { type: "GET_PLAYER_POSE" }
  | { type: "CLICK"; button: 0 | 1 }
  | { type: "HOTBAR_SELECT"; slot: number }
  | { type: "ACK" }
  | { type: "REQUEST_KEYFRAME" }
  | { type: "HEARTBEAT" }
  | { type: "PING" }
  | { type: "RUN_COMMAND"; command: string }
  | { type: "SEND_CHAT"; message: string }
  | { type: "SUBSCRIBE_CHAT" }
  | { type: "UNSUBSCRIBE_CHAT" }
  | { type: "SCREEN_CLICK"; button: number; normalizedX: number; normalizedY: number }
  | { type: "SCREEN_HOVER"; normalizedX: number; normalizedY: number }
  | { type: "SCREEN_KEY"; key: "ESCAPE"; pressed: boolean }
  | { type: "SCREEN_MODIFIER"; modifier: "SHIFT"; active: boolean }
  | { type: "MAP_INTERACT"; entityId: number }
  | { type: "LIST_SERVERS" }
  | { type: "JOIN_SERVER"; address: string; name?: string; acceptResourcePack?: boolean }
  | { type: "LEAVE_WORLD" }
  | { type: "GET_PLAYER_LIST" }
  | { type: "GET_PLAYER_COUNT" };

export type ClientMessageType = ClientMessage["type"];
