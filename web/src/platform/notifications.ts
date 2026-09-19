let registration: Promise<ServiceWorkerRegistration | null> | null = null;

export function notificationsSupported(): boolean {
  return typeof Notification !== "undefined";
}

export async function ensureNotificationPermission(): Promise<boolean> {
  if (!notificationsSupported()) return false;
  const permission = requestPermission();
  void notificationRegistration();
  return permission;
}

export async function notifyIfHidden(
  title: string,
  body: string | null,
  silent = false,
): Promise<boolean> {
  if (!notificationsSupported() || Notification.permission !== "granted") return false;
  if (typeof document !== "undefined" && !document.hidden) return false;
  const options: NotificationOptions = {
    tag: "monkeycraft",
    icon: new URL("icons/Icon-192.png", appBaseUrl()).href,
  };
  if (body) options.body = body;
  if (silent) options.silent = true;
  const worker = await notificationRegistration();
  if (worker) {
    try {
      await worker.showNotification(title, options);
      return true;
    } catch {
      return false;
    }
  }
  try {
    const notification = new Notification(title, options);
    notification.onclick = () => {
      window.focus();
      notification.close();
    };
    return true;
  } catch {
    return false;
  }
}

function requestPermission(): Promise<boolean> {
  if (Notification.permission === "granted") return Promise.resolve(true);
  if (Notification.permission === "denied") return Promise.resolve(false);
  try {
    return Notification.requestPermission()
      .then((permission) => permission === "granted")
      .catch(() => false);
  } catch {
    return Promise.resolve(false);
  }
}

function notificationRegistration(): Promise<ServiceWorkerRegistration | null> {
  if (!isSecureContext || !("serviceWorker" in navigator)) return Promise.resolve(null);
  if (registration) return registration;
  const attempt = withTimeout(
    navigator.serviceWorker.register(new URL("notification-worker.js", appBaseUrl())),
    3_000,
  )
    .then((value) => (value ? waitForActivation(value, 3_000) : null))
    .catch(() => null);
  registration = attempt.then((value) => {
    if (!value) registration = null;
    return value;
  });
  return registration;
}

function waitForActivation(
  workerRegistration: ServiceWorkerRegistration,
  timeoutMs: number,
): Promise<ServiceWorkerRegistration | null> {
  if (workerRegistration.active) return Promise.resolve(workerRegistration);
  return new Promise((resolve) => {
    let worker: ServiceWorker | null = null;
    const done = (value: ServiceWorkerRegistration | null) => {
      clearTimeout(timer);
      workerRegistration.removeEventListener("updatefound", inspect);
      worker?.removeEventListener("statechange", inspect);
      resolve(value);
    };
    const inspect = () => {
      const next = workerRegistration.installing ?? workerRegistration.waiting;
      if (next !== worker) {
        worker?.removeEventListener("statechange", inspect);
        worker = next;
        worker?.addEventListener("statechange", inspect);
      }
      if (workerRegistration.active) done(workerRegistration);
    };
    const timer = setTimeout(() => done(null), timeoutMs);
    workerRegistration.addEventListener("updatefound", inspect);
    inspect();
  });
}

function withTimeout<T>(value: Promise<T>, timeoutMs: number): Promise<T | null> {
  return new Promise((resolve) => {
    const timer = setTimeout(() => resolve(null), timeoutMs);
    void value.then(
      (result) => {
        clearTimeout(timer);
        resolve(result);
      },
      () => {
        clearTimeout(timer);
        resolve(null);
      },
    );
  });
}

function appBaseUrl(): URL {
  return new URL(import.meta.env.BASE_URL, window.location.origin);
}
