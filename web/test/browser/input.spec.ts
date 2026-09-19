// Input layer against the replay server. Includes the regression for the
// Flutter-web ESC palette bug: the palette must follow SCREEN_STATE only.

import { expect, test } from "@playwright/test";
import { drainServerLog, loginToReplay, replayControl, waitForDecoded } from "./helpers.ts";

async function settle(page: import("@playwright/test").Page, ms = 300) {
  await page.waitForTimeout(ms);
}

test("keyboard maps to INPUT edges, hotbar digits, and releases on blur", async ({ page }) => {
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await drainServerLog(page, tag);

  await page.keyboard.down("KeyW");
  await page.keyboard.down("ShiftLeft");
  await page.keyboard.press("Digit3");
  await page.keyboard.up("KeyW");
  await settle(page);
  let log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "INPUT")).toEqual([
    { type: "INPUT", key: "W", pressed: true },
    { type: "INPUT", key: "SHIFT", pressed: true },
    { type: "INPUT", key: "W", pressed: false },
  ]);
  expect(log.filter((m) => m.type === "HOTBAR_SELECT")).toEqual([
    { type: "HOTBAR_SELECT", slot: 2 },
  ]);

  await page.evaluate(() => window.dispatchEvent(new Event("blur")));
  await settle(page);
  log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "INPUT")).toEqual([
    { type: "INPUT", key: "SHIFT", pressed: false },
  ]);
});

test("ESC palette follows SCREEN_STATE regardless of the last pointer device", async ({ page }) => {
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  const palette = page.getByTestId("screen-palette");
  await expect(palette).toHaveCount(0);

  // A mouse click first (this hid the palette in the Flutter client).
  await page.mouse.click(400, 300);
  await replayControl(page, "/replay screen open");
  await expect(palette).toBeVisible();
  await expect(page.locator(".pad-left")).toHaveCount(0);

  // ESC through the palette sends key down and key up.
  await drainServerLog(page, tag);
  await palette.getByRole("button", { name: "Screen controls" }).click();
  await palette.getByRole("button", { name: "ESC" }).click();
  await settle(page);
  const log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "SCREEN_KEY")).toEqual([
    { type: "SCREEN_KEY", key: "ESCAPE", pressed: true },
    { type: "SCREEN_KEY", key: "ESCAPE", pressed: false },
  ]);

  await replayControl(page, "/replay screen close");
  await expect(palette).toHaveCount(0);
});

test("physical Escape and clicks are routed to the GUI while a screen is open", async ({
  page,
}) => {
  await page.setViewportSize({ width: 800, height: 600 });
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await replayControl(page, "/replay screen open");
  await expect(page.getByTestId("screen-palette")).toBeVisible();
  await expect.poll(() => page.evaluate(() => document.pointerLockElement === null)).toBe(true);
  await drainServerLog(page, tag);

  // The 360x640 picture is pillarboxed in 800x600: it spans x in [231, 569].
  await page.mouse.move(400, 300);
  await page.mouse.click(400, 300);
  await page.mouse.click(400, 300, { button: "right" });
  await page.keyboard.press("Escape");
  await settle(page);
  const log = await drainServerLog(page, tag);
  const clicks = log.filter((m) => m.type === "SCREEN_CLICK");
  expect(clicks).toHaveLength(2);
  expect(clicks[0]).toMatchObject({ button: 0 });
  expect(clicks[1]).toMatchObject({ button: 1 });
  for (const c of clicks) {
    expect(c.normalizedX as number).toBeGreaterThan(0.4);
    expect(c.normalizedX as number).toBeLessThan(0.6);
    expect(c.normalizedY as number).toBeGreaterThan(0.4);
    expect(c.normalizedY as number).toBeLessThan(0.6);
  }
  expect(log.some((m) => m.type === "SCREEN_HOVER")).toBe(true);
  expect(log.filter((m) => m.type === "SCREEN_KEY")).toEqual([
    { type: "SCREEN_KEY", key: "ESCAPE", pressed: true },
    { type: "SCREEN_KEY", key: "ESCAPE", pressed: false },
  ]);
  expect(log.some((m) => m.type === "CLICK")).toBe(false);
});

test("pointer lock failures fall back to drag look without page errors", async ({ page }) => {
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  const pageErrors: string[] = [];
  const onPageError = (error: Error) => pageErrors.push(`${error.name}: ${error.message}`);
  page.on("pageerror", onPageError);
  const host = page.locator(".video-host");
  await host.evaluate((element) => {
    const state = globalThis as typeof globalThis & { __pointerLockCalls?: number };
    state.__pointerLockCalls = 0;
    Object.defineProperty(element, "requestPointerLock", {
      configurable: true,
      value: () => {
        state.__pointerLockCalls = (state.__pointerLockCalls ?? 0) + 1;
        if (state.__pointerLockCalls === 1) {
          throw new DOMException("sync pointer lock failure", "InvalidStateError");
        }
        if (state.__pointerLockCalls === 2) {
          return Promise.reject(new DOMException("async pointer lock failure", "NotAllowedError"));
        }
      },
    });
  });
  const box = await host.boundingBox();
  if (!box) throw new Error("expected video host");
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;

  await page.mouse.click(x, y);
  await page.mouse.click(x, y);
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockCalls?: number }).__pointerLockCalls ??
          0,
      ),
    )
    .toBe(2);
  await page.mouse.click(x, y);
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockCalls?: number }).__pointerLockCalls ??
          0,
      ),
    )
    .toBe(3);
  await page.evaluate(() => document.dispatchEvent(new Event("pointerlockerror")));
  await page.mouse.click(x, y);
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockCalls?: number }).__pointerLockCalls ??
          0,
      ),
    )
    .toBe(4);
  await page.evaluate(() => document.dispatchEvent(new Event("pointerlockerror")));
  await settle(page);
  await drainServerLog(page, tag);

  await page.mouse.move(x, y);
  await page.mouse.down();
  await page.mouse.move(x + 20, y);
  await page.mouse.move(x + 40, y);
  await page.mouse.up();
  await settle(page);
  const log = await drainServerLog(page, tag);

  expect(log.some((message) => message.type === "LOOK_DELTA")).toBe(true);
  expect(pageErrors).toEqual([]);
  page.off("pageerror", onPageError);
});

test("late promise pointer lock completion releases after screen open and detach", async ({
  page,
}) => {
  await loginToReplay(page);
  await waitForDecoded(page, 3);
  const pageErrors: string[] = [];
  const onPageError = (error: Error) => pageErrors.push(`${error.name}: ${error.message}`);
  page.on("pageerror", onPageError);
  const host = page.locator(".video-host");
  await host.evaluate((element) => {
    type PointerLockState = typeof globalThis & {
      __pointerLockExitCount?: number;
      __pointerLockRequestCount?: number;
      __resolveNextPointerLock?: () => void;
    };
    const state = globalThis as PointerLockState;
    const pending: Array<() => void> = [];
    let lockedElement: Element | null = null;
    state.__pointerLockExitCount = 0;
    state.__pointerLockRequestCount = 0;
    state.__resolveNextPointerLock = () => pending.shift()?.();
    Object.defineProperty(document, "pointerLockElement", {
      configurable: true,
      get: () => lockedElement,
    });
    Object.defineProperty(document, "exitPointerLock", {
      configurable: true,
      value: () => {
        state.__pointerLockExitCount = (state.__pointerLockExitCount ?? 0) + 1;
        lockedElement = null;
        document.dispatchEvent(new Event("pointerlockchange"));
      },
    });
    Object.defineProperty(element, "requestPointerLock", {
      configurable: true,
      value: () => {
        state.__pointerLockRequestCount = (state.__pointerLockRequestCount ?? 0) + 1;
        return new Promise<void>((resolve) => {
          pending.push(() => {
            lockedElement = element;
            document.dispatchEvent(new Event("pointerlockchange"));
            resolve();
          });
        });
      },
    });
  });
  const box = await host.boundingBox();
  if (!box) throw new Error("expected video host");
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;

  await page.mouse.click(x, y);
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockRequestCount?: number })
            .__pointerLockRequestCount ?? 0,
      ),
    )
    .toBe(1);
  await replayControl(page, "/replay screen open");
  await expect(page.getByTestId("screen-palette")).toBeVisible();
  await page.evaluate(() =>
    (
      globalThis as typeof globalThis & { __resolveNextPointerLock?: () => void }
    ).__resolveNextPointerLock?.(),
  );
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockExitCount?: number })
            .__pointerLockExitCount ?? 0,
      ),
    )
    .toBe(1);
  await expect.poll(() => page.evaluate(() => document.pointerLockElement === null)).toBe(true);

  await replayControl(page, "/replay screen close");
  await expect(page.getByTestId("screen-palette")).toHaveCount(0);
  await page.mouse.click(x, y);
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockRequestCount?: number })
            .__pointerLockRequestCount ?? 0,
      ),
    )
    .toBe(2);
  await page.getByTitle("Disconnect").click();
  await expect(page.getByLabel("Server address")).toBeVisible();
  await page.evaluate(() =>
    (
      globalThis as typeof globalThis & { __resolveNextPointerLock?: () => void }
    ).__resolveNextPointerLock?.(),
  );
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockExitCount?: number })
            .__pointerLockExitCount ?? 0,
      ),
    )
    .toBe(2);
  await expect.poll(() => page.evaluate(() => document.pointerLockElement === null)).toBe(true);

  expect(pageErrors).toEqual([]);
  page.off("pageerror", onPageError);
});

test("late void pointer lock completion releases after screen open and detach", async ({
  page,
}) => {
  await loginToReplay(page);
  await waitForDecoded(page, 3);
  const pageErrors: string[] = [];
  const onPageError = (error: Error) => pageErrors.push(`${error.name}: ${error.message}`);
  page.on("pageerror", onPageError);
  const host = page.locator(".video-host");
  await host.evaluate((element) => {
    type PointerLockState = typeof globalThis & {
      __pointerLockExitCount?: number;
      __pointerLockRequestCount?: number;
      __resolveNextPointerLock?: () => void;
    };
    const state = globalThis as PointerLockState;
    const pending: Array<() => void> = [];
    let lockedElement: Element | null = null;
    state.__pointerLockExitCount = 0;
    state.__pointerLockRequestCount = 0;
    state.__resolveNextPointerLock = () => pending.shift()?.();
    Object.defineProperty(document, "pointerLockElement", {
      configurable: true,
      get: () => lockedElement,
    });
    Object.defineProperty(document, "exitPointerLock", {
      configurable: true,
      value: () => {
        state.__pointerLockExitCount = (state.__pointerLockExitCount ?? 0) + 1;
        lockedElement = null;
        document.dispatchEvent(new Event("pointerlockchange"));
      },
    });
    Object.defineProperty(element, "requestPointerLock", {
      configurable: true,
      value: () => {
        state.__pointerLockRequestCount = (state.__pointerLockRequestCount ?? 0) + 1;
        pending.push(() => {
          lockedElement = element;
          document.dispatchEvent(new Event("pointerlockchange"));
        });
      },
    });
  });
  const box = await host.boundingBox();
  if (!box) throw new Error("expected video host");
  const x = box.x + box.width / 2;
  const y = box.y + box.height / 2;

  await page.mouse.click(x, y);
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockRequestCount?: number })
            .__pointerLockRequestCount ?? 0,
      ),
    )
    .toBe(1);
  await replayControl(page, "/replay screen open");
  await expect(page.getByTestId("screen-palette")).toBeVisible();
  await page.evaluate(() =>
    (
      globalThis as typeof globalThis & { __resolveNextPointerLock?: () => void }
    ).__resolveNextPointerLock?.(),
  );
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockExitCount?: number })
            .__pointerLockExitCount ?? 0,
      ),
    )
    .toBe(1);
  await expect.poll(() => page.evaluate(() => document.pointerLockElement === null)).toBe(true);

  await replayControl(page, "/replay screen close");
  await expect(page.getByTestId("screen-palette")).toHaveCount(0);
  await page.mouse.click(x, y);
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockRequestCount?: number })
            .__pointerLockRequestCount ?? 0,
      ),
    )
    .toBe(2);
  await page.getByTitle("Disconnect").click();
  await expect(page.getByLabel("Server address")).toBeVisible();
  await page.evaluate(() =>
    (
      globalThis as typeof globalThis & { __resolveNextPointerLock?: () => void }
    ).__resolveNextPointerLock?.(),
  );
  await expect
    .poll(() =>
      page.evaluate(
        () =>
          (globalThis as typeof globalThis & { __pointerLockExitCount?: number })
            .__pointerLockExitCount ?? 0,
      ),
    )
    .toBe(2);
  await expect.poll(() => page.evaluate(() => document.pointerLockElement === null)).toBe(true);

  expect(pageErrors).toEqual([]);
  page.off("pageerror", onPageError);
});

test("letterbox margins do not send screen clicks", async ({ page }) => {
  await page.setViewportSize({ width: 800, height: 600 });
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await replayControl(page, "/replay screen open");
  await expect(page.getByTestId("screen-palette")).toBeVisible();
  await drainServerLog(page, tag);

  const host = await page.locator(".video-host").boundingBox();
  const canvas = await page.locator(".video-host canvas").boundingBox();
  if (!host || !canvas || canvas.x <= host.x) throw new Error("expected a pillarboxed video");
  await page.mouse.click(host.x + 5, host.y + host.height / 2);
  await page.mouse.click(canvas.x + canvas.width / 2, canvas.y + canvas.height / 2);
  await settle(page);
  const clicks = (await drainServerLog(page, tag)).filter((m) => m.type === "SCREEN_CLICK");
  expect(clicks).toHaveLength(1);
  expect(clicks[0]).toMatchObject({ button: 0, normalizedX: 0.5, normalizedY: 0.5 });
});

test("mouse clicks in world mode are CLICK messages and the wheel changes the slot", async ({
  page,
}) => {
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await drainServerLog(page, tag);
  await page.mouse.click(400, 300);
  await page.mouse.click(400, 300, { button: "right" });
  await page.mouse.wheel(0, 100);
  await settle(page);
  const log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "CLICK")).toEqual([
    { type: "CLICK", button: 0 },
    { type: "CLICK", button: 1 },
  ]);
  expect(log.filter((m) => m.type === "HOTBAR_SELECT")).toEqual([
    { type: "HOTBAR_SELECT", slot: 1 },
  ]);
});

test("touch drag looks, tap clicks, joystick moves", async ({ browser }) => {
  const context = await browser.newContext({
    hasTouch: true,
    viewport: { width: 800, height: 600 },
  });
  const page = await context.newPage();
  const tag = await loginToReplay(page);
  await waitForDecoded(page, 3);
  await drainServerLog(page, tag);

  // Tap = left click.
  await page.touchscreen.tap(400, 300);
  await settle(page);
  let log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "CLICK")).toEqual([{ type: "CLICK", button: 0 }]);
  // The touch made the pads appear.
  await expect(page.locator(".joystick")).toBeVisible();

  // Drag on the joystick presses W.
  const box = await page.locator(".joystick").boundingBox();
  if (!box) throw new Error("no joystick");
  const cx = box.x + box.width / 2;
  const cy = box.y + box.height / 2;
  await page.evaluate(
    ([x, y]) => {
      const el = document.elementFromPoint(x, y) as HTMLElement;
      const down = new PointerEvent("pointerdown", {
        pointerId: 7,
        pointerType: "touch",
        clientX: x,
        clientY: y,
        bubbles: true,
        isPrimary: true,
      });
      el.dispatchEvent(down);
      el.dispatchEvent(
        new PointerEvent("pointermove", {
          pointerId: 7,
          pointerType: "touch",
          clientX: x,
          clientY: y - 60,
          bubbles: true,
        }),
      );
    },
    [cx, cy] as [number, number],
  );
  await settle(page);
  log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "INPUT")).toEqual([
    { type: "INPUT", key: "W", pressed: true },
  ]);
  await page.evaluate(() => window.dispatchEvent(new Event("blur")));
  await settle(page);
  log = await drainServerLog(page, tag);
  expect(log.filter((m) => m.type === "INPUT")).toEqual([
    { type: "INPUT", key: "W", pressed: false },
  ]);
  await context.close();
});
