import { expect, test } from "@playwright/test";

test("changing target replaces the prefilled password with that target's credential", async ({
  page,
}) => {
  await page.addInitScript(() => {
    localStorage.setItem("monkeycraft.server", "https://first.tailnet.ts.net");
    localStorage.setItem(
      "monkeycraft.vault",
      JSON.stringify({
        "wss://first.tailnet.ts.net/\u0000k": {
          password: "first-password",
          lastServer: "https://first.tailnet.ts.net",
          lastSeen: 1,
        },
        "wss://second.tailnet.ts.net/\u0000k": {
          password: "second-password",
          lastServer: "https://second.tailnet.ts.net",
          lastSeen: 2,
        },
      }),
    );
  });
  await page.goto("./");
  await expect(page.getByRole("textbox", { name: "Password" })).toHaveValue("first-password");
  await page.getByLabel("Server address").fill("https://second.tailnet.ts.net");
  await expect(page.getByRole("textbox", { name: "Password" })).toHaveValue("second-password");
  await page.getByLabel("Server address").fill("https://third.tailnet.ts.net");
  await expect(page.getByRole("textbox", { name: "Password" })).toHaveValue("");
});
