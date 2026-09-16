import { expect, test } from "@playwright/test";
import { drainServerLog, loginToReplay, replayControl, waitForDecoded } from "./helpers.ts";

test("map mode shows coordinates and rides a tapped boat", async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 600 });
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await drainServerLog(page, tag);

  await page.getByRole("button", { name: "Map" }).click();
  await page.waitForTimeout(200);
  let log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "CLIENT_STATUS")).toEqual([
    expect.objectContaining({ mode: "MAP" }),
  ]);
  await replayControl(page, "/replay map");
  await expect(page.locator(".coords")).toHaveText("X: 100.0 Z: 200.0");

  // Picture is 360x640 pillarboxed in 800x600 -> 337.5x600 at x 231..569.
  // The boat sits 5 blocks south of the player: ny = 0.5 + 5 / (2 * 20 tan 35°) ≈ 0.678.
  const halfH = 20 * Math.tan((35 * Math.PI) / 180);
  const ny = 0.5 + 5 / (2 * halfH);
  await page.mouse.click(400, Math.round(ny * 600));
  const sheet = page.getByTestId("ride-sheet");
  await expect(sheet).toBeVisible();
  await expect(sheet.getByRole("heading")).toHaveText("Boat");
  await sheet.getByRole("button", { name: "Ride" }).click();
  await page.waitForTimeout(200);
  log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "MAP_INTERACT")).toEqual([
    { type: "MAP_INTERACT", entityId: 4242 },
  ]);

  await page.getByRole("button", { name: "Map" }).click();
  await page.waitForTimeout(200);
  log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "CLIENT_STATUS")).toEqual([
    expect.objectContaining({ mode: "STREAMING" }),
  ]);
});
