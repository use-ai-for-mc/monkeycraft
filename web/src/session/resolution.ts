// Requested stream size policy. This is the only place a viewport size turns
// into a CLIENT_STATUS width/height, and it is never called from render code
// (docs/LEGACY_CLIENT_NOTES.md, defect 1).

export type ResolutionPreset = "low" | "medium" | "high";

export interface StreamSize {
  width: number;
  height: number;
}

export const PRESETS: Record<ResolutionPreset, { scale: number; maxEdge: number }> = {
  low: { scale: 0.5, maxEdge: 640 },
  medium: { scale: 0.75, maxEdge: 960 },
  high: { scale: 1.0, maxEdge: 1280 },
};

/** Server limits (docs/PROTOCOL.md 3.1). */
export const MIN_EDGE = 2;
export const MAX_EDGE = 1920;

export interface ViewportInput {
  /** CSS pixels of the area the video may fill. */
  cssWidth: number;
  cssHeight: number;
  devicePixelRatio: number;
  preset: ResolutionPreset;
}

function even(n: number): number {
  const v = Math.floor(n / 2) * 2;
  return Math.min(MAX_EDGE, Math.max(MIN_EDGE, v));
}

/** viewport × DPR × preset scale, long edge capped, both edges even and within server limits. */
export function computeStreamSize(input: ViewportInput): StreamSize {
  const { scale, maxEdge } = PRESETS[input.preset];
  const dpr = input.devicePixelRatio > 0 ? input.devicePixelRatio : 1;
  let w = Math.max(0, input.cssWidth) * dpr * scale;
  let h = Math.max(0, input.cssHeight) * dpr * scale;
  const longEdge = Math.max(w, h);
  if (longEdge > maxEdge && longEdge > 0) {
    const f = maxEdge / longEdge;
    w *= f;
    h *= f;
  }
  return { width: even(Math.round(w)), height: even(Math.round(h)) };
}

export function sameSize(a: StreamSize | null, b: StreamSize | null): boolean {
  if (a === null || b === null) return a === b;
  return a.width === b.width && a.height === b.height;
}

/**
 * Whether a viewport change is big enough to renegotiate: either axis moved
 * by more than `threshold` (fraction) AND the resulting even size differs.
 */
export function shouldRenegotiate(
  previousViewport: { cssWidth: number; cssHeight: number } | null,
  previousSize: StreamSize | null,
  next: ViewportInput,
  threshold = 0.1,
): boolean {
  const nextSize = computeStreamSize(next);
  if (previousViewport === null || previousSize === null) return true;
  const dw =
    Math.abs(next.cssWidth - previousViewport.cssWidth) / Math.max(1, previousViewport.cssWidth);
  const dh =
    Math.abs(next.cssHeight - previousViewport.cssHeight) / Math.max(1, previousViewport.cssHeight);
  if (dw <= threshold && dh <= threshold) return false;
  return !sameSize(previousSize, nextSize);
}

/** Letterboxed rectangle of a `frame`-sized picture inside a `box`, in the box's units. */
export function containRect(
  frame: StreamSize,
  box: StreamSize,
): { x: number; y: number; width: number; height: number } {
  if (frame.width <= 0 || frame.height <= 0 || box.width <= 0 || box.height <= 0) {
    return { x: 0, y: 0, width: 0, height: 0 };
  }
  const scale = Math.min(box.width / frame.width, box.height / frame.height);
  const width = frame.width * scale;
  const height = frame.height * scale;
  return { x: (box.width - width) / 2, y: (box.height - height) / 2, width, height };
}
