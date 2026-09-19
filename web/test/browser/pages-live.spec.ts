import { expect, test } from "@playwright/test";

test.use({ trace: "off" });

const enabled = process.env.MONKEYCRAFT_PAGES_LIVE === "1";
const liveUrl = process.env.MONKEYCRAFT_LIVE_URL ?? "";
const password = process.env.MONKEYCRAFT_PASSWORD ?? "";
const invalidPassword = "__monkeycraft_pages_invalid_password__";

test.skip(
  !enabled || liveUrl === "" || password === "",
  "set MONKEYCRAFT_PAGES_LIVE=1, MONKEYCRAFT_LIVE_URL, and MONKEYCRAFT_PASSWORD",
);
test.describe.configure({ mode: "serial" });

test("Pages uses a separate secure game origin and restores a saved credential", async ({
  page,
}) => {
  test.setTimeout(90_000);
  await page.goto("./?debug=1");

  const pageOrigin = new URL(page.url()).origin;
  expect(await page.evaluate(() => isSecureContext)).toBe(true);
  const gameUrl = new URL(liveUrl);
  if (gameUrl.protocol === "https:") gameUrl.protocol = "wss:";
  if (gameUrl.protocol === "http:") gameUrl.protocol = "ws:";
  expect(gameUrl.protocol).toBe("wss:");
  gameUrl.protocol = "https:";
  expect(pageOrigin).not.toBe(gameUrl.origin);

  await page.getByLabel("Server address").fill(liveUrl);
  const usePassword = page.getByRole("button", { name: "Use password instead" });
  if (await usePassword.isVisible()) await usePassword.click();
  const passwordField = page.getByRole("textbox", { name: "Password" });
  await passwordField.fill(invalidPassword);
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.locator(".error")).toContainText(
    "Saved password did not match this computer.",
    { timeout: 20_000 },
  );

  await passwordField.fill(password);
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.locator(".stream")).toBeVisible({ timeout: 20_000 });

  const debug = page.locator(".debug");
  const decodedFrames = async () => {
    const text = (await debug.textContent()) ?? "";
    return Number(/dec (\d+)/.exec(text)?.[1] ?? 0);
  };
  await expect
    .poll(decodedFrames, { timeout: 30_000, message: "decoded frames" })
    .toBeGreaterThan(5);
  const decodedBeforeDisconnect = await decodedFrames();
  await expect
    .poll(decodedFrames, { timeout: 20_000, message: "decoded frames continue" })
    .toBeGreaterThan(decodedBeforeDisconnect);
  await expect(debug).toContainText("err 0");

  await page.getByTitle("Disconnect").click();
  await expect(page.getByLabel("Server address")).toHaveValue(liveUrl);
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.locator(".stream")).toBeVisible({ timeout: 20_000 });
  await expect
    .poll(decodedFrames, { timeout: 30_000, message: "restored decoded frames" })
    .toBeGreaterThan(5);
  await expect(debug).toContainText("err 0");
  await page.getByTitle("Disconnect").click();
});
