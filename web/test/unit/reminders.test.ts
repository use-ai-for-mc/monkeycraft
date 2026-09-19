import { describe, expect, it, vi } from "vitest";
import { ReminderAlerts, type ReminderSound } from "../../src/platform/reminders.ts";

class FakeSound implements ReminderSound {
  plays = 0;
  async unlock(): Promise<boolean> {
    return true;
  }
  play(): boolean {
    this.plays += 1;
    return true;
  }
}

describe("ReminderAlerts", () => {
  it("respects sound=false for a nudge while preserving its notification", () => {
    const sound = new FakeSound();
    const notify = vi.fn(() => false);
    const alerts = new ReminderAlerts({ sound, notify });
    alerts.nudge({ title: "Ride", body: "Ready", sound: false });
    expect(notify).toHaveBeenCalledWith("Ride", "Ready", true);
    expect(sound.plays).toBe(0);
  });

  it("does not add a page chime when a hidden-tab notification is shown", () => {
    const sound = new FakeSound();
    const alerts = new ReminderAlerts({ sound, notify: () => true });
    alerts.nudge({ title: "Ride", body: "Ready", sound: true });
    expect(sound.plays).toBe(0);
  });

  it("honors the user's page-sound mute while preserving reminders", () => {
    const sound = new FakeSound();
    const notify = vi.fn(() => false);
    const alerts = new ReminderAlerts({ sound, notify });
    alerts.setSoundEnabled(false);
    alerts.nudge({ title: "Ride", body: "Ready", sound: true });
    expect(notify).toHaveBeenCalledWith("Ride", "Ready", true);
    expect(sound.plays).toBe(0);
  });

  it("does not play a late fallback after mute or disposal", async () => {
    let resolveNotification: (value: boolean) => void = () => {};
    const notification = new Promise<boolean>((resolve) => {
      resolveNotification = resolve;
    });
    const sound = new FakeSound();
    const alerts = new ReminderAlerts({ sound, notify: () => notification });
    alerts.nudge({ title: "Ride", body: "Ready", sound: true });
    alerts.setSoundEnabled(false);
    resolveNotification(false);
    await Promise.resolve();
    expect(sound.plays).toBe(0);

    const disposedSound = new FakeSound();
    const disposed = new ReminderAlerts({
      sound: disposedSound,
      notify: () => Promise.resolve(false),
    });
    disposed.nudge({ title: "Ride", body: "Ready", sound: true });
    disposed.dispose();
    await Promise.resolve();
    expect(disposedSound.plays).toBe(0);
  });

  it("plays one fallback when notification delivery rejects", async () => {
    const sound = new FakeSound();
    const alerts = new ReminderAlerts({
      sound,
      notify: () => Promise.reject(new Error("rejected")),
    });

    alerts.nudge({ title: "Ride", body: "Ready", sound: true });
    await Promise.resolve();

    expect(sound.plays).toBe(1);
  });

  it("updates, cancels, deduplicates, and restores timed reminders", async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(0);
      const sound = new FakeSound();
      const notify = vi.fn(() => false);
      const alerts = new ReminderAlerts({ sound, notify, now: () => Date.now() });
      const first = {
        fireAtEpochMs: 1_000,
        title: "Ride",
        body: "Done",
        sound: true,
        countDownText: null,
      };
      const updated = { ...first, fireAtEpochMs: 2_000, title: "Updated" };
      alerts.setTimed(first);
      alerts.setTimed(updated);
      vi.advanceTimersByTime(1_000);
      expect(sound.plays).toBe(0);
      alerts.setTimed(null);
      vi.advanceTimersByTime(2_000);
      expect(sound.plays).toBe(0);
      alerts.setTimed(updated);
      vi.advanceTimersByTime(2_000);
      await Promise.resolve();
      expect(notify).toHaveBeenCalledTimes(1);
      expect(sound.plays).toBe(1);
      alerts.setTimed(updated);
      alerts.restore();
      expect(notify).toHaveBeenCalledTimes(1);
      expect(sound.plays).toBe(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it("separates distinct reminders with one deadline and ignores stale deadlines", async () => {
    vi.useFakeTimers();
    try {
      vi.setSystemTime(100_000);
      const sound = new FakeSound();
      const notify = vi.fn(() => false);
      const alerts = new ReminderAlerts({ sound, notify, now: () => Date.now() });
      alerts.setTimed({
        fireAtEpochMs: 101_000,
        title: "First ride",
        body: "Done",
        sound: true,
        countDownText: null,
      });
      alerts.setTimed({
        fireAtEpochMs: 101_000,
        title: "Second ride",
        body: "Done",
        sound: true,
        countDownText: null,
      });
      vi.advanceTimersByTime(1_000);
      await Promise.resolve();
      expect(notify).toHaveBeenCalledWith("Second ride", "Done", false);
      expect(sound.plays).toBe(1);
      alerts.setTimed({
        fireAtEpochMs: 70_000,
        title: "Expired ride",
        body: "Done",
        sound: true,
        countDownText: null,
      });
      alerts.restore();
      expect(notify).toHaveBeenCalledTimes(1);
      expect(sound.plays).toBe(1);
    } finally {
      vi.useRealTimers();
    }
  });

  it("does not replay a fired reminder after a page refresh", async () => {
    vi.useFakeTimers();
    const values = new Map<string, string>();
    vi.stubGlobal("sessionStorage", {
      getItem: (key: string) => values.get(key) ?? null,
      setItem: (key: string, value: string) => values.set(key, value),
    });
    try {
      vi.setSystemTime(0);
      const timed = {
        fireAtEpochMs: 1_000,
        title: "Ride",
        body: "Done",
        sound: true,
        countDownText: null,
      };
      const firstSound = new FakeSound();
      const first = new ReminderAlerts({
        sound: firstSound,
        notify: () => false,
        now: () => Date.now(),
      });
      first.setTimed(timed);
      vi.advanceTimersByTime(1_000);
      await Promise.resolve();
      expect(firstSound.plays).toBe(1);

      const refreshedSound = new FakeSound();
      const refreshed = new ReminderAlerts({
        sound: refreshedSound,
        notify: () => false,
        now: () => Date.now(),
      });
      refreshed.setTimed(timed);
      refreshed.restore();
      vi.advanceTimersByTime(1_000);
      expect(refreshedSound.plays).toBe(0);
    } finally {
      vi.unstubAllGlobals();
      vi.useRealTimers();
    }
  });

  it("does not fire early and discards a callback delayed beyond the grace period", async () => {
    let now = 0;
    const callbacks: Array<() => void> = [];
    const sound = new FakeSound();
    const notify = vi.fn(() => false);
    const alerts = new ReminderAlerts({
      sound,
      notify,
      now: () => now,
      setTimeout: (callback) => {
        callbacks.push(callback);
        return callbacks.length as never;
      },
      clearTimeout: () => {},
    });
    const timed = {
      fireAtEpochMs: 1_000,
      title: "Ride",
      body: "Done",
      sound: true,
      countDownText: null,
    };
    alerts.setTimed(timed);
    now = 500;
    callbacks[0]?.();
    expect(notify).not.toHaveBeenCalled();
    now = 1_000;
    callbacks[1]?.();
    await Promise.resolve();
    expect(notify).toHaveBeenCalledTimes(1);
    expect(sound.plays).toBe(1);

    const delayed = new ReminderAlerts({
      sound: new FakeSound(),
      notify,
      now: () => now,
      setTimeout: (callback) => {
        callbacks.push(callback);
        return callbacks.length as never;
      },
      clearTimeout: () => {},
    });
    delayed.setTimed({ ...timed, fireAtEpochMs: 2_000, title: "Late" });
    now = 20_000;
    callbacks[2]?.();
    expect(notify).toHaveBeenCalledTimes(1);
  });
});
