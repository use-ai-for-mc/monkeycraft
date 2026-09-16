// WebCodecs H.264 decoder wrapper (docs/PLAN.md 2.4).
//
// Lifecycle rules:
// - one VideoDecoder for the life of this object; configure() again only when
//   the in-band SPS bytes change; recreate only after a WebCodecs error;
// - never touched by resize or CLIENT_STATUS;
// - admission through DecodeQueuePolicy; "reset" flushes and waits for a key,
//   it does not destroy the decoder.

import { bytesEqual, codecStringFromSps, containsIdr, findSps } from "../protocol/h264.ts";
import { DecodeQueuePolicy } from "./queue-policy.ts";

export interface DecoderStats {
  received: number;
  decoded: number;
  dropped: number;
  waitedForKey: number;
  errors: number;
  configures: number;
  keyframeRequests: number;
  queueSize: number;
  codec: string | null;
  lastError: string | null;
}

export interface DecoderCallbacks {
  /** The consumer owns the frame and must call frame.close(). */
  onFrame: (frame: VideoFrame) => void;
  onKeyframeNeeded: () => void;
  onUnsupported?: (message: string) => void;
  onStats?: (stats: DecoderStats) => void;
}

export interface DecoderOptions {
  fps?: number;
  policy?: DecodeQueuePolicy;
  /** Codec string to probe support with before any SPS has been seen. */
  probeCodec?: string;
}

export const DEFAULT_CODEC = "avc1.420028";

export class H264Decoder {
  private decoder: VideoDecoder | null = null;
  private readonly policy: DecodeQueuePolicy;
  private fps: number;
  private frameIndex = 0;
  private currentSps: Uint8Array | null = null;
  private codec: string | null = null;
  private closed = false;
  private supported: boolean | null = null;
  readonly stats: DecoderStats = {
    received: 0,
    decoded: 0,
    dropped: 0,
    waitedForKey: 0,
    errors: 0,
    configures: 0,
    keyframeRequests: 0,
    queueSize: 0,
    codec: null,
    lastError: null,
  };

  constructor(
    private readonly cb: DecoderCallbacks,
    opts: DecoderOptions = {},
  ) {
    this.fps = opts.fps && opts.fps > 0 ? opts.fps : 10;
    this.policy = opts.policy ?? new DecodeQueuePolicy();
    this.probeCodec = opts.probeCodec ?? DEFAULT_CODEC;
  }

  private readonly probeCodec: string;

  static available(): boolean {
    return typeof VideoDecoder !== "undefined" && typeof EncodedVideoChunk !== "undefined";
  }

  /** Probe support once. Returns false (and reports) when this browser cannot decode. */
  async start(): Promise<boolean> {
    if (this.supported !== null) return this.supported;
    if (!H264Decoder.available()) {
      this.supported = false;
      this.fail("WebCodecs is not available in this browser (needs a secure context).");
      return false;
    }
    try {
      const result = await VideoDecoder.isConfigSupported(this.config(this.probeCodec));
      this.supported = result.supported === true;
    } catch (err) {
      this.supported = false;
      this.fail(`WebCodecs probe failed: ${String(err)}`);
      return false;
    }
    if (!this.supported) this.fail(`This browser cannot decode ${this.probeCodec}.`);
    return this.supported;
  }

  setFps(fps: number): void {
    if (fps > 0) this.fps = fps;
  }

  /** Feed one access unit (header already stripped). Synchronous; never throws. */
  push(au: Uint8Array): void {
    if (this.closed || this.supported !== true) return;
    this.stats.received += 1;
    const isKey = containsIdr(au);

    if (isKey) {
      const sps = findSps(au);
      if (sps && !bytesEqual(sps, this.currentSps)) this.configure(sps);
    }
    if (!this.decoder) {
      this.stats.waitedForKey += 1;
      this.report();
      return;
    }

    const action = this.policy.decide(isKey, this.decoder.decodeQueueSize);
    switch (action) {
      case "wait-for-key":
        this.stats.waitedForKey += 1;
        break;
      case "drop":
        this.stats.dropped += 1;
        break;
      case "reset-and-wait-for-key":
        this.stats.dropped += 1;
        this.resync();
        break;
      case "decode":
        this.decode(au, isKey);
        break;
    }
    this.report();
  }

  close(): void {
    this.closed = true;
    this.destroyDecoder();
  }

  private config(codec: string): VideoDecoderConfig {
    return { codec, optimizeForLatency: true, hardwareAcceleration: "no-preference" };
  }

  private configure(sps: Uint8Array): void {
    const codec = codecStringFromSps(sps) ?? this.probeCodec;
    this.currentSps = sps.slice();
    this.codec = codec;
    this.stats.codec = codec;
    try {
      if (!this.decoder || this.decoder.state === "closed") this.createDecoder();
      this.decoder?.configure(this.config(codec));
      this.stats.configures += 1;
      this.policy.requireKey();
    } catch (err) {
      this.onError(err);
    }
  }

  private createDecoder(): void {
    this.destroyDecoder();
    this.decoder = new VideoDecoder({
      output: (frame) => {
        this.stats.decoded += 1;
        this.cb.onFrame(frame);
      },
      error: (err) => this.onError(err),
    });
  }

  private destroyDecoder(): void {
    const d = this.decoder;
    this.decoder = null;
    if (d && d.state !== "closed") {
      try {
        d.close();
      } catch {
        // already closed
      }
    }
  }

  private decode(au: Uint8Array, isKey: boolean): void {
    const d = this.decoder;
    if (d?.state !== "configured") {
      this.stats.waitedForKey += 1;
      return;
    }
    const duration = Math.round(1_000_000 / this.fps);
    const chunk = new EncodedVideoChunk({
      type: isKey ? "key" : "delta",
      timestamp: this.frameIndex * duration,
      duration,
      data: au as BufferSource,
    });
    try {
      d.decode(chunk);
      this.frameIndex += 1;
    } catch (err) {
      this.onError(err);
    }
  }

  /** Queue too deep: flush what is pending and start again from the next IDR. */
  private resync(): void {
    const d = this.decoder;
    if (d && d.state === "configured") {
      d.flush().catch(() => {
        // flush rejects when the decoder is reset or closed meanwhile; harmless
      });
    }
    this.policy.requireKey();
    this.requestKeyframe();
  }

  private onError(err: unknown): void {
    this.stats.errors += 1;
    this.stats.lastError = err instanceof Error ? err.message : String(err);
    // A WebCodecs error closes the decoder; the next keyframe recreates it.
    this.destroyDecoder();
    this.currentSps = null;
    this.policy.requireKey();
    this.requestKeyframe();
    this.report();
  }

  private requestKeyframe(): void {
    this.stats.keyframeRequests += 1;
    this.cb.onKeyframeNeeded();
  }

  private fail(message: string): void {
    this.stats.lastError = message;
    this.cb.onUnsupported?.(message);
    this.report();
  }

  private report(): void {
    this.stats.queueSize = this.decoder?.decodeQueueSize ?? 0;
    this.cb.onStats?.(this.stats);
  }

  get codecString(): string | null {
    return this.codec;
  }
}
