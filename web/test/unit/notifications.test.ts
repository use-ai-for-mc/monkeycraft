import { readFile } from "node:fs/promises";
import { afterEach, describe, expect, it, vi } from "vitest";

let constructed = 0;

afterEach(() => {
  vi.useRealTimers();
  vi.unstubAllGlobals();
  vi.unstubAllEnvs();
  vi.resetModules();
  vi.clearAllMocks();
  constructed = 0;
});

function activeRegistration(): ServiceWorkerRegistration {
  return {
    active: {} as ServiceWorker,
    showNotification: vi.fn(async () => {}),
  } as unknown as ServiceWorkerRegistration;
}

function inactiveRegistration(): ServiceWorkerRegistration {
  return {
    active: null,
    installing: null,
    waiting: null,
    addEventListener: vi.fn(),
    removeEventListener: vi.fn(),
  } as unknown as ServiceWorkerRegistration;
}

function installGlobals(
  options: {
    constructorThrows?: boolean;
    register?: () => Promise<ServiceWorkerRegistration>;
    ready?: Promise<ServiceWorkerRegistration>;
  } = {},
): void {
  class TestNotification {
    static permission: NotificationPermission = "granted";
    static requestPermission = vi.fn(async () => "granted" as NotificationPermission);
    onclick: (() => void) | null = null;
    close = vi.fn();
    constructor(_title: string, _options: NotificationOptions) {
      constructed += 1;
      if (options.constructorThrows) throw new TypeError("mobile");
    }
  }
  vi.stubGlobal("Notification", TestNotification);
  vi.stubGlobal("document", { hidden: true });
  vi.stubGlobal("window", { location: { origin: "https://example.test" }, focus: vi.fn() });
  vi.stubGlobal("isSecureContext", true);
  vi.stubGlobal("navigator", {
    serviceWorker: {
      register: vi.fn(options.register ?? (async () => activeRegistration())),
      ready: options.ready ?? Promise.resolve(activeRegistration()),
    },
  });
}

describe("notifications", () => {
  it("uses this registration rather than an unrelated ready worker", async () => {
    const registration = activeRegistration();
    const unrelated = activeRegistration();
    installGlobals({
      constructorThrows: true,
      register: async () => registration,
      ready: Promise.resolve(unrelated),
    });
    const { notifyIfHidden } = await import("../../src/platform/notifications.ts");

    await expect(notifyIfHidden("Ride", "Ready", false)).resolves.toBe(true);

    expect(registration.showNotification).toHaveBeenCalledWith(
      "Ride",
      expect.objectContaining({ tag: "monkeycraft", body: "Ready" }),
    );
    expect(unrelated.showNotification).not.toHaveBeenCalled();
  });

  it("uses a Pages-safe icon URL and preserves silent notifications", async () => {
    vi.stubEnv("BASE_URL", "/monkeycraft/");
    const registration = activeRegistration();
    installGlobals({ register: async () => registration });
    const { notifyIfHidden } = await import("../../src/platform/notifications.ts");

    await expect(notifyIfHidden("Ride", "Ready", true)).resolves.toBe(true);

    expect(registration.showNotification).toHaveBeenCalledWith(
      "Ride",
      expect.objectContaining({
        silent: true,
        icon: "https://example.test/monkeycraft/icons/Icon-192.png",
      }),
    );
  });

  it("falls back after a hung registration and retries after activation timeout", async () => {
    vi.useFakeTimers();
    const first = inactiveRegistration();
    const second = activeRegistration();
    let attempts = 0;
    installGlobals({
      register: async () => {
        attempts += 1;
        return attempts === 1 ? first : second;
      },
    });
    const { notifyIfHidden } = await import("../../src/platform/notifications.ts");

    const firstResult = notifyIfHidden("Ride", "Ready", false);
    await vi.advanceTimersByTimeAsync(3_000);
    await expect(firstResult).resolves.toBe(true);
    await expect(notifyIfHidden("Ride", "Ready", false)).resolves.toBe(true);

    expect(attempts).toBe(2);
    expect(constructed).toBe(1);
    expect(second.showNotification).toHaveBeenCalledTimes(1);
  });

  it("falls back when registration itself does not settle", async () => {
    vi.useFakeTimers();
    installGlobals({ register: () => new Promise<ServiceWorkerRegistration>(() => {}) });
    const { notifyIfHidden } = await import("../../src/platform/notifications.ts");

    const result = notifyIfHidden("Ride", "Ready", false);
    await vi.advanceTimersByTimeAsync(3_000);

    await expect(result).resolves.toBe(true);
    expect(constructed).toBe(1);
  });

  it("reports a rejected service worker notification without using the constructor", async () => {
    const registration = activeRegistration();
    vi.mocked(registration.showNotification).mockRejectedValueOnce(new Error("rejected"));
    installGlobals({ constructorThrows: true, register: async () => registration });
    const { notifyIfHidden } = await import("../../src/platform/notifications.ts");

    await expect(notifyIfHidden("Ride", "Ready", false)).resolves.toBe(false);

    expect(constructed).toBe(0);
  });

  it("keeps cleanup scoped to the known Flutter worker", async () => {
    const html = await readFile(new URL("../../index.html", import.meta.url), "utf8");

    expect(html).toContain("%BASE_URL%flutter_service_worker.js");
    expect(html).not.toContain("caches.delete");
  });
});
