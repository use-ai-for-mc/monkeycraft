import { expect, test } from "@playwright/test";

test("login page renders with the page origin as the default server", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "MonkeyCraft" })).toBeVisible();
  await expect(page.getByLabel("Server address")).toHaveValue("http://127.0.0.1:4173");
  // 127.0.0.1 is pairing-eligible and nothing is saved, so the default mode is pair.
  await expect(page.getByRole("button", { name: "Pair" })).toBeVisible();
  await page.getByRole("button", { name: "Use password instead" }).click();
  await expect(page.getByRole("textbox", { name: "Password" })).toBeVisible();
});

test("WebCodecs H.264 baseline is decodable in this browser", async ({ page }) => {
  await page.goto("/");
  const supported = await page.evaluate(async () => {
    if (!("VideoDecoder" in window)) return "no-webcodecs";
    const r = await VideoDecoder.isConfigSupported({
      codec: "avc1.420028",
      optimizeForLatency: true,
      hardwareAcceleration: "no-preference",
    });
    return r.supported ? "ok" : "unsupported";
  });
  expect(supported).toBe("ok");
});
