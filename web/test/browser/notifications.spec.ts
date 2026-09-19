import { expect, test } from "@playwright/test";

test.describe("service worker notifications", () => {
  test.skip(
    ({ browserName }) => browserName !== "chromium",
    "requires Chromium notification support",
  );
  test("serves, activates, and preserves the worker", async ({ page }) => {
    await page.goto("./");
    const secureUrl = new URL(page.url());
    secureUrl.hostname = "localhost";
    await page.goto(secureUrl.href);
    const urls = await page.evaluate(() => ({
      worker: new URL("notification-worker.js", document.baseURI).href,
      icon: new URL("icons/Icon-192.png", document.baseURI).href,
    }));
    const resources = await page.evaluate(async ({ worker, icon }) => {
      const [workerResponse, iconResponse] = await Promise.all([fetch(worker), fetch(icon)]);
      return {
        workerStatus: workerResponse.status,
        workerType: workerResponse.headers.get("content-type"),
        iconStatus: iconResponse.status,
        iconType: iconResponse.headers.get("content-type"),
      };
    }, urls);

    expect(resources.workerStatus).toBe(200);
    expect(resources.workerType).toContain("javascript");
    expect(resources.iconStatus).toBe(200);
    expect(resources.iconType).toContain("image/png");

    await page.evaluate(async ({ worker }) => {
      const registration = await navigator.serviceWorker.register(worker);
      await new Promise<void>((resolve, reject) => {
        if (registration.active?.state === "activated") {
          resolve();
          return;
        }
        const timeout = window.setTimeout(
          () => reject(new Error("worker activation timed out")),
          5_000,
        );
        let installing: ServiceWorker | null = null;
        const inspect = () => {
          const next = registration.installing ?? registration.waiting ?? registration.active;
          if (next !== installing) {
            installing?.removeEventListener("statechange", inspect);
            installing = next;
            installing?.addEventListener("statechange", inspect);
          }
          if (registration.active?.state !== "activated") return;
          window.clearTimeout(timeout);
          registration.removeEventListener("updatefound", inspect);
          installing?.removeEventListener("statechange", inspect);
          resolve();
        };
        registration.addEventListener("updatefound", inspect);
        inspect();
      });
      return registration.scope;
    }, urls);

    await page.reload();
    await expect
      .poll(() =>
        page.evaluate(async (worker) => {
          const registration = await navigator.serviceWorker.getRegistration(worker);
          return {
            scriptURL: registration?.active?.scriptURL,
            state: registration?.active?.state,
          };
        }, urls.worker),
      )
      .toEqual({ scriptURL: urls.worker, state: "activated" });
  });

  test("shows a silent notification when Chromium grants the current origin", async ({
    page,
    context,
  }) => {
    await page.goto("./");
    const secureUrl = new URL(page.url());
    secureUrl.hostname = "localhost";
    await page.goto(secureUrl.href);
    await context.grantPermissions(["notifications"], {
      origin: new URL(page.url()).origin,
    });
    const permission = await page.evaluate(() => Notification.permission);
    test.skip(permission !== "granted", "this Chromium mode cannot grant notification permission");
    const shown = await page.evaluate(async () => {
      const worker = new URL("notification-worker.js", document.baseURI).href;
      const icon = new URL("icons/Icon-192.png", document.baseURI).href;
      const registration = await navigator.serviceWorker.register(worker);
      await new Promise((resolve) => window.setTimeout(resolve, 100));
      const tag = `monkeycraft-sw-${Date.now()}`;
      await registration.showNotification("MonkeyCraft browser test", { icon, silent: true, tag });
      const notification = (await registration.getNotifications({ tag }))[0];
      const result = {
        count: notification ? 1 : 0,
        silent: notification?.silent,
        icon: notification?.icon,
      };
      notification?.close();
      return result;
    });
    expect(shown.count).toBe(1);
    expect(shown.silent).toBe(true);
    expect(shown.icon).toContain("/icons/Icon-192.png");
  });
});
