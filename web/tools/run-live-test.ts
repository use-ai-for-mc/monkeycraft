import { spawn } from "node:child_process";
import { readFile } from "node:fs/promises";
import { createServer } from "node:net";
import { fileURLToPath } from "node:url";

const webRoot = fileURLToPath(new URL("..", import.meta.url));
const configPath =
  process.env.MONKEYCRAFT_CONFIG ??
  "/Users/cusgadmin/Library/Application Support/PrismLauncher/instances/ImagineFun Add-Ons/minecraft/config/monkeycraft.json";
const config = JSON.parse(await readFile(configPath, "utf8")) as { password?: unknown };
if (typeof config.password !== "string" || config.password.length === 0) {
  throw new Error("MonkeyCraft password is unavailable in the local Prism configuration.");
}

const port = 5173;
const liveUrl = process.env.MONKEYCRAFT_LIVE_URL ?? `http://127.0.0.1:${port}/ws`;
const pageUrl = liveUrl.startsWith("https://") ? liveUrl : `http://127.0.0.1:${port}`;
const portAvailable = await isPortAvailable(port);
if (!portAvailable && process.env.MONKEYCRAFT_REUSE_DEV !== "1") {
  throw new Error(
    `Port ${port} is already in use. Set MONKEYCRAFT_REUSE_DEV=1 to reuse its Vite server.`,
  );
}
const vite = portAvailable
  ? spawn(process.execPath, ["node_modules/vite/bin/vite.js", "--host", "127.0.0.1"], {
      cwd: webRoot,
      env: {
        ...process.env,
        MONKEYCRAFT_DEV_WS: process.env.MONKEYCRAFT_DEV_WS ?? "ws://127.0.0.1:9600",
      },
      stdio: "ignore",
    })
  : null;

try {
  await waitForHttp(`http://127.0.0.1:${port}`, 20_000);
  const test = spawn(
    process.execPath,
    ["node_modules/@playwright/test/cli.js", "test", "test/browser/live.spec.ts"],
    {
      cwd: webRoot,
      env: {
        ...process.env,
        MONKEYCRAFT_DEV_URL: `http://127.0.0.1:${port}`,
        MONKEYCRAFT_LIVE_URL: liveUrl,
        MONKEYCRAFT_PAGE_URL: pageUrl,
        MONKEYCRAFT_LIVE: "1",
        MONKEYCRAFT_PASSWORD: config.password,
      },
      stdio: "inherit",
    },
  );
  await new Promise<void>((resolve, reject) => {
    test.once("exit", (code) =>
      code === 0 ? resolve() : reject(new Error(`live test exited ${code}`)),
    );
    test.once("error", reject);
  });
} finally {
  vite?.kill();
}

async function isPortAvailable(port: number): Promise<boolean> {
  return new Promise<boolean>((resolve) => {
    const socket = createServer();
    socket.once("error", () => resolve(false));
    socket.once("listening", () => socket.close(() => resolve(true)));
    socket.listen(port, "127.0.0.1");
  });
}

async function waitForHttp(url: string, timeoutMs: number): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (Date.now() < deadline) {
    try {
      if ((await fetch(url)).ok) return;
    } catch {}
    await new Promise((resolve) => setTimeout(resolve, 200));
  }
  throw new Error("Vite did not start within 20 seconds.");
}
