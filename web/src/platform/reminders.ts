import { type Signal, signal } from "@preact/signals";
import type { TimedNotification } from "../protocol/messages.ts";
import { ensureNotificationPermission, notifyIfHidden } from "./notifications.ts";

export type ReminderStatus = "not-enabled" | "ready" | "unsupported" | "blocked";

export interface ReminderSound {
  unlock(): Promise<boolean>;
  play(): boolean;
}

export const REMINDER_LATE_GRACE_MS = 15_000;
const FIRED_REMINDERS_KEY = "monkeycraft.reminder-fires";
const MAX_FIRED_REMINDERS = 32;
const MAX_TIMER_DELAY_MS = 2_147_483_647;

class WebAudioReminderSound implements ReminderSound {
  private context: AudioContext | null = null;

  async unlock(): Promise<boolean> {
    const AudioContextConstructor = window.AudioContext ?? window.webkitAudioContext;
    if (!AudioContextConstructor) return false;
    try {
      this.context ??= new AudioContextConstructor();
      await this.context.resume();
      return this.context.state === "running";
    } catch {
      return false;
    }
  }

  play(): boolean {
    const context = this.context;
    if (context?.state !== "running") return false;
    try {
      const oscillator = context.createOscillator();
      const gain = context.createGain();
      oscillator.type = "sine";
      oscillator.frequency.setValueAtTime(880, context.currentTime);
      gain.gain.setValueAtTime(0.0001, context.currentTime);
      gain.gain.exponentialRampToValueAtTime(0.12, context.currentTime + 0.01);
      gain.gain.exponentialRampToValueAtTime(0.0001, context.currentTime + 0.2);
      oscillator.connect(gain).connect(context.destination);
      oscillator.start();
      oscillator.stop(context.currentTime + 0.21);
      return true;
    } catch {
      return false;
    }
  }
}

interface ReminderOptions {
  sound?: ReminderSound;
  now?: () => number;
  notify?: (title: string, body: string | null, silent: boolean) => boolean | Promise<boolean>;
  setTimeout?: (callback: () => void, delay: number) => ReturnType<typeof setTimeout>;
  clearTimeout?: (timer: ReturnType<typeof setTimeout>) => void;
}

export class ReminderAlerts {
  readonly status: Signal<ReminderStatus> = signal("not-enabled");
  private readonly sound: ReminderSound;
  private readonly now: () => number;
  private readonly notify: (
    title: string,
    body: string | null,
    silent: boolean,
  ) => boolean | Promise<boolean>;
  private readonly schedule: (callback: () => void, delay: number) => ReturnType<typeof setTimeout>;
  private readonly cancel: (timer: ReturnType<typeof setTimeout>) => void;
  private timer: ReturnType<typeof setTimeout> | null = null;
  private timed: TimedNotification | null = null;
  private readonly fired = loadFiredReminders();
  private soundEnabled = true;
  private soundGeneration = 0;
  private disposed = false;

  constructor(options: ReminderOptions = {}) {
    this.sound = options.sound ?? new WebAudioReminderSound();
    this.now = options.now ?? (() => Date.now());
    this.notify = options.notify ?? notifyIfHidden;
    this.schedule = options.setTimeout ?? ((callback, delay) => setTimeout(callback, delay));
    this.cancel = options.clearTimeout ?? ((timer) => clearTimeout(timer));
  }

  async enable(): Promise<ReminderStatus> {
    const sound = this.sound.unlock();
    const notifications = ensureNotificationPermission();
    const [soundReady, notificationsReady] = await Promise.all([sound, notifications]);
    this.status.value = soundReady || notificationsReady ? "ready" : "blocked";
    return this.status.value;
  }

  test(): boolean {
    const played = this.soundEnabled && this.sound.play();
    if (!played) this.status.value = "blocked";
    return played;
  }

  nudge(nudge: { title: string | null; body: string | null; sound: boolean }): void {
    this.alert(nudge.title ?? "MonkeyCraft", nudge.body, nudge.sound);
  }

  notice(title: string, body: string | null): void {
    this.alert(title, body, false);
  }

  setSoundEnabled(enabled: boolean): void {
    this.soundEnabled = enabled;
    this.soundGeneration += 1;
  }

  setTimed(timed: TimedNotification | null): void {
    if (this.timed && timed && this.key(this.timed) === this.key(timed)) {
      this.timed = timed;
      return;
    }
    this.clearTimer();
    this.timed = timed;
    if (!timed || this.fired.has(this.key(timed))) return;
    this.scheduleTimed(this.key(timed));
  }

  restore(): void {
    const timed = this.timed;
    if (!timed || this.fired.has(this.key(timed))) return;
    this.scheduleTimed(this.key(timed));
  }

  dispose(): void {
    this.disposed = true;
    this.soundGeneration += 1;
    this.clearTimer();
  }

  private fireTimed(key: string): void {
    this.timer = null;
    const timed = this.timed;
    if (!timed || this.key(timed) !== key || this.fired.has(key)) return;
    const remaining = timed.fireAtEpochMs - this.now();
    if (remaining > 0) {
      this.scheduleTimed(key);
      return;
    }
    if (remaining < -REMINDER_LATE_GRACE_MS) {
      this.markFired(key);
      return;
    }
    this.markFired(key);
    this.alert(timed.title ?? "MonkeyCraft", timed.body, timed.sound);
  }

  private clearTimer(): void {
    if (this.timer !== null) this.cancel(this.timer);
    this.timer = null;
  }

  private key(timed: TimedNotification): string {
    return `${timed.fireAtEpochMs}:${fingerprint(`${timed.title ?? ""}\u0000${timed.body ?? ""}`)}`;
  }

  private playSound(): boolean {
    return this.soundEnabled && this.sound.play();
  }

  private async alert(title: string, body: string | null, requestedSound: boolean): Promise<void> {
    const audible = requestedSound && this.soundEnabled;
    const generation = this.soundGeneration;
    let notified = false;
    try {
      notified = await this.notify(title, body, !audible);
    } catch {}
    if (audible && !notified && !this.disposed && this.soundGeneration === generation)
      this.playSound();
  }

  private scheduleTimed(key: string): void {
    const timed = this.timed;
    if (!timed || this.key(timed) !== key || this.fired.has(key)) return;
    const remaining = timed.fireAtEpochMs - this.now();
    if (remaining < -REMINDER_LATE_GRACE_MS) {
      this.markFired(key);
      return;
    }
    this.clearTimer();
    this.timer = this.schedule(
      () => this.fireTimed(key),
      Math.min(Math.max(0, remaining), MAX_TIMER_DELAY_MS),
    );
  }

  private markFired(key: string): void {
    this.fired.add(key);
    saveFiredReminders(this.fired);
  }
}

function loadFiredReminders(): Set<string> {
  if (typeof sessionStorage === "undefined") return new Set();
  try {
    const value = JSON.parse(sessionStorage.getItem(FIRED_REMINDERS_KEY) ?? "[]");
    return new Set(
      Array.isArray(value) ? value.filter((key): key is string => typeof key === "string") : [],
    );
  } catch {
    return new Set();
  }
}

function saveFiredReminders(fired: Set<string>): void {
  if (typeof sessionStorage === "undefined") return;
  try {
    sessionStorage.setItem(
      FIRED_REMINDERS_KEY,
      JSON.stringify([...fired].slice(-MAX_FIRED_REMINDERS)),
    );
  } catch {}
}

function fingerprint(value: string): string {
  let hash = 2_166_136_261;
  for (let i = 0; i < value.length; i++) {
    hash ^= value.charCodeAt(i);
    hash = Math.imul(hash, 16_777_619);
  }
  return (hash >>> 0).toString(16);
}

declare global {
  interface Window {
    webkitAudioContext?: typeof AudioContext;
  }
}
