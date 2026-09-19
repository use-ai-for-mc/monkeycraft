import { expect, test } from "@playwright/test";

test.skip(process.env.MONKEYCRAFT_PAGES !== "1", "runs against the Pages bundle");

test("Pages bundle uses its configured path and asks for a server", async ({ page }) => {
  await page.goto("./");
  expect(new URL(page.url()).pathname).toBe(process.env.MONKEYCRAFT_PAGES_BASE ?? "/monkeycraft/");
  await expect(page.getByLabel("Server address")).toHaveValue("");
});

test("Pages bundle exposes verifiable build provenance", async ({ page }) => {
  await page.goto("./");
  const response = await page.request.get("build-provenance.json");
  expect(response.ok()).toBeTruthy();
  const provenance = await response.json();
  expect(provenance.schemaVersion).toBe(1);
  if (provenance.source.dirty) {
    expect(provenance.source.commit).toBeNull();
  } else {
    expect(provenance.source.commit).toMatch(/^[0-9a-f]{40}$/);
  }
  expect(provenance.workflow.sha256).toMatch(/^[0-9a-f]{64}$/);
  expect(Object.values(provenance.workflow.actions)).toHaveLength(6);
  for (const pin of Object.values(provenance.workflow.actions)) {
    expect(pin).toMatch(/^[0-9a-f]{40}$/);
  }
  expect(provenance.artifactFiles).toEqual(
    expect.arrayContaining([
      expect.objectContaining({
        path: "index.html",
        sha256: expect.stringMatching(/^[0-9a-f]{64}$/),
      }),
    ]),
  );
});
