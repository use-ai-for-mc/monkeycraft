import { describe, expect, it } from "vitest";
import type { MapFrame } from "../../src/protocol/frames.ts";
import { isRideable, pickEntity, tapToWorldOffset } from "../../src/session/map.ts";

const frame: MapFrame = {
  kind: "map",
  playerX: 100,
  playerZ: 200,
  playerYaw: 180,
  playerUuid: "u",
  entities: [
    { type: 0, x: 100, z: 205, entityId: 1, name: "Boat" },
    { type: 1, x: 110, z: 200, entityId: 2, name: "Steve" },
    { type: 2, x: 100, z: 190, entityId: 3, name: "Horse" },
  ],
};

describe("map geometry", () => {
  it("maps the picture centre to the player and edges to ±half-extent", () => {
    expect(tapToWorldOffset(0.5, 0.5, 1)).toEqual({ dx: 0, dz: 0 });
    const halfH = 20 * Math.tan((35 * Math.PI) / 180);
    const edge = tapToWorldOffset(1, 1, 2);
    expect(edge.dz).toBeCloseTo(halfH, 6);
    expect(edge.dx).toBeCloseTo(halfH * 2, 6);
  });

  it("picks the nearest entity within 3 blocks", () => {
    const halfH = 20 * Math.tan((35 * Math.PI) / 180);
    // Boat is 5 blocks south (positive z): ny = 0.5 + 5 / (2 * halfH)
    const ny = 0.5 + 5 / (2 * halfH);
    expect(pickEntity(frame, 0.5, ny, 1)?.name).toBe("Boat");
    expect(pickEntity(frame, 0.5, 0.5, 1)).toBeNull();
    expect(isRideable(frame.entities[0]!)).toBe(true);
    expect(isRideable(frame.entities[1]!)).toBe(false);
    expect(isRideable(frame.entities[2]!)).toBe(true);
  });
});
