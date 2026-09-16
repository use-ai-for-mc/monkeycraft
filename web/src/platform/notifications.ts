// Web Notifications for NUDGE / timed alerts while the tab is hidden. In the
// foreground the in-app banner is the surface, like the Flutter client.

export function notificationsSupported(): boolean {
  return typeof Notification !== "undefined";
}

export async function ensureNotificationPermission(): Promise<boolean> {
  if (!notificationsSupported()) return false;
  if (Notification.permission === "granted") return true;
  if (Notification.permission === "denied") return false;
  try {
    return (await Notification.requestPermission()) === "granted";
  } catch {
    return false;
  }
}

export function notifyIfHidden(title: string, body: string | null): void {
  if (!notificationsSupported() || Notification.permission !== "granted") return;
  if (typeof document !== "undefined" && !document.hidden) return;
  try {
    const options: NotificationOptions = { tag: "monkeycraft", icon: "/icons/Icon-192.png" };
    if (body) options.body = body;
    const n = new Notification(title, options);
    n.onclick = () => {
      window.focus();
      n.close();
    };
  } catch {
    // some browsers require a service worker for notifications; ignore
  }
}
