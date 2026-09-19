// Drives the real H264Decoder wrapper in Chromium with recorded access units.

import { expect, test } from "@playwright/test";
import { binaryOf, isText, loadFixture } from "../helpers/fixture.ts";

function accessUnits(name: string): string[] {
  const fixture = loadFixture(name);
  const out: string[] = [];
  for (const line of fixture.lines) {
    if (isText(line) || line.bin.kind !== "video") continue;
    const bytes = binaryOf(fixture, line);
    const au = line.bin.header ? bytes.subarray(6) : bytes;
    out.push(Buffer.from(au).toString("base64"));
  }
  return out;
}

interface Result {
  received: number;
  decoded: number;
  dropped: number;
  waitedForKey: number;
  errors: number;
  configures: number;
  keyframeRequests: number;
  codec: string | null;
  lastError: string | null;
  width: number;
  height: number;
}

async function decodeInPage(page: import("@playwright/test").Page, aus: string[]): Promise<Result> {
  await page.goto("./");
  return page.evaluate(async (list) => {
    type Hook = {
      H264Decoder: new (
        cb: {
          onFrame: (f: VideoFrame) => void;
          onKeyframeNeeded: () => void;
        },
        opts: { fps: number },
      ) => {
        start(): Promise<boolean>;
        push(au: Uint8Array): void;
        drain(): Promise<void>;
        close(): void;
        stats: Omit<Result, "width" | "height">;
      };
    };
    const { H264Decoder } = (globalThis as unknown as { __monkeycraft: Hook }).__monkeycraft;
    let width = 0;
    let height = 0;
    const decoder = new H264Decoder(
      {
        onFrame: (f) => {
          width = f.displayWidth;
          height = f.displayHeight;
          f.close();
        },
        onKeyframeNeeded: () => {},
      },
      { fps: 10 },
    );
    if (!(await decoder.start())) throw new Error("unsupported");
    for (const b64 of list) {
      const bin = atob(b64);
      const au = new Uint8Array(bin.length);
      for (let i = 0; i < bin.length; i++) au[i] = bin.charCodeAt(i);
      decoder.push(au);
      // Pace like a 20 fps stream so the queue policy sees realistic depth.
      await new Promise((r) => setTimeout(r, 50));
    }
    await decoder.drain();
    const stats = decoder.stats;
    decoder.close();
    return { ...stats, width, height };
  }, aus);
}

test("decodes the IDR/P alternating stream with a single configure", async ({ page }) => {
  const aus = accessUnits("streaming-360x640");
  expect(aus.length).toBeGreaterThan(50);
  const r = await decodeInPage(page, aus);
  expect(r.errors).toBe(0);
  expect(r.configures).toBe(1);
  expect(r.codec).toMatch(/^avc1\.42/);
  expect(r.decoded).toBeGreaterThanOrEqual(aus.length - 3);
  expect(r.width).toBe(360);
  expect(r.height).toBe(640);
});

test("decodes the data-saver GOP stream", async ({ page }) => {
  const aus = accessUnits("streaming-360x640-datasaver");
  expect(aus.length).toBeGreaterThan(100);
  const r = await decodeInPage(page, aus);
  expect(r.errors).toBe(0);
  expect(r.configures).toBe(1);
  expect(r.decoded).toBeGreaterThanOrEqual(aus.length - 3);
  expect(r.keyframeRequests).toBe(0);
});

test("survives an inventory screen open/close cycle", async ({ page }) => {
  const aus = accessUnits("inventory-360x640");
  const r = await decodeInPage(page, aus);
  expect(r.errors).toBe(0);
  expect(r.decoded).toBeGreaterThanOrEqual(aus.length - 3);
});
