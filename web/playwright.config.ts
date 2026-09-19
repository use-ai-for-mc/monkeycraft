import { defineConfig, devices } from "@playwright/test";

// The app is served by `vite preview`; a replay server plays a recorded
// fixture over ws://127.0.0.1:9601 so tests can run without Minecraft.
export const REPLAY_URL = "ws://127.0.0.1:9601";
export const REPLAY_HTTP = "http://127.0.0.1:9601";
export const REPLAY_PASSWORD = "test";
const browser = process.env.PLAYWRIGHT_BROWSER === "webkit" ? "webkit" : "chromium";
const pagesBuild = process.env.MONKEYCRAFT_PAGES === "1";
const baseURL = process.env.PLAYWRIGHT_BASE_URL ?? "http://127.0.0.1:4173";

export default defineConfig({
  testDir: "test/browser",
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL,
    trace: "retain-on-failure",
  },
  webServer: [
    {
      command: `${pagesBuild ? "MONKEYCRAFT_PAGES=1 " : ""}node node_modules/vite/bin/vite.js preview --host 127.0.0.1 --port 4173 --strictPort`,
      url: baseURL,
      reuseExistingServer: !process.env.CI,
    },
    {
      command:
        "node tools/replay-server.ts --port 9601 --fixture streaming-360x640 --password test",
      url: "http://127.0.0.1:9601/health",
      reuseExistingServer: !process.env.CI,
    },
  ],
  projects: [
    browser === "webkit"
      ? { name: "webkit", use: { ...devices["Desktop Safari"] } }
      : { name: "chromium", use: { ...devices["Desktop Chrome"] } },
  ],
});
