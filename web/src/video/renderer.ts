// Draws decoded frames on one canvas and exposes the rectangle the picture
// occupies, which the input layer uses for SCREEN_CLICK normalisation.
//
// The canvas backing store follows the decoded frame size; its CSS box is
// letterboxed inside the host element by the renderer itself (no CSS
// object-fit, so the same numbers feed input mapping).

import { containRect, type StreamSize } from "../session/resolution.ts";

export interface DisplayRect {
  x: number;
  y: number;
  width: number;
  height: number;
}

export class CanvasRenderer {
  readonly canvas: HTMLCanvasElement;
  private readonly ctx: CanvasRenderingContext2D;
  private frameSize: StreamSize | null = null;
  private hostSize: StreamSize = { width: 0, height: 0 };
  private rect: DisplayRect = { x: 0, y: 0, width: 0, height: 0 };
  private observer: ResizeObserver | null = null;
  private onRectChange: ((rect: DisplayRect) => void) | null = null;
  framesDrawn = 0;
  lastFrameAt = 0;

  constructor(private readonly host: HTMLElement) {
    this.canvas = document.createElement("canvas");
    this.canvas.style.position = "absolute";
    this.canvas.style.pointerEvents = "none";
    this.canvas.style.left = "0";
    this.canvas.style.top = "0";
    const ctx = this.canvas.getContext("2d", { alpha: false, desynchronized: true });
    if (!ctx) throw new Error("2D canvas context unavailable");
    this.ctx = ctx;
    host.appendChild(this.canvas);
    if (typeof ResizeObserver !== "undefined") {
      this.observer = new ResizeObserver(() => this.measure());
      this.observer.observe(host);
    }
    this.measure();
  }

  /** Called with the picture rectangle (CSS px, relative to the host) whenever it changes. */
  setRectListener(listener: ((rect: DisplayRect) => void) | null): void {
    this.onRectChange = listener;
    listener?.(this.rect);
  }

  get displayRect(): DisplayRect {
    return this.rect;
  }

  get decodedSize(): StreamSize | null {
    return this.frameSize;
  }

  /** Takes ownership of the frame and closes it. */
  draw(frame: VideoFrame): void {
    try {
      const w = frame.displayWidth;
      const h = frame.displayHeight;
      if (w > 0 && h > 0) {
        if (this.canvas.width !== w || this.canvas.height !== h) {
          this.canvas.width = w;
          this.canvas.height = h;
          this.frameSize = { width: w, height: h };
          this.layout();
        }
        this.ctx.drawImage(frame, 0, 0, w, h);
        this.framesDrawn += 1;
        this.lastFrameAt = performance.now();
      }
    } finally {
      frame.close();
    }
  }

  clear(): void {
    this.ctx.fillStyle = "#000";
    this.ctx.fillRect(0, 0, this.canvas.width, this.canvas.height);
  }

  destroy(): void {
    this.observer?.disconnect();
    this.observer = null;
    this.canvas.remove();
  }

  private measure(): void {
    const box = this.host.getBoundingClientRect();
    const next = { width: box.width, height: box.height };
    if (next.width === this.hostSize.width && next.height === this.hostSize.height) return;
    this.hostSize = next;
    this.layout();
  }

  private layout(): void {
    const frame = this.frameSize ?? { width: 0, height: 0 };
    const rect = containRect(frame, this.hostSize);
    this.rect = rect;
    this.canvas.style.transform = `translate(${rect.x}px, ${rect.y}px)`;
    this.canvas.style.width = `${rect.width}px`;
    this.canvas.style.height = `${rect.height}px`;
    this.onRectChange?.(rect);
  }
}

/** Normalised [0,1] position of a point (CSS px, host-relative) inside the picture, or null when outside. */
export function normalizeInRect(
  rect: DisplayRect,
  x: number,
  y: number,
): { nx: number; ny: number } | null {
  if (rect.width <= 0 || rect.height <= 0) return null;
  const lx = x - rect.x;
  const ly = y - rect.y;
  if (lx < 0 || ly < 0 || lx > rect.width || ly > rect.height) return null;
  return {
    nx: Math.min(1, Math.max(0, lx / rect.width)),
    ny: Math.min(1, Math.max(0, ly / rect.height)),
  };
}
