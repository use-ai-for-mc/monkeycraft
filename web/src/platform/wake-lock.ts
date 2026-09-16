// Keep the screen on while streaming. Re-acquired after the tab becomes visible.

export class WakeLock {
  private sentinel: WakeLockSentinel | null = null;
  private wanted = false;
  private readonly onVisible = () => {
    if (this.wanted && !document.hidden) void this.acquire();
  };

  async request(): Promise<void> {
    this.wanted = true;
    document.addEventListener("visibilitychange", this.onVisible);
    await this.acquire();
  }

  release(): void {
    this.wanted = false;
    document.removeEventListener("visibilitychange", this.onVisible);
    void this.sentinel?.release();
    this.sentinel = null;
  }

  private async acquire(): Promise<void> {
    if (!("wakeLock" in navigator) || this.sentinel) return;
    try {
      this.sentinel = await navigator.wakeLock.request("screen");
      this.sentinel.addEventListener("release", () => {
        this.sentinel = null;
      });
    } catch {
      // denied or unsupported; nothing to do
    }
  }
}
