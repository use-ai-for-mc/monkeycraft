import { describe, expect, it } from "vitest";
import { KeyboardMapper } from "../../src/input/keyboard.ts";
import { LookAccumulator } from "../../src/input/look.ts";
import { MoveVector } from "../../src/input/move-vector.ts";
import { ScreenMode } from "../../src/input/screen-mode.ts";

describe("KeyboardMapper", () => {
  it("maps codes to INPUT edges and ignores auto-repeat", () => {
    const k = new KeyboardMapper();
    expect(k.keyDown({ code: "KeyW" })).toEqual([
      { kind: "send", msg: { type: "INPUT", key: "W", pressed: true } },
    ]);
    expect(k.keyDown({ code: "KeyW", repeat: true })).toEqual([]);
    expect(k.keyUp({ code: "KeyW" })).toEqual([
      { kind: "send", msg: { type: "INPUT", key: "W", pressed: false } },
    ]);
    expect(k.keyUp({ code: "KeyW" })).toEqual([]);
  });

  it("handles both shifts as one SHIFT with reference counting", () => {
    const k = new KeyboardMapper();
    expect(k.keyDown({ code: "ShiftLeft" })).toHaveLength(1);
    expect(k.keyDown({ code: "ShiftRight" })).toEqual([]);
    expect(k.keyUp({ code: "ShiftLeft" })).toEqual([]);
    expect(k.keyUp({ code: "ShiftRight" })).toEqual([
      { kind: "send", msg: { type: "INPUT", key: "SHIFT", pressed: false } },
    ]);
  });

  it("maps digits, Q/E/F, arrows and Escape", () => {
    const k = new KeyboardMapper();
    expect(k.keyDown({ code: "Digit1" })).toEqual([{ kind: "hotbar", slot: 0 }]);
    expect(k.keyDown({ code: "Digit9" })).toEqual([{ kind: "hotbar", slot: 8 }]);
    expect(k.keyDown({ code: "Digit0" })).toEqual([{ kind: "ignore" }]);
    expect(k.keyDown({ code: "KeyE" })[0]).toMatchObject({ msg: { key: "E", pressed: true } });
    expect(k.keyDown({ code: "ArrowUp" })[0]).toMatchObject({ msg: { key: "UP" } });
    expect(k.keyDown({ code: "Escape" })).toEqual([{ kind: "escape", pressed: true }]);
    expect(k.keyUp({ code: "Escape" })).toEqual([{ kind: "escape", pressed: false }]);
  });

  it("ignores keys typed into text fields and releases everything on demand", () => {
    const k = new KeyboardMapper();
    expect(k.keyDown({ code: "KeyW", editable: true })).toEqual([{ kind: "ignore" }]);
    k.keyDown({ code: "KeyW" });
    k.keyDown({ code: "Space" });
    expect(k.heldKeys.sort()).toEqual(["SPACE", "W"]);
    expect(k.releaseAll()).toEqual([
      { type: "INPUT", key: "W", pressed: false },
      { type: "INPUT", key: "SPACE", pressed: false },
    ]);
    expect(k.heldKeys).toEqual([]);
    expect(k.keyUp({ code: "KeyW" })).toEqual([]);
  });
});

describe("LookAccumulator", () => {
  it("accumulates at 0.12°/px, inverts Y by default, and skips empty flushes", () => {
    const l = new LookAccumulator();
    expect(l.flush()).toBeNull();
    l.add(10, -5);
    l.add(5, 0);
    expect(l.flush()).toEqual({ type: "LOOK_DELTA", yaw: 1.8, pitch: -0.6 });
    expect(l.flush()).toBeNull();
    const n = new LookAccumulator({ invertY: false, sensitivity: 0.5 });
    n.add(0, 4);
    expect(n.flush()).toEqual({ type: "LOOK_DELTA", yaw: 0, pitch: -2 });
  });
});

describe("MoveVector", () => {
  it("presses past 0.35 and releases below 0.25 per axis", () => {
    const m = new MoveVector();
    expect(m.update(0, -0.3)).toEqual([]);
    expect(m.update(0, -0.4)).toEqual([{ type: "INPUT", key: "W", pressed: true }]);
    expect(m.update(0, -0.3)).toEqual([]);
    expect(m.update(0, -0.2)).toEqual([{ type: "INPUT", key: "W", pressed: false }]);
    expect(m.update(0.9, 0.9)).toEqual([
      { type: "INPUT", key: "D", pressed: true },
      { type: "INPUT", key: "S", pressed: true },
    ]);
    expect(m.update(-0.9, 0.9)).toEqual([
      { type: "INPUT", key: "D", pressed: false },
      { type: "INPUT", key: "A", pressed: true },
    ]);
    expect(m.release()).toEqual([
      { type: "INPUT", key: "A", pressed: false },
      { type: "INPUT", key: "S", pressed: false },
    ]);
  });
});

describe("ScreenMode", () => {
  const rect = { x: 100, y: 50, width: 200, height: 400 };

  it("normalises clicks over the picture rect and rejects outside points", () => {
    const s = new ScreenMode({ now: () => 0 });
    expect(s.mouseDown(rect, 200, 250, 0)).toEqual({
      type: "SCREEN_CLICK",
      button: 0,
      normalizedX: 0.5,
      normalizedY: 0.5,
    });
    expect(s.mouseDown(rect, 300, 450, 1)).toMatchObject({
      button: 1,
      normalizedX: 1,
      normalizedY: 1,
    });
    expect(s.mouseDown(rect, 50, 50, 0)).toBeNull();
  });

  it("throttles hover to the configured interval", () => {
    let t = 0;
    const s = new ScreenMode({ hoverIntervalMs: 33, now: () => t });
    expect(s.mouseMove(rect, 150, 150)).toMatchObject({ type: "SCREEN_HOVER" });
    t = 10;
    expect(s.mouseMove(rect, 160, 160)).toBeNull();
    t = 40;
    expect(s.mouseMove(rect, 160, 160)).toMatchObject({ normalizedX: 0.3 });
  });

  it("touch taps follow the click mode", () => {
    const s = new ScreenMode({ now: () => 0 });
    expect(s.touchTap(rect, 200, 250)).toMatchObject({ type: "SCREEN_CLICK", button: 0 });
    s.clickMode = "right";
    expect(s.touchTap(rect, 200, 250)).toMatchObject({ type: "SCREEN_CLICK", button: 1 });
    s.clickMode = "hover";
    expect(s.touchTap(rect, 200, 250)).toMatchObject({ type: "SCREEN_HOVER" });
    const t = new ScreenMode({ now: () => 100 });
    t.clickMode = "hover";
    expect(t.touchMove(rect, 210, 250)).toMatchObject({ type: "SCREEN_HOVER" });
    t.clickMode = "left";
    expect(t.touchMove(rect, 210, 250)).toBeNull();
  });

  it("builds ESC and SHIFT messages", () => {
    expect(ScreenMode.escape(true)).toEqual({ type: "SCREEN_KEY", key: "ESCAPE", pressed: true });
    expect(ScreenMode.shift(false)).toEqual({
      type: "SCREEN_MODIFIER",
      modifier: "SHIFT",
      active: false,
    });
  });
});
