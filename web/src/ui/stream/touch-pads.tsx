import { useEffect, useRef } from "preact/hooks";
import { MoveVector } from "../../input/move-vector.ts";
import type { ClientMessage } from "../../protocol/messages.ts";

interface SendProps {
  send: (msg: ClientMessage) => void;
}

/** Virtual joystick: pointer drag inside the pad maps to a [-1,1] vector. */
export function Joystick({ send, size = 150 }: SendProps & { size?: number }) {
  const ref = useRef<HTMLDivElement>(null);
  const knobRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    const el = ref.current;
    const knob = knobRef.current;
    if (!el || !knob) return;
    const vector = new MoveVector();
    let pointerId: number | null = null;
    const radius = size / 2;
    const place = (dx: number, dy: number) => {
      knob.style.transform = `translate(${dx * radius * 0.6}px, ${dy * radius * 0.6}px)`;
    };
    const update = (e: PointerEvent) => {
      const box = el.getBoundingClientRect();
      let dx = (e.clientX - (box.left + box.width / 2)) / radius;
      let dy = (e.clientY - (box.top + box.height / 2)) / radius;
      const len = Math.hypot(dx, dy);
      if (len > 1) {
        dx /= len;
        dy /= len;
      }
      place(dx, dy);
      for (const m of vector.update(dx, dy)) send(m);
    };
    const down = (e: PointerEvent) => {
      if (pointerId !== null) return;
      pointerId = e.pointerId;
      el.setPointerCapture(e.pointerId);
      e.preventDefault();
      e.stopPropagation();
      update(e);
    };
    const move = (e: PointerEvent) => {
      if (e.pointerId !== pointerId) return;
      e.stopPropagation();
      update(e);
    };
    const up = (e: PointerEvent) => {
      if (e.pointerId !== pointerId) return;
      pointerId = null;
      e.stopPropagation();
      place(0, 0);
      for (const m of vector.release()) send(m);
    };
    el.addEventListener("pointerdown", down);
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
    el.addEventListener("pointercancel", up);
    return () => {
      el.removeEventListener("pointerdown", down);
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", up);
      el.removeEventListener("pointercancel", up);
      for (const m of vector.release()) send(m);
    };
  }, [send, size]);

  return (
    <div
      class="joystick"
      ref={ref}
      style={{ width: size, height: size }}
      role="slider"
      tabIndex={0}
      aria-label="Move"
      aria-valuenow={0}
    >
      <div class="knob" ref={knobRef} />
    </div>
  );
}

/** Press-and-hold button that sends an INPUT key down/up. */
export function HoldButton({
  send,
  keyName,
  label,
  class: cls,
}: SendProps & { keyName: "SPACE" | "SHIFT"; label: string; class?: string }) {
  const ref = useRef<HTMLButtonElement>(null);
  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    let held = false;
    const press = (e: PointerEvent) => {
      e.preventDefault();
      e.stopPropagation();
      if (held) return;
      held = true;
      el.classList.add("active");
      send({ type: "INPUT", key: keyName, pressed: true });
    };
    const release = (e: PointerEvent) => {
      e.stopPropagation();
      if (!held) return;
      held = false;
      el.classList.remove("active");
      send({ type: "INPUT", key: keyName, pressed: false });
    };
    el.addEventListener("pointerdown", press);
    el.addEventListener("pointerup", release);
    el.addEventListener("pointercancel", release);
    el.addEventListener("pointerleave", release);
    return () => {
      el.removeEventListener("pointerdown", press);
      el.removeEventListener("pointerup", release);
      el.removeEventListener("pointercancel", release);
      el.removeEventListener("pointerleave", release);
      if (held) send({ type: "INPUT", key: keyName, pressed: false });
    };
  }, [send, keyName]);
  return (
    <button type="button" class={`hold ${cls ?? ""}`} ref={ref} aria-label={label}>
      {label}
    </button>
  );
}
