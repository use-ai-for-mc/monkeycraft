import preact from "@preact/preset-vite";
import { defineConfig } from "vitest/config";

// The mod ignores the WebSocket request path, so in development the app dials
// `${origin}/ws` and Vite forwards the upgrade to the running mod. Override the
// target with MONKEYCRAFT_DEV_WS=ws://host:port when the mod is elsewhere.
const devWsTarget = process.env.MONKEYCRAFT_DEV_WS ?? "ws://127.0.0.1:9600";

export default defineConfig({
  plugins: [preact()],
  base: "/",
  build: {
    outDir: "dist",
    emptyOutDir: true,
    sourcemap: true,
    target: "es2022",
  },
  server: {
    port: 5173,
    strictPort: true,
    proxy: {
      "/ws": { target: devWsTarget, ws: true, changeOrigin: true },
    },
  },
  test: {
    include: ["test/unit/**/*.test.ts"],
    environment: "node",
    coverage: {
      provider: "v8",
      include: [
        "src/protocol/**",
        "src/transport/**",
        "src/session/**",
        "src/video/queue-policy.ts",
      ],
    },
  },
});
