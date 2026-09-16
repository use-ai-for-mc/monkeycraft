// Keyboard → protocol. Uses KeyboardEvent.code so layouts and Shift labels do
// not matter (docs/LEGACY_CLIENT_NOTES.md defect 5). Pure: takes a minimal
// event shape and returns messages; the owner wires DOM listeners.

import type { ClientMessage, InputKey } from "../protocol/messages.ts";

export interface KeyEventLike {
  code: string;
  repeat?: boolean;
  /** True when the event target is a text field; game keys are ignored then. */
  editable?: boolean;
}

const INPUT_KEYS: Record<string, InputKey> = {
  KeyW: "W",
  KeyA: "A",
  KeyS: "S",
  KeyD: "D",
  Space: "SPACE",
  ShiftLeft: "SHIFT",
  ShiftRight: "SHIFT",
  KeyQ: "Q",
  KeyE: "E",
  KeyF: "F",
  ArrowLeft: "LEFT",
  ArrowRight: "RIGHT",
  ArrowUp: "UP",
  ArrowDown: "DOWN",
};

const DIGITS: Record<string, number> = {
  Digit1: 0,
  Digit2: 1,
  Digit3: 2,
  Digit4: 3,
  Digit5: 4,
  Digit6: 5,
  Digit7: 6,
  Digit8: 7,
  Digit9: 8,
};

export type KeyboardOutput =
  | { kind: "send"; msg: ClientMessage }
  | { kind: "hotbar"; slot: number }
  | { kind: "escape"; pressed: boolean }
  | { kind: "ignore" };

export class KeyboardMapper {
  /** Physical codes currently held that map to an INPUT key. */
  private readonly held = new Map<string, InputKey>();
  /** Reference count per INPUT key, so ShiftLeft+ShiftRight release correctly. */
  private readonly count = new Map<InputKey, number>();

  keyDown(ev: KeyEventLike): KeyboardOutput[] {
    if (ev.editable) return [{ kind: "ignore" }];
    if (ev.code === "Escape") return ev.repeat ? [] : [{ kind: "escape", pressed: true }];
    const slot = DIGITS[ev.code];
    if (slot !== undefined) return ev.repeat ? [] : [{ kind: "hotbar", slot }];
    const key = INPUT_KEYS[ev.code];
    if (!key) return [{ kind: "ignore" }];
    if (this.held.has(ev.code)) return [];
    this.held.set(ev.code, key);
    const n = (this.count.get(key) ?? 0) + 1;
    this.count.set(key, n);
    return n === 1 ? [{ kind: "send", msg: { type: "INPUT", key, pressed: true } }] : [];
  }

  keyUp(ev: KeyEventLike): KeyboardOutput[] {
    if (ev.code === "Escape") return [{ kind: "escape", pressed: false }];
    const key = this.held.get(ev.code);
    if (!key) return [];
    this.held.delete(ev.code);
    const n = (this.count.get(key) ?? 1) - 1;
    this.count.set(key, Math.max(0, n));
    return n <= 0 ? [{ kind: "send", msg: { type: "INPUT", key, pressed: false } }] : [];
  }

  /** Release messages for everything held (blur, hide, disconnect, mode change). */
  releaseAll(): ClientMessage[] {
    const out: ClientMessage[] = [];
    for (const [key, n] of this.count) {
      if (n > 0) out.push({ type: "INPUT", key, pressed: false });
    }
    this.held.clear();
    this.count.clear();
    return out;
  }

  get heldKeys(): InputKey[] {
    return [...this.count.entries()].filter(([, n]) => n > 0).map(([k]) => k);
  }
}

/** Whether a DOM event target should keep keyboard input for itself. */
export function isEditableTarget(target: EventTarget | null): boolean {
  if (!(target instanceof HTMLElement)) return false;
  if (target.isContentEditable) return true;
  const tag = target.tagName;
  return tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT";
}
