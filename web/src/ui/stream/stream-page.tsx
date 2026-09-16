import { useSignal } from "@preact/signals";
import { useEffect, useRef } from "preact/hooks";
import { computeStreamSize, type StreamSize, shouldRenegotiate } from "../../session/resolution.ts";
import { deriveView } from "../../session/session.ts";
import { type DecoderStats, H264Decoder } from "../../video/decoder.ts";
import { CanvasRenderer } from "../../video/renderer.ts";
import type { AppContext } from "../app.tsx";

interface Props {
  ctx: AppContext;
  onLeave: () => void;
}

const RESIZE_DEBOUNCE_MS = 500;

export function StreamPage({ ctx, onLeave }: Props) {
  const hostRef = useRef<HTMLDivElement>(null);
  const unsupported = useSignal<string | null>(null);
  const stats = useSignal<DecoderStats | null>(null);
  const measuredFps = useSignal(0);
  const debug = new URLSearchParams(window.location.search).get("debug") === "1";

  useEffect(() => {
    const host = hostRef.current;
    if (!host) return;
    const controller = ctx.controller;
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

    // Measured fps for the debug overlay.
    let lastDrawn = 0;
    const fpsTimer = setInterval(() => {
      measuredFps.value = renderer.framesDrawn - lastDrawn;
      lastDrawn = renderer.framesDrawn;
    }, 1000);

    return () => {
      disposed = true;
      offVideo();
      observer.disconnect();
      if (timer !== null) clearTimeout(timer);
      clearInterval(fpsTimer);
      decoder.close();
      renderer.destroy();
    };
  }, [ctx]);

  const state = ctx.controller.state.value;
  const view = deriveView(state);

  return (
    <main class="stream">
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
      <div class="toolbar">
        <button type="button" onClick={onLeave} title="Disconnect">
          ✕
        </button>
      </div>
      {debug && stats.value && (
        <pre class="debug">
          {`fps ${measuredFps.value}  recv ${stats.value.received}  dec ${stats.value.decoded}  drop ${stats.value.dropped}  wait ${stats.value.waitedForKey}
err ${stats.value.errors}  cfg ${stats.value.configures}  kf ${stats.value.keyframeRequests}  q ${stats.value.queueSize}  ${stats.value.codec ?? "-"}
server ${state.serverSize ? `${state.serverSize.width}x${state.serverSize.height}` : "-"}  req ${state.requestedSize ? `${state.requestedSize.width}x${state.requestedSize.height}` : "-"}  link ${state.link.phase}${stats.value.lastError ? `\n${stats.value.lastError}` : ""}`}
        </pre>
      )}
    </main>
  );
}
