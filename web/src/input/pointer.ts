// Pointer input over the video host. World mode: mouse look through Pointer
// Lock (drag-look fallback), clicks, wheel to change hotbar slot, touch drag
// look with tap / long-press. Screen mode (a GUI is open): clicks and hover
// mapped through ScreenMode. Which mode applies is decided per event from
// `screenOpen()`, never from the pointer kind (docs/LEGACY_CLIENT_NOTES.md
// defect 4).

import type { ClientMessage } from "../protocol/messages.ts";
import type { DisplayRect } from "../video/renderer.ts";
import type { LookAccumulator } from "./look.ts";
import type { ScreenMode } from "./screen-mode.ts";

export type PointerKind = "mouse" | "touch";

export interface PointerHost {
  element: HTMLElement;
  send: (msg: ClientMessage) => boolean;
  rect: () => DisplayRect;
  screenOpen: () => boolean;
  look: LookAccumulator;
  screenMode: ScreenMode;
  onPointerKind?: (kind: PointerKind) => void;
  onHotbarStep?: (delta: number) => void;
  /** Whether to use Pointer Lock for mouse look (desktop). */
  usePointerLock?: () => boolean;
  /** MAP mode: taps pick entities instead of looking/clicking. */
  mapMode?: () => boolean;
  onMapTap?: (nx: number, ny: number) => void;
}

const DRAG_THRESHOLD_PX = 8;

/** Browser buttons are 0 left, 1 middle, 2 right; GLFW (the server) is 0 left, 1 right, 2 middle. */
function glfwButton(button: number): number {
  return button === 2 ? 1 : button === 1 ? 2 : button;
}
const LONG_PRESS_MS = 200;
const FLUSH_MS = 16;

interface Active {
  id: number;
  kind: PointerKind;
  startX: number;
  startY: number;
  lastX: number;
  lastY: number;
  button: 0 | 1;
  dragged: boolean;
  longPressed: boolean;
  timer: ReturnType<typeof setTimeout> | null;
}

export class PointerController {
  private active: Active | null = null;
  private flushTimer: ReturnType<typeof setInterval> | null = null;
  private locked = false;
  private readonly listeners: Array<[EventTarget, string, EventListener]> = [];

  constructor(private readonly host: PointerHost) {}

  attach(): void {
    const el = this.host.element;
    this.on(el, "pointerdown", (e) => this.onDown(e as PointerEvent));
    this.on(el, "pointermove", (e) => this.onMove(e as PointerEvent));
    this.on(el, "pointerup", (e) => this.onUp(e as PointerEvent));
    this.on(el, "pointercancel", (e) => this.onCancel(e as PointerEvent));
    this.on(el, "wheel", (e) => this.onWheel(e as WheelEvent), { passive: false });
    this.on(el, "contextmenu", (e) => e.preventDefault());
    this.on(document, "pointerlockchange", () => {
      this.locked = document.pointerLockElement === el;
    });
    this.flushTimer = setInterval(() => {
      const msg = this.host.look.flush();
      if (msg) this.host.send(msg);
    }, FLUSH_MS);
  }

  detach(): void {
    for (const [target, type, fn] of this.listeners) target.removeEventListener(type, fn);
    this.listeners.length = 0;
    if (this.flushTimer !== null) clearInterval(this.flushTimer);
    this.flushTimer = null;
    this.cancelActive();
    this.exitLock();
  }

  /** Called when SCREEN_STATE changes: a GUI needs a free cursor. */
  setScreenOpen(open: boolean): void {
    if (open) this.exitLock();
    this.cancelActive();
    this.host.look.clear();
  }

  get pointerLocked(): boolean {
    return this.locked;
  }

  exitLock(): void {
    if (this.locked && document.pointerLockElement === this.host.element) {
      document.exitPointerLock();
    }
  }

  private on(
    target: EventTarget,
    type: string,
    fn: EventListener,
    opts?: AddEventListenerOptions,
  ): void {
    target.addEventListener(type, fn, opts);
    this.listeners.push([target, type, fn]);
  }

  private local(e: PointerEvent): { x: number; y: number } {
    const box = this.host.element.getBoundingClientRect();
    return { x: e.clientX - box.left, y: e.clientY - box.top };
  }

  private onDown(e: PointerEvent): void {
    const kind: PointerKind = e.pointerType === "touch" ? "touch" : "mouse";
    this.host.onPointerKind?.(kind);
    if (this.active) return;
    const { x, y } = this.local(e);
    e.preventDefault();

    if (this.host.screenOpen()) {
      if (kind === "mouse") {
        const msg = this.host.screenMode.mouseDown(this.host.rect(), x, y, glfwButton(e.button));
        if (msg) this.host.send(msg);
        return;
      }
      this.active = this.newActive(e, kind, x, y);
      return;
    }

    if (this.host.mapMode?.()) {
      const r = this.host.rect();
      if (r.width > 0 && r.height > 0) {
        const nx = (x - r.x) / r.width;
        const ny = (y - r.y) / r.height;
        if (nx >= 0 && nx <= 1 && ny >= 0 && ny <= 1) this.host.onMapTap?.(nx, ny);
      }
      return;
    }

    if (kind === "mouse") {
      if (this.host.usePointerLock?.() !== false && !this.locked) {
        this.host.element.requestPointerLock?.();
      }
      if (this.locked) {
        this.host.send({ type: "CLICK", button: e.button === 2 ? 1 : 0 });
        return;
      }
      this.active = this.newActive(e, kind, x, y);
      return;
    }

    // touch, world mode
    const active = this.newActive(e, kind, x, y);
    active.timer = setTimeout(() => {
      if (this.active === active && !active.dragged) {
        active.longPressed = true;
        this.host.send({ type: "CLICK", button: 1 });
        navigator.vibrate?.(30);
      }
    }, LONG_PRESS_MS);
    this.active = active;
    this.host.element.setPointerCapture?.(e.pointerId);
  }

  private newActive(e: PointerEvent, kind: PointerKind, x: number, y: number): Active {
    return {
      id: e.pointerId,
      kind,
      startX: x,
      startY: y,
      lastX: x,
      lastY: y,
      button: e.button === 2 ? 1 : 0,
      dragged: false,
      longPressed: false,
      timer: null,
    };
  }

  private onMove(e: PointerEvent): void {
    const { x, y } = this.local(e);
    if (this.host.mapMode?.()) return;
    if (this.host.screenOpen()) {
      if (e.pointerType !== "touch") {
        const msg = this.host.screenMode.mouseMove(this.host.rect(), x, y);
        if (msg) this.host.send(msg);
      } else if (this.active && this.active.id === e.pointerId) {
        const msg = this.host.screenMode.touchMove(this.host.rect(), x, y);
        if (msg) this.host.send(msg);
        this.markDrag(this.active, x, y);
      }
      return;
    }
    if (this.locked && e.pointerType !== "touch") {
      this.host.look.add(e.movementX, e.movementY);
      return;
    }
    const a = this.active;
    if (!a || a.id !== e.pointerId) return;
    const dx = x - a.lastX;
    const dy = y - a.lastY;
    a.lastX = x;
    a.lastY = y;
    const wasDragging = a.dragged;
    this.markDrag(a, x, y);
    if (a.kind === "touch" || a.dragged) {
      // Mouse drag-look starts only after the threshold; touch looks immediately.
      if (a.kind === "touch" || wasDragging) this.host.look.add(dx, dy);
    }
  }

  private markDrag(a: Active, x: number, y: number): void {
    if (a.dragged) return;
    if (Math.hypot(x - a.startX, y - a.startY) > DRAG_THRESHOLD_PX) {
      a.dragged = true;
      if (a.timer) {
        clearTimeout(a.timer);
        a.timer = null;
      }
    }
  }

  private onUp(e: PointerEvent): void {
    const a = this.active;
    if (!a || a.id !== e.pointerId) return;
    this.active = null;
    if (a.timer) clearTimeout(a.timer);
    const { x, y } = this.local(e);
    if (this.host.screenOpen()) {
      if (a.kind === "touch" && !a.dragged) {
        const msg = this.host.screenMode.touchTap(this.host.rect(), x, y);
        if (msg) this.host.send(msg);
      }
      return;
    }
    if (!a.dragged && !a.longPressed) {
      this.host.send({ type: "CLICK", button: a.kind === "touch" ? 0 : a.button });
    }
  }

  private onCancel(e: PointerEvent): void {
    if (this.active && this.active.id === e.pointerId) this.cancelActive();
  }

  private cancelActive(): void {
    if (this.active?.timer) clearTimeout(this.active.timer);
    this.active = null;
  }

  private onWheel(e: WheelEvent): void {
    e.preventDefault();
    if (this.host.screenOpen() || e.deltaY === 0) return;
    this.host.onHotbarStep?.(e.deltaY > 0 ? 1 : -1);
  }
}
