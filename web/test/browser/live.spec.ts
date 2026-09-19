// End-to-end against a running mod through the Vite dev server proxy.
// Skipped unless MONKEYCRAFT_LIVE=1 and MONKEYCRAFT_PASSWORD are set:
//
//   node node_modules/vite/bin/vite.js --host 127.0.0.1 &
//   MONKEYCRAFT_LIVE=1 MONKEYCRAFT_PASSWORD=... node node_modules/@playwright/test/cli.js test test/browser/live.spec.ts

import { expect, test } from "@playwright/test";

test.use({ trace: "off" });

const live = process.env.MONKEYCRAFT_LIVE === "1";
const password = process.env.MONKEYCRAFT_PASSWORD ?? "";
const devUrl = process.env.MONKEYCRAFT_DEV_URL ?? "http://127.0.0.1:5173";
const liveUrl = process.env.MONKEYCRAFT_LIVE_URL ?? `${devUrl}/ws`;
const pageUrl = process.env.MONKEYCRAFT_PAGE_URL ?? devUrl;
const soak = process.env.MONKEYCRAFT_LIVE_SOAK === "1";
const maxFps = process.env.MONKEYCRAFT_LIVE_MAX_FPS === "1";

test.skip(!live || password === "", "set MONKEYCRAFT_LIVE=1 and MONKEYCRAFT_PASSWORD");
test.describe.configure({ mode: "serial" });

test("logs in through the dev proxy and draws video frames", async ({ page }) => {
  await page.goto(`${pageUrl}/?debug=1`);
  if (liveUrl.startsWith("https://")) expect(await page.evaluate(() => isSecureContext)).toBe(true);
  await page.getByLabel("Server address").fill(liveUrl);
  const usePassword = page.getByRole("button", { name: "Use password instead" });
  if (await usePassword.isVisible()) await usePassword.click();
  await page.getByRole("textbox", { name: "Password" }).fill(password);
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.locator(".stream")).toBeVisible({ timeout: 15_000 });
  const picker = page.getByTestId("picker-panel");
  if (await picker.isVisible()) {
    await picker.getByRole("button", { name: /mp\.imaginefun\.net/ }).click();
    await expect(picker).toHaveCount(0, { timeout: 30_000 });
  }
  const debug = page.locator(".debug");
  await expect(debug).toBeVisible({ timeout: 10_000 });
  await expect
    .poll(
      async () => {
        const text = (await debug.textContent()) ?? "";
        const m = /dec (\d+)/.exec(text);
        return m ? Number(m[1]) : 0;
      },
      { timeout: 30_000, message: "decoded frames" },
    )
    .toBeGreaterThan(20);
  const text = (await debug.textContent()) ?? "";
  expect(text).toMatch(/err 0/);
  expect(text).toMatch(/cfg 1/);
  const palette = page.getByTestId("screen-palette");
  const host = page.locator(".video-host");
  await host.evaluate((element) => {
    element.tabIndex = -1;
    element.focus();
  });
  if (await palette.isVisible()) {
    await page.keyboard.press("Escape");
    await expect(palette).toHaveCount(0, { timeout: 5_000 });
  }
  await page.screenshot({ path: "test-results/live-stream.png" });
  await page.keyboard.press("KeyE");
  await expect(palette).toBeVisible({ timeout: 5_000 });
  await expect.poll(() => page.evaluate(() => document.pointerLockElement === null)).toBe(true);
  const decodedBeforeInventory = Number(
    /dec (\d+)/.exec((await debug.textContent()) ?? "")?.[1] ?? 0,
  );
  await expect
    .poll(() =>
      debug.textContent().then((value) => Number(/dec (\d+)/.exec(value ?? "")?.[1] ?? 0)),
    )
    .toBeGreaterThan(decodedBeforeInventory + 3);
  await page.screenshot({ path: "test-results/live-inventory.png" });
  await page.keyboard.press("Escape");
  await expect(palette).toHaveCount(0, { timeout: 5_000 });
});

test("keeps decoding through a ten-minute live soak and resize cycle", async ({
  page,
}, testInfo) => {
  test.skip(!soak, "set MONKEYCRAFT_LIVE_SOAK=1 for the ten-minute run");
  test.setTimeout(12 * 60_000);
  await page.setViewportSize({ width: 1000, height: 700 });
  await page.goto(`${pageUrl}/?debug=1`);
  if (liveUrl.startsWith("https://")) expect(await page.evaluate(() => isSecureContext)).toBe(true);
  await page.getByLabel("Server address").fill(liveUrl);
  const usePassword = page.getByRole("button", { name: "Use password instead" });
  if (await usePassword.isVisible()) await usePassword.click();
  await page.getByRole("textbox", { name: "Password" }).fill(password);
  await page.getByRole("button", { name: "Connect" }).click();
  const debug = page.locator(".debug");
  await expect(debug).toBeVisible({ timeout: 15_000 });
  await expect
    .poll(async () => Number(/dec (\d+)/.exec((await debug.textContent()) ?? "")?.[1] ?? 0), {
      timeout: 30_000,
    })
    .toBeGreaterThan(20);

  if (maxFps) {
    await page.getByRole("button", { name: "Settings", exact: true }).click();
    const frameRate = page.getByRole("slider", { name: /^Frame rate:/ });
    await frameRate.focus();
    await frameRate.press("End");
    await expect(frameRate).toHaveValue("20");
    await page.getByRole("button", { name: "Apply", exact: true }).click();
    await expect(page.getByTestId("settings-panel")).toHaveCount(0);
  }

  const started = Date.now();
  const samples: Array<{ elapsedMs: number; viewport: unknown; debug: string }> = [];
  const sample = async () => {
    const value = {
      elapsedMs: Date.now() - started,
      viewport: page.viewportSize(),
      debug: (await debug.textContent()) ?? "",
    };
    samples.push(value);
    console.log(JSON.stringify({ soakSample: value }));
    return value.debug;
  };
  await sample();

  const resizeSteps: Array<{ width: number; height: number }> = [
    { width: 800, height: 600 },
    { width: 1200, height: 700 },
    { width: 700, height: 900 },
    { width: 1000, height: 700 },
  ];
  let decoded = 20;
  for (const { width, height } of resizeSteps) {
    await page.waitForTimeout(140_000);
    const text = await sample();
    const nextDecoded = Number(/dec (\d+)/.exec(text)?.[1] ?? 0);
    expect(nextDecoded).toBeGreaterThan(decoded + 20);
    expect(text).toMatch(/err 0/);
    expect(text).toMatch(/link connected/);
    decoded = nextDecoded;
    await page.setViewportSize({ width, height });
  }
  await page.waitForTimeout(40_000);
  const text = await sample();
  expect(text).toMatch(/err 0/);
  expect(text).toMatch(/link connected/);
  expect(Number(/dec (\d+)/.exec(text)?.[1] ?? 0)).toBeGreaterThan(decoded + 10);
  await testInfo.attach("live-soak-samples", {
    body: JSON.stringify(samples, null, 2),
    contentType: "application/json",
  });
});
