export function isFullscreen(): boolean {
  return typeof document !== "undefined" && document.fullscreenElement !== null;
}

export async function toggleFullscreen(el: HTMLElement): Promise<void> {
  try {
    if (document.fullscreenElement) {
      await document.exitFullscreen();
    } else {
      await el.requestFullscreen({ navigationUI: "hide" });
      // Android lets a fullscreen page lock orientation; iOS ignores it.
      const orientation = screen.orientation as ScreenOrientation & {
        lock?: (o: string) => Promise<void>;
      };
      await orientation.lock?.("landscape").catch(() => {});
    }
  } catch {
    // unsupported (iPhone Safari) or denied
  }
}
