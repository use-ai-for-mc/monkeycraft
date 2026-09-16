import { expect, test } from "@playwright/test";

test("app shell renders and reports its origin", async ({ page }) => {
  await page.goto("/");
  await expect(page.getByRole("heading", { name: "MonkeyCraft" })).toBeVisible();
  await expect(page.getByText("http://127.0.0.1:4173")).toBeVisible();
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
