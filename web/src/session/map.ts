// Map mode geometry, ported as-is from the Flutter client for parity
// (docs/LEGACY_CLIENT_NOTES.md defect 13: fixed FOV and camera height,
// yaw ignored). In MAP mode the server locks the player to face north.

import type { MapEntity, MapFrame } from "../protocol/frames.ts";

const CAMERA_HEIGHT = 20;
const FOV_DEG = 70;
const PICK_RADIUS = 3;

/** World offset (dx, dz) of a normalised tap on the top-down picture. */
export function tapToWorldOffset(
  nx: number,
  ny: number,
  aspect: number,
): { dx: number; dz: number } {
  const halfH = CAMERA_HEIGHT * Math.tan((FOV_DEG / 2) * (Math.PI / 180));
  const halfW = halfH * aspect;
  return { dx: (nx * 2 - 1) * halfW, dz: (ny * 2 - 1) * halfH };
}

/** Nearest entity within PICK_RADIUS blocks of a tap, or null. */
export function pickEntity(
  frame: MapFrame,
  nx: number,
  ny: number,
  aspect: number,
): MapEntity | null {
  const { dx, dz } = tapToWorldOffset(nx, ny, aspect);
  const tx = frame.playerX + dx;
  const tz = frame.playerZ + dz;
  let best: MapEntity | null = null;
  let bestD = PICK_RADIUS;
  for (const e of frame.entities) {
    const d = Math.hypot(e.x - tx, e.z - tz);
    if (d < bestD) {
      bestD = d;
      best = e;
    }
  }
  return best;
}

export function isRideable(e: MapEntity): boolean {
  return e.type === 0 || e.type === 2;
}
