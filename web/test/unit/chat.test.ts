import { describe, expect, it } from "vitest";
import { parseServerMessage } from "../../src/protocol/codec.ts";
import type { ChatMessage, ServerMessage } from "../../src/protocol/messages.ts";
import {
  initialChat,
  MAX_CHAT_MESSAGES,
  messageText,
  outgoingChat,
  reduceChat,
} from "../../src/session/chat.ts";

const msg = (o: Record<string, unknown>): ServerMessage => {
  const m = parseServerMessage(JSON.stringify(o));
  if (!m) throw new Error("bad");
  return m;
};

describe("reduceChat", () => {
  it("loads the cache, appends live messages, and caps at 100", () => {
    let s = reduceChat(
      initialChat,
      msg({
        type: "CACHED_CHAT_MESSAGES",
        messages: [{ sender: "A", segments: [{ text: "x" }], timestamp: 1 }],
      }),
    );
    expect(s.loaded).toBe(true);
    expect(s.messages).toHaveLength(1);
    for (let i = 0; i < MAX_CHAT_MESSAGES + 10; i++) {
      s = reduceChat(
        s,
        msg({ type: "CHAT_MESSAGE", sender: "B", segments: [{ text: String(i) }], timestamp: i }),
      );
    }
    expect(s.messages).toHaveLength(MAX_CHAT_MESSAGES);
    expect(messageText(s.messages[MAX_CHAT_MESSAGES - 1] as ChatMessage)).toBe(
      String(MAX_CHAT_MESSAGES + 9),
    );
  });

  it("records denials and player counts", () => {
    let s = reduceChat(
      initialChat,
      msg({ type: "CHAT_DENIED", reason: "Commands must use RUN_COMMAND" }),
      5,
    );
    expect(s.notice).toEqual({ text: "Message denied: Commands must use RUN_COMMAND", at: 5 });
    s = reduceChat(s, msg({ type: "COMMAND_DENIED", command: "/op me" }), 6);
    expect(s.notice?.text).toBe("Command not allowed: /op me");
    s = reduceChat(s, msg({ type: "PLAYER_COUNT", count: 7 }));
    expect(s.playerCount).toBe(7);
    s = reduceChat(s, msg({ type: "PLAYER_LIST", count: 2, players: ["a", "b"] }));
    expect(s.players).toEqual(["a", "b"]);
    expect(s.playerCount).toBe(2);
  });
});

describe("outgoingChat", () => {
  it("routes commands and messages, ignores blanks", () => {
    expect(outgoingChat("  ")).toBeNull();
    expect(outgoingChat(" /warp hub ")).toEqual({ type: "RUN_COMMAND", command: "/warp hub" });
    expect(outgoingChat("hello")).toEqual({ type: "SEND_CHAT", message: "hello" });
  });
});
