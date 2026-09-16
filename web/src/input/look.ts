// Camera look: accumulate pixel deltas, flush as LOOK_DELTA at a fixed rate.
// Pure; the owner calls flush() on a timer (16 ms like the Flutter client).

import type { ClientMessage } from "../protocol/messages.ts";

export interface LookOptions {
  /** Degrees per CSS pixel. */
  sensitivity?: number;
  invertY?: boolean;
}

export class LookAccumulator {
  private yaw = 0;
  private pitch = 0;
  sensitivity: number;
  invertY: boolean;

  constructor(opts: LookOptions = {}) {
    this.sensitivity = opts.sensitivity ?? 0.12;
    this.invertY = opts.invertY ?? true;
  }

  /** Add a pointer movement in CSS pixels. */
  add(dx: number, dy: number): void {
    this.yaw += dx * this.sensitivity;
    const pitch = dy * this.sensitivity;
    this.pitch += this.invertY ? pitch : -pitch;
  }

  /** Returns the message to send, or null when nothing accumulated. */
  flush(): ClientMessage | null {
    if (this.yaw === 0 && this.pitch === 0) return null;
    const msg: ClientMessage = {
      type: "LOOK_DELTA",
      yaw: round3(this.yaw),
      pitch: round3(this.pitch),
    };
    this.yaw = 0;
    this.pitch = 0;
    return msg;
  }

  clear(): void {
    this.yaw = 0;
    this.pitch = 0;
  }
}

function round3(v: number): number {
  return Math.round(v * 1000) / 1000;
}
