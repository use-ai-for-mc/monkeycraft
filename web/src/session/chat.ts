// Chat state: cached + live messages (rolling cap 100), denials, player count.
// Pure reducer over server messages; the chat panel owns subscribe/unsubscribe.

import type { ChatMessage, ServerMessage } from "../protocol/messages.ts";

export const MAX_CHAT_MESSAGES = 100;

export interface ChatState {
  messages: ChatMessage[];
  /** Set once CACHED_CHAT_MESSAGES arrived after SUBSCRIBE_CHAT. */
  loaded: boolean;
  playerCount: number | null;
  players: string[] | null;
  /** Last CHAT_DENIED / COMMAND_DENIED text, for a toast. */
  notice: { text: string; at: number } | null;
}

export const initialChat: ChatState = {
  messages: [],
  loaded: false,
  playerCount: null,
  players: null,
  notice: null,
};

export function reduceChat(state: ChatState, msg: ServerMessage, now = Date.now()): ChatState {
  switch (msg.type) {
    case "CACHED_CHAT_MESSAGES":
      return { ...state, messages: msg.messages.slice(-MAX_CHAT_MESSAGES), loaded: true };
    case "CHAT_MESSAGE":
      return { ...state, messages: [...state.messages, msg.message].slice(-MAX_CHAT_MESSAGES) };
    case "CHAT_DENIED":
      return { ...state, notice: { text: `Message denied: ${msg.reason}`, at: now } };
    case "COMMAND_DENIED":
      return { ...state, notice: { text: `Command not allowed: ${msg.command}`, at: now } };
    case "PLAYER_COUNT":
      return { ...state, playerCount: msg.count };
    case "PLAYER_LIST":
      return { ...state, playerCount: msg.count, players: msg.players };
    default:
      return state;
  }
}

/** What to send for a chat box submission: commands must use RUN_COMMAND. */
export function outgoingChat(
  text: string,
): { type: "RUN_COMMAND"; command: string } | { type: "SEND_CHAT"; message: string } | null {
  const t = text.trim();
  if (t === "") return null;
  if (t.startsWith("/")) return { type: "RUN_COMMAND", command: t };
  return { type: "SEND_CHAT", message: t };
}

/** Plain text of a message, for accessibility labels and tests. */
export function messageText(m: ChatMessage): string {
  return m.segments.map((s) => s.text).join("");
}
