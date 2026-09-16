import { describe, expect, it } from "vitest";
import { DecodeQueuePolicy } from "../../src/video/queue-policy.ts";

describe("DecodeQueuePolicy", () => {
  it("waits for a keyframe before decoding anything", () => {
    const p = new DecodeQueuePolicy();
    expect(p.decide(false, 0)).toBe("wait-for-key");
    expect(p.decide(true, 0)).toBe("decode");
    expect(p.decide(false, 0)).toBe("decode");
  });

  it("drops deltas while the queue is full and resyncs after the drop limit", () => {
    const p = new DecodeQueuePolicy({ maxQueue: 3, dropLimit: 4 });
    p.decide(true, 0);
    expect(p.decide(false, 3)).toBe("drop");
    expect(p.decide(false, 5)).toBe("drop");
    expect(p.decide(false, 3)).toBe("drop");
    expect(p.decide(false, 3)).toBe("reset-and-wait-for-key");
    expect(p.waitingForKey).toBe(true);
    expect(p.decide(false, 0)).toBe("wait-for-key");
    expect(p.decide(true, 0)).toBe("decode");
  });

  it("a keyframe while full resyncs immediately", () => {
    const p = new DecodeQueuePolicy({ maxQueue: 3 });
    p.decide(true, 0);
    expect(p.decide(true, 3)).toBe("reset-and-wait-for-key");
  });

  it("a successful decode clears the drop streak", () => {
    const p = new DecodeQueuePolicy({ maxQueue: 3, dropLimit: 3 });
    p.decide(true, 0);
    expect(p.decide(false, 3)).toBe("drop");
    expect(p.decide(false, 1)).toBe("decode");
    expect(p.consecutiveDrops).toBe(0);
    expect(p.decide(false, 3)).toBe("drop");
    expect(p.decide(false, 3)).toBe("drop");
    expect(p.decide(false, 3)).toBe("reset-and-wait-for-key");
  });

  it("requireKey forces a resync", () => {
    const p = new DecodeQueuePolicy();
    p.decide(true, 0);
    p.requireKey();
    expect(p.decide(false, 0)).toBe("wait-for-key");
  });
});
