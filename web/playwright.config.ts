import { defineConfig, devices } from "@playwright/test";

// The app is served by `vite preview`; a replay server plays a recorded
// fixture over ws://127.0.0.1:9601 so tests can run without Minecraft.
export const REPLAY_URL = "ws://127.0.0.1:9601";
export const REPLAY_HTTP = "http://127.0.0.1:9601";
export const REPLAY_PASSWORD = "test";

export default defineConfig({
  testDir: "test/browser",
  fullyParallel: true,
  retries: process.env.CI ? 1 : 0,
  reporter: process.env.CI ? "github" : "list",
  use: {
    baseURL: "http://127.0.0.1:4173",
    trace: "retain-on-failure",
  },
  webServer: [
    {
      command: "pnpm exec vite preview --host 127.0.0.1 --port 4173 --strictPort",
      url: "http://127.0.0.1:4173",
      reuseExistingServer: !process.env.CI,
    },
    {
      command:
        "node tools/replay-server.ts --port 9601 --fixture streaming-360x640 --password test",
      url: "http://127.0.0.1:9601/health",
      reuseExistingServer: !process.env.CI,
    },
  ],
  projects: [{ name: "chromium", use: { ...devices["Desktop Chrome"] } }],
});
