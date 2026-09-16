/** Calls `listener(hidden)` on visibility changes; returns an unsubscribe function. */
export function listenVisibility(listener: (hidden: boolean) => void): () => void {
  if (typeof document === "undefined") return () => {};
  const handler = () => listener(document.hidden);
  document.addEventListener("visibilitychange", handler);
  return () => document.removeEventListener("visibilitychange", handler);
}

export function isHidden(): boolean {
  return typeof document !== "undefined" && document.hidden;
}
