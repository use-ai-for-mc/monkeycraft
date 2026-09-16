// Chat, settings and picker panels against the replay server.

import { expect, test } from "@playwright/test";
import { drainServerLog, loginToReplay, replayControl, waitForDecoded } from "./helpers.ts";

test("chat subscribes, shows cached messages, sends, and prefills suggested commands", async ({
  page,
}) => {
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await drainServerLog(page, tag);

  await page.getByRole("button", { name: "Chat" }).click();
  const chat = page.getByTestId("chat-panel");
  await expect(chat).toBeVisible();
  await expect(chat.getByText("Welcome to the replay server")).toBeVisible();
  await expect(chat.getByText("👥 42")).toBeVisible();

  await chat.getByRole("button", { name: "click me" }).click();
  await expect(chat.getByPlaceholder("Message or /command")).toHaveValue("/warp hub");

  await chat.getByPlaceholder("Message or /command").fill("hello there");
  await chat.getByRole("button", { name: "Send" }).click();
  await expect(chat.getByText("hello there")).toBeVisible();
  await expect(chat.getByPlaceholder("Message or /command")).toHaveValue("");

  await page.waitForTimeout(200);
  let log = (await drainServerLog(page, tag)).filter((m) => m.type !== "ACK");
  const types = log.map((m) => m.type);
  expect(types.slice(0, 2)).toEqual(["CLIENT_STATUS", "SUBSCRIBE_CHAT"]);
  expect(log[0]).toMatchObject({ mode: "CHAT" });
  expect(log.some((m) => m.type === "SEND_CHAT" && m.message === "hello there")).toBe(true);

  await chat.getByRole("button", { name: "Back to game" }).click();
  await expect(chat).toHaveCount(0);
  await page.waitForTimeout(200);
  log = (await drainServerLog(page, tag)).filter((m) => m.type !== "ACK");
  expect(log.map((m) => m.type)).toEqual(["UNSUBSCRIBE_CHAT", "CLIENT_STATUS"]);
  expect(log[1]).toMatchObject({ mode: "STREAMING", width: expect.any(Number) });
});

test("settings apply sends CLIENT_STATUS without reconnecting", async ({ page }) => {
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await drainServerLog(page, tag);
  await page.getByRole("button", { name: "Settings" }).click();
  const panel = page.getByTestId("settings-panel");
  await panel.getByLabel(/Frame rate/).fill("15");
  await panel.getByLabel("Color mode").selectOption("2");
  await panel.getByRole("button", { name: "Apply" }).click();
  await expect(panel).toHaveCount(0);
  await page.waitForTimeout(200);
  const log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "CLIENT_STATUS")).toEqual([
    expect.objectContaining({ fps: 15, colorMode: 2, mode: "STREAMING" }),
  ]);
  expect(log.some((m) => m.type === "AUTH")).toBe(false);
  await expect(page.locator(".stream")).toBeVisible();
});

test("the picker appears at the menu and joins a server", async ({ page }) => {
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await replayControl(page, "/replay world menu");
  const picker = page.getByTestId("picker-panel");
  await expect(picker).toBeVisible();
  const entry = picker.getByRole("button", { name: /^Replay / });
  await expect(entry).toBeVisible();
  await drainServerLog(page, tag);
  await entry.click();
  await expect(picker).toHaveCount(0);
  const log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "JOIN_SERVER")).toEqual([
    {
      type: "JOIN_SERVER",
      address: "replay.example:25565",
      name: "Replay",
      acceptResourcePack: true,
    },
  ]);
});
