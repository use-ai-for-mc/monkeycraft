import { describe, expect, it } from "vitest";
import { Heartbeat } from "../../src/transport/heartbeat.ts";
import { ReconnectPolicy } from "../../src/transport/reconnect.ts";

function clock(start = 0) {
  let t = start;
  return { now: () => t, advance: (ms: number) => (t += ms) };
}

describe("Heartbeat", () => {
  it("sends after 3 s of silence and declares loss 5 s after an unanswered send", () => {
    const c = clock();
    const hb = new Heartbeat({ now: c.now });
    c.advance(2999);
    expect(hb.tick()).toBeNull();
    c.advance(1);
    expect(hb.tick()).toBe("send");
    expect(hb.waitingForAck).toBe(true);
    c.advance(4999);
    expect(hb.tick()).toBeNull();
    c.advance(1);
    expect(hb.tick()).toBe("lost");
    expect(hb.waitingForAck).toBe(false);
  });

  it("an ack clears the pending state and restarts the idle clock", () => {
    const c = clock();
    const hb = new Heartbeat({ now: c.now });
    c.advance(3000);
    expect(hb.tick()).toBe("send");
    c.advance(100);
    hb.onAck();
    expect(hb.tick()).toBeNull();
    c.advance(2999);
    expect(hb.tick()).toBeNull();
    c.advance(1);
    expect(hb.tick()).toBe("send");
  });

  it("any server traffic, including video, counts as liveness", () => {
    const c = clock();
    const hb = new Heartbeat({ now: c.now });
    for (let i = 0; i < 10; i++) {
      c.advance(1000);
      hb.onServerMessage();
      expect(hb.tick()).toBeNull();
    }
  });

  it("pauses while hidden and restarts cleanly when visible again", () => {
    const c = clock();
    const hb = new Heartbeat({ now: c.now });
    c.advance(3000);
    expect(hb.tick()).toBe("send");
    hb.onVisibility(true);
    c.advance(60_000);
    expect(hb.tick()).toBeNull();
    hb.onVisibility(false);
    expect(hb.tick()).toBeNull();
    expect(hb.waitingForAck).toBe(false);
    c.advance(3000);
    expect(hb.tick()).toBe("send");
  });
});

describe("ReconnectPolicy", () => {
  it("backs off 1 s, 2 s, 4 s and then gives up", () => {
    const p = new ReconnectPolicy();
    expect(p.next()).toBe(1000);
    expect(p.next()).toBe(2000);
    expect(p.next()).toBe(4000);
    expect(p.exhausted).toBe(true);
    expect(p.next()).toBeNull();
  });

  it("reset returns to the first delay", () => {
    const p = new ReconnectPolicy();
    p.next();
    p.next();
    p.reset();
    expect(p.next()).toBe(1000);
  });
});
