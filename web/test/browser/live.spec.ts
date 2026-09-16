// End-to-end against a running mod through the Vite dev server proxy.
// Skipped unless MONKEYCRAFT_LIVE=1 and MONKEYCRAFT_PASSWORD are set:
//
//   pnpm dev &                      # http://127.0.0.1:5173, proxies /ws to the mod
//   MONKEYCRAFT_LIVE=1 MONKEYCRAFT_PASSWORD=... pnpm test:browser test/browser/live.spec.ts

import { expect, test } from "@playwright/test";

const live = process.env.MONKEYCRAFT_LIVE === "1";
const password = process.env.MONKEYCRAFT_PASSWORD ?? "";
const devUrl = process.env.MONKEYCRAFT_DEV_URL ?? "http://127.0.0.1:5173";

test.skip(!live || password === "", "set MONKEYCRAFT_LIVE=1 and MONKEYCRAFT_PASSWORD");

test("logs in through the dev proxy and draws video frames", async ({ page }) => {
  await page.goto(`${devUrl}/?debug=1`);
  await page.getByLabel("Server address").fill(`${devUrl}/ws`);
  const usePassword = page.getByRole("button", { name: "Use password instead" });
  if (await usePassword.isVisible()) await usePassword.click();
  await page.getByRole("textbox", { name: "Password" }).fill(password);
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.locator(".stream")).toBeVisible({ timeout: 15_000 });
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
  await page.screenshot({ path: "test-results/live-stream.png" });

  // Real inventory round trip: E opens it (SCREEN_STATE true -> palette),
  // physical Escape closes it (SCREEN_STATE false -> palette gone).
  const palette = page.getByTestId("screen-palette");
  await page.mouse.click(400, 300);
  await page.keyboard.press("KeyE");
  await expect(palette).toBeVisible({ timeout: 5_000 });
  await page.screenshot({ path: "test-results/live-inventory.png" });
  await page.keyboard.press("Escape");
  await expect(palette).toHaveCount(0, { timeout: 5_000 });
});
