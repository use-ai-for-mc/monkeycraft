// Joystick vector → W/A/S/D with per-axis hysteresis (press 0.35, release 0.25),
// edge-triggered like the Flutter GameInputController.

import type { ClientMessage, InputKey } from "../protocol/messages.ts";

export class MoveVector {
  private x = 0; // -1 A, +1 D
  private y = 0; // -1 W, +1 S
  readonly pressThreshold: number;
  readonly releaseThreshold: number;

  constructor(pressThreshold = 0.35, releaseThreshold = 0.25) {
    this.pressThreshold = pressThreshold;
    this.releaseThreshold = releaseThreshold;
  }

  /** dx, dy in [-1, 1]; dy negative is forward. Returns INPUT edges. */
  update(dx: number, dy: number): ClientMessage[] {
    const out: ClientMessage[] = [];
    const nx = this.axis(this.x, clamp(dx));
    const ny = this.axis(this.y, clamp(dy));
    if (nx !== this.x) {
      if (this.x !== 0) out.push(input(this.x < 0 ? "A" : "D", false));
      if (nx !== 0) out.push(input(nx < 0 ? "A" : "D", true));
      this.x = nx;
    }
    if (ny !== this.y) {
      if (this.y !== 0) out.push(input(this.y < 0 ? "W" : "S", false));
      if (ny !== 0) out.push(input(ny < 0 ? "W" : "S", true));
      this.y = ny;
    }
    return out;
  }

  release(): ClientMessage[] {
    return this.update(0, 0);
  }

  private axis(current: number, v: number): number {
    if (current === 0) {
      if (v >= this.pressThreshold) return 1;
      if (v <= -this.pressThreshold) return -1;
      return 0;
    }
    if (current > 0) return v > this.releaseThreshold ? 1 : v <= -this.pressThreshold ? -1 : 0;
    return v < -this.releaseThreshold ? -1 : v >= this.pressThreshold ? 1 : 0;
  }
}

function clamp(v: number): number {
  return Math.max(-1, Math.min(1, v));
}

function input(key: InputKey, pressed: boolean): ClientMessage {
  return { type: "INPUT", key, pressed };
}
