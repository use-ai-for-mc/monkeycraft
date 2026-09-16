// Which control surface to show. Only affects touch pads; the ESC palette is
// gated on SCREEN_STATE elsewhere.

import type { ControlLayout } from "../session/settings.ts";
import type { PointerKind } from "./pointer.ts";

export function showTouchControls(
  layout: ControlLayout,
  lastPointer: PointerKind | null,
  coarsePointer: boolean,
): boolean {
  if (layout === "touch") return true;
  if (layout === "mouse") return false;
  if (lastPointer) return lastPointer === "touch";
  return coarsePointer;
}

export function hasCoarsePointer(): boolean {
  return typeof matchMedia !== "undefined" && matchMedia("(pointer: coarse)").matches;
}
