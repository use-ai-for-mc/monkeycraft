// The mod accepts one session; a second tab would kick the first. Hold a Web
// Lock for the lifetime of the page so other tabs can tell.

const LOCK_NAME = "monkeycraft-session";

export type TabLockResult = "acquired" | "busy" | "unsupported";

let release: (() => void) | null = null;

export async function acquireTabLock(): Promise<TabLockResult> {
  if (typeof navigator === "undefined" || !("locks" in navigator)) return "unsupported";
  return new Promise<TabLockResult>((resolve) => {
    void navigator.locks.request(LOCK_NAME, { ifAvailable: true }, (lock) => {
      if (!lock) {
        resolve("busy");
        return Promise.resolve();
      }
      resolve("acquired");
      return new Promise<void>((done) => {
        release = done;
      });
    });
  });
}

export function releaseTabLock(): void {
  release?.();
  release = null;
}
