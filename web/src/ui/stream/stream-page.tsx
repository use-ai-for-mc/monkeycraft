import { useSignal } from "@preact/signals";
import { useCallback, useEffect, useRef } from "preact/hooks";
import { isEditableTarget, KeyboardMapper } from "../../input/keyboard.ts";
import { hasCoarsePointer, showTouchControls } from "../../input/layout.ts";
import { LookAccumulator } from "../../input/look.ts";
import { PointerController, type PointerKind } from "../../input/pointer.ts";
import { type ClickMode, ScreenMode } from "../../input/screen-mode.ts";
import { isFullscreen, toggleFullscreen } from "../../platform/fullscreen.ts";
import { WakeLock } from "../../platform/wake-lock.ts";
import type { MapEntity, MapFrame } from "../../protocol/frames.ts";
import type { ClientMessage } from "../../protocol/messages.ts";
import { isRideable, pickEntity } from "../../session/map.ts";
import { computeStreamSize, type StreamSize, shouldRenegotiate } from "../../session/resolution.ts";
import { deriveView } from "../../session/session.ts";
import { type DecoderStats, H264Decoder } from "../../video/decoder.ts";
import { CanvasRenderer, type DisplayRect } from "../../video/renderer.ts";
import type { AppContext } from "../app.tsx";
import { Hotbar } from "./hotbar.tsx";
import { ScreenPalette } from "./palette.tsx";
import { HoldButton, Joystick } from "./touch-pads.tsx";

interface Props {
  ctx: AppContext;
  onLeave: () => void;
  onOpenChat: () => void;
  onOpenSettings: () => void;
}

const RESIZE_DEBOUNCE_MS = 500;

export function StreamPage({ ctx, onLeave, onOpenChat, onOpenSettings }: Props) {
  const hostRef = useRef<HTMLDivElement>(null);
  const pageRef = useRef<HTMLElement>(null);
  const unsupported = useSignal<string | null>(null);
  const stats = useSignal<DecoderStats | null>(null);
  const measuredFps = useSignal(0);
  const lastPointer = useSignal<PointerKind | null>(null);
  const hotbarSlot = useSignal(0);
  const hotbarOpen = useSignal(false);
  const paletteOpen = useSignal(false);
  const shiftActive = useSignal(false);
  const clickMode = useSignal<ClickMode>("left");
  const fullscreen = useSignal(isFullscreen());
  const mapFrame = useSignal<MapFrame | null>(null);
  const ridePick = useSignal<MapEntity | null>(null);
  const timedLeft = useSignal<string | null>(null);
  const debug = new URLSearchParams(window.location.search).get("debug") === "1";

  const controller = ctx.controller;
  const send = useCallback((msg: ClientMessage) => controller.send(msg), [controller]);
  const screenModeRef = useRef(new ScreenMode());
  const pointerRef = useRef<PointerController | null>(null);

  const selectSlot = useCallback(
    (slot: number) => {
      const s = ((slot % 9) + 9) % 9;
      hotbarSlot.value = s;
      send({ type: "HOTBAR_SELECT", slot: s });
    },
    [send, hotbarSlot],
  );

  // Video pipeline + pointer input, bound to the host element.
  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const renderer = new CanvasRenderer(host);
    const decoder = new H264Decoder(
      {
        onFrame: (frame) => renderer.draw(frame),
        onKeyframeNeeded: () => controller.requestKeyframe(),
        onUnsupported: (message) => {
          unsupported.value = message;
        },
        onStats: (s) => {
          stats.value = { ...s };
        },
      },
      { fps: ctx.settings.value.fps },
    );
    let disposed = false;
    const offVideo = controller.onVideo((au) => decoder.push(au));
    decoder.start().catch(() => {});
    const offSettings = ctx.settings.subscribe((s) => decoder.setFps(s.fps));

    let rect: DisplayRect = renderer.displayRect;
    renderer.setRectListener((r) => {
      rect = r;
    });

    const look = new LookAccumulator({
      sensitivity: ctx.settings.value.lookSensitivity,
      invertY: ctx.settings.value.invertLookY,
    });
    const offLook = ctx.settings.subscribe((s) => {
      look.sensitivity = s.lookSensitivity;
      look.invertY = s.invertLookY;
    });
    const pointer = new PointerController({
      element: host,
      send,
      rect: () => rect,
      screenOpen: () => controller.snapshot.screenOpen,
      look,
      screenMode: screenModeRef.current,
      onPointerKind: (kind) => {
        lastPointer.value = kind;
      },
      onHotbarStep: (delta) => selectSlot(hotbarSlot.value + delta),
      usePointerLock: () => ctx.settings.value.controlLayout !== "touch",
      mapMode: () => controller.snapshot.mode === "MAP",
      onMapTap: (nx, ny) => {
        const frame = mapFrame.value;
        const size = controller.snapshot.serverSize;
        if (!frame || !size) return;
        const hit = pickEntity(frame, nx, ny, size.width / size.height);
        if (hit && isRideable(hit)) ridePick.value = hit;
      },
    });
    const offMap = controller.onEvent((ev) => {
      if (ev.kind === "map") mapFrame.value = ev.frame;
    });
    pointer.attach();
    pointerRef.current = pointer;

    // Requested size policy: once now, then on debounced meaningful resizes.
    let lastViewport: { cssWidth: number; cssHeight: number } | null = null;
    let lastSize: StreamSize | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;
    const negotiate = () => {
      const box = host.getBoundingClientRect();
      const input = {
        cssWidth: box.width,
        cssHeight: box.height,
        devicePixelRatio: window.devicePixelRatio || 1,
        preset: ctx.settings.value.preset,
      };
      if (!shouldRenegotiate(lastViewport, lastSize, input)) return;
      lastViewport = { cssWidth: input.cssWidth, cssHeight: input.cssHeight };
      lastSize = computeStreamSize(input);
      controller.setRequestedSize(lastSize);
    };
    negotiate();
    const observer = new ResizeObserver(() => {
      if (timer !== null) clearTimeout(timer);
      timer = setTimeout(() => {
        timer = null;
        if (!disposed) negotiate();
      }, RESIZE_DEBOUNCE_MS);
    });
    observer.observe(host);

    let lastDrawn = 0;
    const fpsTimer = setInterval(() => {
      measuredFps.value = renderer.framesDrawn - lastDrawn;
      lastDrawn = renderer.framesDrawn;
    }, 1000);

    const wakeLock = new WakeLock();
    void wakeLock.request();

    return () => {
      disposed = true;
      offVideo();
      offSettings();
      offLook();
      offMap();
      observer.disconnect();
      if (timer !== null) clearTimeout(timer);
      clearInterval(fpsTimer);
      wakeLock.release();
      pointer.detach();
      pointerRef.current = null;
      decoder.close();
      renderer.destroy();
    };
  }, [
    ctx,
    controller,
    send,
    selectSlot,
    hotbarSlot,
    lastPointer,
    measuredFps,
    stats,
    unsupported,
    mapFrame,
    ridePick,
  ]);

  // Timed notification countdown (ride end).
  useEffect(() => {
    const tick = () => {
      const timed = controller.snapshot.timed;
      if (!timed) {
        timedLeft.value = null;
        return;
      }
      const left = Math.max(0, Math.round((timed.fireAtEpochMs - Date.now()) / 1000));
      timedLeft.value =
        `${timed.countDownText ?? timed.title ?? ""} ${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`.trim();
    };
    tick();
    const timer = setInterval(tick, 1000);
    return () => clearInterval(timer);
  }, [controller, timedLeft]);

  // Keyboard, focus loss, screen-state transitions.
  useEffect(() => {
    const keys = new KeyboardMapper();
    const releaseAll = () => {
      for (const m of keys.releaseAll()) send(m);
    };
    const onKey = (pressed: boolean) => (e: KeyboardEvent) => {
      const outputs = pressed
        ? keys.keyDown({ code: e.code, repeat: e.repeat, editable: isEditableTarget(e.target) })
        : keys.keyUp({ code: e.code });
      for (const out of outputs) {
        switch (out.kind) {
          case "send":
            send(out.msg);
            e.preventDefault();
            break;
          case "hotbar":
            selectSlot(out.slot);
            e.preventDefault();
            break;
          case "escape":
            if (controller.snapshot.screenOpen) {
              send(ScreenMode.escape(out.pressed));
              e.preventDefault();
            }
            break;
          default:
            break;
        }
      }
    };
    const down = onKey(true);
    const up = onKey(false);
    const onHidden = () => {
      if (document.hidden) releaseAll();
    };
    window.addEventListener("keydown", down);
    window.addEventListener("keyup", up);
    window.addEventListener("blur", releaseAll);
    document.addEventListener("visibilitychange", onHidden);
    const onFullscreen = () => {
      fullscreen.value = isFullscreen();
    };
    document.addEventListener("fullscreenchange", onFullscreen);

    let wasOpen = controller.snapshot.screenOpen;
    let wasHibernating = controller.snapshot.hibernating;
    const unsubscribe = controller.state.subscribe((s) => {
      if (s.screenOpen !== wasOpen) {
        wasOpen = s.screenOpen;
        pointerRef.current?.setScreenOpen(s.screenOpen);
        releaseAll();
        if (!s.screenOpen) {
          paletteOpen.value = false;
          if (shiftActive.value) {
            shiftActive.value = false;
            send(ScreenMode.shift(false));
          }
        }
      }
      if (s.hibernating !== wasHibernating) {
        wasHibernating = s.hibernating;
        if (s.hibernating) releaseAll();
        else controller.requestKeyframe();
      }
    });
    return () => {
      window.removeEventListener("keydown", down);
      window.removeEventListener("keyup", up);
      window.removeEventListener("blur", releaseAll);
      document.removeEventListener("visibilitychange", onHidden);
      document.removeEventListener("fullscreenchange", onFullscreen);
      unsubscribe();
      releaseAll();
    };
  }, [controller, send, selectSlot, paletteOpen, shiftActive, fullscreen]);

  const state = controller.state.value;
  const view = deriveView(state);
  const touch = showTouchControls(
    ctx.settings.value.controlLayout,
    lastPointer.value,
    hasCoarsePointer(),
  );
  const mapMode = state.mode === "MAP";
  const showPads = (touch || mapMode) && view.showVideo && !state.screenOpen;
  const showPalette = view.showVideo && state.screenOpen && !mapMode;
  const toggleMap = () => {
    ridePick.value = null;
    controller.setMode(mapMode ? "STREAMING" : "MAP");
  };

  return (
    <main class="stream" ref={pageRef}>
      <div class="video-host" ref={hostRef} />
      {view.showHibernation && (
        <div class="overlay scrim">
          <p class="big">Paused</p>
          {state.hibernationMessage?.split("\n").map((line) => (
            <p key={line}>{line}</p>
          ))}
        </div>
      )}
      {view.showReconnecting && (
        <div class="overlay scrim">
          <p class="big">Reconnecting…</p>
        </div>
      )}
      {unsupported.value && (
        <div class="overlay scrim">
          <p>{unsupported.value}</p>
        </div>
      )}
      {state.nudge && (
        <button
          type="button"
          class="banner"
          onClick={() => controller.dismissNudge()}
          onPointerDown={(e) => e.stopPropagation()}
        >
          {state.nudge.title && <strong>{state.nudge.title} </strong>}
          {state.nudge.body}
        </button>
      )}
      {timedLeft.value && <div class="timed">{timedLeft.value}</div>}
      {mapMode && mapFrame.value && (
        <div class="coords">
          X: {mapFrame.value.playerX.toFixed(1)} Z: {mapFrame.value.playerZ.toFixed(1)}
        </div>
      )}
      {ridePick.value && (
        <div class="sheet-host" onPointerDown={(e) => e.stopPropagation()}>
          <button
            type="button"
            class="sheet-backdrop"
            aria-label="Close"
            onClick={() => (ridePick.value = null)}
          />
          <div class="sheet" data-testid="ride-sheet">
            <h3>{ridePick.value.name}</h3>
            <p class="muted">
              Position: {ridePick.value.x.toFixed(1)}, {ridePick.value.z.toFixed(1)}
            </p>
            <button
              type="button"
              class="ride"
              onClick={() => {
                const id = ridePick.value?.entityId;
                if (id !== undefined) send({ type: "MAP_INTERACT", entityId: id });
                ridePick.value = null;
              }}
            >
              Ride
            </button>
          </div>
        </div>
      )}
      <div class="toolbar" onPointerDown={(e) => e.stopPropagation()}>
        <button type="button" onClick={onOpenChat} title="Chat" aria-label="Chat">
          💬
        </button>
        <button
          type="button"
          onClick={toggleMap}
          title="Map"
          aria-label="Map"
          class={mapMode ? "active" : ""}
        >
          🗺
        </button>
        <button type="button" onClick={onOpenSettings} title="Settings" aria-label="Settings">
          ⚙
        </button>
        <button
          type="button"
          onClick={() => pageRef.current && toggleFullscreen(pageRef.current)}
          title={fullscreen.value ? "Exit fullscreen" : "Fullscreen"}
        >
          {fullscreen.value ? "⤡" : "⤢"}
        </button>
        <button type="button" onClick={onLeave} title="Disconnect">
          ✕
        </button>
      </div>
      {view.showVideo && (
        <Hotbar
          selected={hotbarSlot.value}
          expanded={hotbarOpen.value}
          onToggle={() => {
            hotbarOpen.value = !hotbarOpen.value;
          }}
          onSelect={(slot) => {
            selectSlot(slot);
            hotbarOpen.value = false;
          }}
          send={send}
          showKeys={!state.screenOpen}
        />
      )}
      {showPads && (
        <>
          <div class="pad-left" onPointerDown={(e) => e.stopPropagation()}>
            <Joystick send={send} />
          </div>
          <div class="pad-right" onPointerDown={(e) => e.stopPropagation()}>
            <HoldButton send={send} keyName="SPACE" label="Jump" class="jump" />
            <HoldButton send={send} keyName="SHIFT" label="Sneak" class="sneak" />
          </div>
        </>
      )}
      {showPalette && (
        <ScreenPalette
          expanded={paletteOpen.value}
          onToggle={() => {
            paletteOpen.value = !paletteOpen.value;
          }}
          onEscape={() => {
            send(ScreenMode.escape(true));
            send(ScreenMode.escape(false));
            paletteOpen.value = false;
          }}
          shiftActive={shiftActive.value}
          onShift={(active) => {
            shiftActive.value = active;
            send(ScreenMode.shift(active));
          }}
          clickMode={clickMode.value}
          onClickMode={(mode) => {
            clickMode.value = mode;
            screenModeRef.current.clickMode = mode;
          }}
          showClickModes={touch}
        />
      )}
      {debug && stats.value && (
        <pre class="debug">
          {`fps ${measuredFps.value}  recv ${stats.value.received}  dec ${stats.value.decoded}  drop ${stats.value.dropped}  wait ${stats.value.waitedForKey}
err ${stats.value.errors}  cfg ${stats.value.configures}  kf ${stats.value.keyframeRequests}  q ${stats.value.queueSize}  ${stats.value.codec ?? "-"}
server ${state.serverSize ? `${state.serverSize.width}x${state.serverSize.height}` : "-"}  req ${state.requestedSize ? `${state.requestedSize.width}x${state.requestedSize.height}` : "-"}  link ${state.link.phase}  screen ${state.screenOpen ? "open" : "closed"}  ptr ${lastPointer.value ?? "-"}${stats.value.lastError ? `\n${stats.value.lastError}` : ""}`}
        </pre>
      )}
    </main>
  );
}
