// Regression for the Flutter-web reconnect loop: a resize storm must not
// recreate the decoder, blank the video, or spam CLIENT_STATUS.

import { expect, test } from "@playwright/test";
import { drainServerLog, loginToReplay, readDebug, waitForDecoded } from "./helpers.ts";

test("a resize storm keeps one decoder and sends at most a few CLIENT_STATUS", async ({ page }) => {
  await page.setViewportSize({ width: 1000, height: 700 });
  await loginToReplay(page);
  await waitForDecoded(page, 10);
  await drainServerLog(page);

  for (let i = 0; i < 20; i++) {
    const w = 700 + ((i * 137) % 600);
    const h = 500 + ((i * 89) % 400);
    await page.setViewportSize({ width: w, height: h });
    await page.waitForTimeout(40);
  }
  await page.waitForTimeout(1500);
  const before = await readDebug(page);
  await page.waitForTimeout(1500);
  const after = await readDebug(page);

  expect(after.err).toBe(0);
  expect(after.cfg).toBe(1);
  expect(after.dec).toBeGreaterThan(before.dec + 5);
  expect(after.link).toBe("connected");

  const statuses = (await drainServerLog(page)).filter((m) => m.type === "CLIENT_STATUS");
  expect(statuses.length).toBeLessThanOrEqual(3);
  // The picture is sized from decoded frames, never from the request.
  const canvas = page.locator(".video-host canvas");
  await expect(canvas).toHaveAttribute("width", "360");
  await expect(canvas).toHaveAttribute("height", "640");
});

test("browser zoom does not blank the video", async ({ page }) => {
  await loginToReplay(page);
  await waitForDecoded(page, 10);
  await page.evaluate(() => {
    document.body.style.zoom = "1.5";
  });
  await page.waitForTimeout(1200);
  const before = await readDebug(page);
  await page.waitForTimeout(1200);
  const after = await readDebug(page);
  expect(after.dec).toBeGreaterThan(before.dec + 3);
  expect(after.cfg).toBe(1);
});
