import { describe, expect, it } from "vitest";
import { encodeClientMessage, parseServerMessage } from "../../src/protocol/codec.ts";
import { isText, listFixtures, loadFixture } from "../helpers/fixture.ts";

describe("parseServerMessage", () => {
  it("rejects invalid input", () => {
    expect(parseServerMessage("not json")).toBeNull();
    expect(parseServerMessage("5")).toBeNull();
    expect(parseServerMessage("[]")).toBeNull();
    expect(parseServerMessage('{"salt":"x"}')).toBeNull();
    expect(parseServerMessage('{"type":7}')).toBeNull();
  });

  it("keeps unknown types", () => {
    expect(parseServerMessage('{"type":"FUTURE","x":1}')).toEqual({
      type: "UNKNOWN",
      rawType: "FUTURE",
      raw: { type: "FUTURE", x: 1 },
    });
  });

  it("parses HELLO with an absent keyId", () => {
    expect(parseServerMessage('{"type":"HELLO","salt":"abc==","pairing":false}')).toEqual({
      type: "HELLO",
      salt: "abc==",
      pairing: false,
      keyId: null,
    });
  });

  it("reads both spellings of the timed notification", () => {
    const status = parseServerMessage(
      '{"type":"SERVER_STATUS","videoState":"HIBERNATING","message":"Riding","timedFireAtEpochMs":1700000000000,"timedTitle":"Ride finished","timedBody":"b","timedSound":true,"timedCountDownText":"c"}',
    );
    expect(status).toEqual({
      type: "SERVER_STATUS",
      videoState: "HIBERNATING",
      message: "Riding",
      timed: {
        fireAtEpochMs: 1700000000000,
        title: "Ride finished",
        body: "b",
        sound: true,
        countDownText: "c",
      },
    });
    const timed = parseServerMessage(
      '{"type":"TIMED_STATUS","fireAtEpochMs":1,"title":"t","body":"b","sound":false,"countDownText":"c"}',
    );
    expect(timed).toEqual({
      type: "TIMED_STATUS",
      timed: { fireAtEpochMs: 1, title: "t", body: "b", sound: false, countDownText: "c" },
    });
  });

  it("treats an explicit null timedFireAtEpochMs as cancellation", () => {
    const status = parseServerMessage(
      '{"type":"SERVER_STATUS","videoState":"ACTIVE","timedFireAtEpochMs":null}',
    );
    expect(status).toEqual({
      type: "SERVER_STATUS",
      videoState: "ACTIVE",
      message: null,
      timed: null,
    });
  });

  it("maps unknown video states and phases to the safe defaults", () => {
    expect(parseServerMessage('{"type":"SERVER_STATUS","videoState":"WEIRD"}')).toMatchObject({
      videoState: "ACTIVE",
    });
    expect(parseServerMessage('{"type":"WORLD_STATE","phase":"nope"}')).toMatchObject({
      phase: "MENU",
      serverName: null,
      singleplayer: false,
    });
  });

  it("parses chat segments with click and one level of hover", () => {
    const msg = parseServerMessage(
      JSON.stringify({
        type: "CHAT_MESSAGE",
        sender: "Alice",
        senderUuid: "u-1",
        timestamp: 42,
        segments: [
          { text: "hi ", color: "#FF0000", bold: true },
          {
            text: "link",
            clickEvent: { action: "open_url", value: "https://example.com" },
            hoverEvent: {
              action: "show_text",
              value: [{ text: "tip", hoverEvent: { action: "show_text", value: [{ text: "x" }] } }],
            },
          },
          { text: "bad", clickEvent: { action: "explode", value: "!" } },
        ],
      }),
    );
    expect(msg?.type).toBe("CHAT_MESSAGE");
    if (msg?.type !== "CHAT_MESSAGE") return;
    expect(msg.message.sender).toBe("Alice");
    expect(msg.message.senderUuid).toBe("u-1");
    expect(msg.message.timestamp).toBe(42);
    const [a, b, c] = msg.message.segments;
    expect(a).toMatchObject({ text: "hi ", color: "#FF0000", bold: true, italic: false });
    expect(b?.clickEvent).toEqual({ action: "open_url", value: "https://example.com" });
    expect(b?.hoverEvent?.segments[0]?.text).toBe("tip");
    expect(b?.hoverEvent?.segments[0]?.hoverEvent).toBeNull();
    expect(c?.clickEvent).toBeNull();
  });

  it("falls back to a plain message string and a System sender", () => {
    const msg = parseServerMessage('{"type":"CHAT_MESSAGE","message":"hello","timestamp":1}');
    expect(msg).toMatchObject({
      message: { sender: "System", senderUuid: null, segments: [{ text: "hello" }] },
    });
  });

  it("parses lists", () => {
    expect(
      parseServerMessage(
        '{"type":"SERVER_LIST","servers":[{"index":0,"name":"A","address":"a:1"},{"name":"B"}]}',
      ),
    ).toEqual({
      type: "SERVER_LIST",
      servers: [
        { index: 0, name: "A", address: "a:1" },
        { index: 1, name: "B", address: "" },
      ],
    });
    expect(parseServerMessage('{"type":"PLAYER_LIST","count":2,"players":["x","y"]}')).toEqual({
      type: "PLAYER_LIST",
      count: 2,
      players: ["x", "y"],
    });
    expect(parseServerMessage('{"type":"JOIN_RESULT","ok":false,"error":"nope"}')).toEqual({
      type: "JOIN_RESULT",
      ok: false,
      error: "nope",
    });
    expect(parseServerMessage('{"type":"JOIN_RESULT","ok":true}')).toEqual({
      type: "JOIN_RESULT",
      ok: true,
      error: null,
    });
  });
});

describe("encodeClientMessage", () => {
  it("drops undefined optional fields", () => {
    expect(
      encodeClientMessage({ type: "CLIENT_STATUS", mode: "CHAT", autoFaceMovement: false }),
    ).toBe('{"type":"CLIENT_STATUS","mode":"CHAT","autoFaceMovement":false}');
    expect(encodeClientMessage({ type: "ACK" })).toBe('{"type":"ACK"}');
    expect(
      encodeClientMessage({ type: "AUTH", mode: "PAIR", protocolVersion: 2, deviceName: "web" }),
    ).toBe('{"type":"AUTH","mode":"PAIR","protocolVersion":2,"deviceName":"web"}');
  });
});

describe.each(listFixtures())("fixture %s parses", (name) => {
  const fixture = loadFixture(name);

  it("every server message to a known type", () => {
    const unknown: string[] = [];
    for (const line of fixture.lines) {
      if (!isText(line) || line.dir !== "in") continue;
      const msg = parseServerMessage(line.text);
      expect(msg).not.toBeNull();
      if (msg?.type === "UNKNOWN") unknown.push(msg.rawType);
    }
    expect(unknown).toEqual([]);
  });

  it("the handshake and post-auth state", () => {
    const inbound = fixture.lines
      .filter(isText)
      .filter((l) => l.dir === "in")
      .map((l) => parseServerMessage(l.text));
    expect(inbound[0]).toMatchObject({ type: "HELLO", pairing: true });
    expect((inbound[0] as { salt: string }).salt).toMatch(/^[A-Za-z0-9+/]{22}==$/);
    expect(inbound[1]).toMatchObject({
      type: "AUTH_OK",
      protocolVersion: 2,
      capabilities: ["PLAYER_LIST", "DATA_SAVER", "PAIRING", "KEY_ID"],
      versionWarning: null,
    });
    const types = inbound.map((m) => m?.type);
    expect(types).toContain("SCREEN_STATE");
    expect(types).toContain("WORLD_STATE");
    expect(types).toContain("SERVER_STATUS");
  });
});
