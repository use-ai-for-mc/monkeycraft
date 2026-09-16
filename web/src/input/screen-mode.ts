// Pointer handling while a Minecraft GUI is open (docs/PROTOCOL.md 3.4):
// SCREEN_CLICK / SCREEN_HOVER normalised over the displayed picture rect.
// Pure; the stream page feeds pointer positions and picks the click mode.

import type { ClientMessage } from "../protocol/messages.ts";
import type { DisplayRect } from "../video/renderer.ts";
import { normalizeInRect } from "../video/renderer.ts";

export type ClickMode = "left" | "right" | "hover";

export interface ScreenModeOptions {
  /** Minimum spacing between SCREEN_HOVER messages. */
  hoverIntervalMs?: number;
  now?: () => number;
}

export class ScreenMode {
  clickMode: ClickMode = "left";
  private lastHoverAt = -Infinity;
  private readonly hoverIntervalMs: number;
  private readonly now: () => number;

  constructor(opts: ScreenModeOptions = {}) {
    this.hoverIntervalMs = opts.hoverIntervalMs ?? 33;
    this.now = opts.now ?? (() => performance.now());
  }

  /** Mouse button press: buttons map straight to GLFW (0 left, 1 right, 2 middle). */
  mouseDown(rect: DisplayRect, x: number, y: number, button: number): ClientMessage | null {
    const n = normalizeInRect(rect, x, y);
    if (!n) return null;
    return { type: "SCREEN_CLICK", button, normalizedX: n.nx, normalizedY: n.ny };
  }

  /** Mouse movement: throttled hover. */
  mouseMove(rect: DisplayRect, x: number, y: number): ClientMessage | null {
    const t = this.now();
    if (t - this.lastHoverAt < this.hoverIntervalMs) return null;
    const n = normalizeInRect(rect, x, y);
    if (!n) return null;
    this.lastHoverAt = t;
    return { type: "SCREEN_HOVER", normalizedX: n.nx, normalizedY: n.ny };
  }

  /** Touch tap: the palette's click mode decides what a tap means. */
  touchTap(rect: DisplayRect, x: number, y: number): ClientMessage | null {
    const n = normalizeInRect(rect, x, y);
    if (!n) return null;
    if (this.clickMode === "hover") {
      return { type: "SCREEN_HOVER", normalizedX: n.nx, normalizedY: n.ny };
    }
    return {
      type: "SCREEN_CLICK",
      button: this.clickMode === "right" ? 1 : 0,
      normalizedX: n.nx,
      normalizedY: n.ny,
    };
  }

  /** Touch drag only hovers when the palette is in hover mode. */
  touchMove(rect: DisplayRect, x: number, y: number): ClientMessage | null {
    if (this.clickMode !== "hover") return null;
    return this.mouseMove(rect, x, y);
  }

  static escape(pressed: boolean): ClientMessage {
    return { type: "SCREEN_KEY", key: "ESCAPE", pressed };
  }

  static shift(active: boolean): ClientMessage {
    return { type: "SCREEN_MODIFIER", modifier: "SHIFT", active };
  }
}
