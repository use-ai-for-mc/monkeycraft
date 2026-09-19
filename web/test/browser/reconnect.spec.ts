import { expect, test } from "@playwright/test";
import { drainServerLog, loginToReplay, replayControl } from "./helpers.ts";

test("keeps the stream page through an unexpected close and automatic reconnect", async ({
  page,
}) => {
  const tag = await loginToReplay(page);
  await drainServerLog(page, tag);
  await replayControl(page, "/replay close 1011");

  const reconnecting = page.getByText("Reconnecting…", { exact: true });
  await expect(reconnecting).toBeVisible({ timeout: 5_000 });
  await expect(page.locator(".stream")).toBeVisible({ timeout: 15_000 });
  await expect(reconnecting).toHaveCount(0, { timeout: 15_000 });
  await expect(page.locator(".debug")).toContainText(/link connected/, { timeout: 15_000 });
  const reconnected = await drainServerLog(page, tag);
  expect(reconnected.filter((message) => message.type === "AUTH")).toHaveLength(1);
  expect(reconnected.filter((message) => message.type === "CLIENT_STATUS")).toHaveLength(1);
});
