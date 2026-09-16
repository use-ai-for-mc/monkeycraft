// Decode admission policy (docs/LEGACY_CLIENT_NOTES.md, "Decode queue").
// Pure so it can be unit tested; the decoder wrapper feeds it queue depth.

export type DecodeAction = "decode" | "wait-for-key" | "drop" | "reset-and-wait-for-key";

export interface QueuePolicyOptions {
  /** Deltas are dropped while the decoder queue is at or above this. */
  maxQueue?: number;
  /** After this many consecutive drops, resync on a fresh keyframe instead. */
  dropLimit?: number;
}

export class DecodeQueuePolicy {
  readonly maxQueue: number;
  readonly dropLimit: number;
  waitingForKey = true;
  consecutiveDrops = 0;

  constructor(opts: QueuePolicyOptions = {}) {
    this.maxQueue = opts.maxQueue ?? 3;
    this.dropLimit = opts.dropLimit ?? 12;
  }

  decide(isKey: boolean, queueSize: number): DecodeAction {
    if (this.waitingForKey && !isKey) return "wait-for-key";
    if (queueSize >= this.maxQueue) {
      if (isKey || this.consecutiveDrops + 1 >= this.dropLimit) {
        this.consecutiveDrops = 0;
        this.waitingForKey = true;
        return "reset-and-wait-for-key";
      }
      this.consecutiveDrops += 1;
      return "drop";
    }
    this.consecutiveDrops = 0;
    if (isKey) this.waitingForKey = false;
    return "decode";
  }

  /** After a decoder error or reconfigure: only a keyframe may start the sequence again. */
  requireKey(): void {
    this.waitingForKey = true;
    this.consecutiveDrops = 0;
  }
}
