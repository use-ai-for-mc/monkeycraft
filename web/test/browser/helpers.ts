import { expect, type Page } from "@playwright/test";
import { REPLAY_HTTP, REPLAY_PASSWORD, REPLAY_URL } from "../../playwright.config.ts";

/** Log in against the replay server with the debug overlay on. */
export async function loginToReplay(page: Page): Promise<void> {
  await page.goto("/?debug=1");
  await page.getByLabel("Server address").fill(REPLAY_URL);
  const usePassword = page.getByRole("button", { name: "Use password instead" });
  if (await usePassword.isVisible()) await usePassword.click();
  await page.getByRole("textbox", { name: "Password" }).fill(REPLAY_PASSWORD);
  await page.getByRole("button", { name: "Connect" }).click();
  await expect(page.locator(".stream")).toBeVisible({ timeout: 15_000 });
}

export interface DebugStats {
  fps: number;
  recv: number;
  dec: number;
  drop: number;
  err: number;
  cfg: number;
  kf: number;
  link: string;
}

export async function readDebug(page: Page): Promise<DebugStats> {
  const text = (await page.locator(".debug").textContent()) ?? "";
  const num = (key: string) => {
    const m = new RegExp(`${key} (\\d+)`).exec(text);
    return m ? Number(m[1]) : 0;
  };
  const link = /link (\w+)/.exec(text)?.[1] ?? "";
  return {
    fps: num("fps"),
    recv: num("recv"),
    dec: num("dec"),
    drop: num("drop"),
    err: num("err"),
    cfg: num("cfg"),
    kf: num("kf"),
    link,
  };
}

export async function waitForDecoded(page: Page, atLeast: number, timeout = 20_000): Promise<void> {
  await expect
    .poll(async () => (await readDebug(page)).dec, { timeout, message: "decoded frames" })
    .toBeGreaterThanOrEqual(atLeast);
}

/** Messages the replay server received since the previous call. */
export async function drainServerLog(page: Page): Promise<Record<string, unknown>[]> {
  const entries = (await page.evaluate(async (url) => {
    const r = await fetch(`${url}/log`);
    return (await r.json()) as Array<{ msg: Record<string, unknown> }>;
  }, REPLAY_HTTP)) as Array<{ msg: Record<string, unknown> }>;
  return entries.map((e) => e.msg);
}

/** Send a test control through the app's own socket (RUN_COMMAND). */
export async function replayControl(page: Page, command: string): Promise<void> {
  await page.evaluate((cmd) => {
    const hook = (globalThis as unknown as { __monkeycraft?: { send?: (m: unknown) => boolean } })
      .__monkeycraft;
    hook?.send?.({ type: "RUN_COMMAND", command: cmd });
  }, command);
}
