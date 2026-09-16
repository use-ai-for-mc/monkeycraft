// User settings, persisted under one localStorage key. Defaults match the
// Flutter client (docs/LEGACY_CLIENT_NOTES.md, "Settings").

import type { ResolutionPreset } from "./resolution.ts";

export type ControlLayout = "auto" | "touch" | "mouse";

export interface Settings {
  fps: number;
  colorMode: 0 | 1 | 2 | 3;
  preset: ResolutionPreset;
  invertLookY: boolean;
  autoSwitchRideChat: boolean;
  autoFaceMovement: boolean;
  dataSaver: boolean;
  controlLayout: ControlLayout;
  deviceName: string;
  /** Degrees of look per CSS pixel of drag. */
  lookSensitivity: number;
}

export const SETTINGS_KEY = "monkeycraft.settings";

export const defaultSettings: Settings = {
  fps: 10,
  colorMode: 0,
  preset: "medium",
  invertLookY: true,
  autoSwitchRideChat: false,
  autoFaceMovement: false,
  dataSaver: false,
  controlLayout: "auto",
  deviceName: "",
  lookSensitivity: 0.12,
};

export interface StorageLike {
  getItem(key: string): string | null;
  setItem(key: string, value: string): void;
  removeItem(key: string): void;
}

const clampInt = (v: unknown, lo: number, hi: number, fallback: number): number =>
  typeof v === "number" && Number.isFinite(v)
    ? Math.min(hi, Math.max(lo, Math.round(v)))
    : fallback;

/** Coerce arbitrary JSON into a valid Settings object. */
export function sanitizeSettings(raw: unknown): Settings {
  const r = (typeof raw === "object" && raw !== null ? raw : {}) as Record<string, unknown>;
  const d = defaultSettings;
  const colorMode = clampInt(r.colorMode, 0, 3, d.colorMode) as Settings["colorMode"];
  const preset: ResolutionPreset =
    r.preset === "low" || r.preset === "medium" || r.preset === "high" ? r.preset : d.preset;
  const controlLayout: ControlLayout =
    r.controlLayout === "touch" || r.controlLayout === "mouse" || r.controlLayout === "auto"
      ? r.controlLayout
      : d.controlLayout;
  const sens =
    typeof r.lookSensitivity === "number" && r.lookSensitivity > 0 && r.lookSensitivity < 5
      ? r.lookSensitivity
      : d.lookSensitivity;
  return {
    fps: clampInt(r.fps, 1, 20, d.fps),
    colorMode,
    preset,
    invertLookY: typeof r.invertLookY === "boolean" ? r.invertLookY : d.invertLookY,
    autoSwitchRideChat:
      typeof r.autoSwitchRideChat === "boolean" ? r.autoSwitchRideChat : d.autoSwitchRideChat,
    autoFaceMovement:
      typeof r.autoFaceMovement === "boolean" ? r.autoFaceMovement : d.autoFaceMovement,
    dataSaver: typeof r.dataSaver === "boolean" ? r.dataSaver : d.dataSaver,
    controlLayout,
    deviceName: typeof r.deviceName === "string" ? r.deviceName.slice(0, 48) : d.deviceName,
    lookSensitivity: sens,
  };
}

export function loadSettings(storage: StorageLike): Settings {
  try {
    const text = storage.getItem(SETTINGS_KEY);
    if (!text) return { ...defaultSettings };
    return sanitizeSettings(JSON.parse(text));
  } catch {
    return { ...defaultSettings };
  }
}

export function saveSettings(storage: StorageLike, settings: Settings): void {
  storage.setItem(SETTINGS_KEY, JSON.stringify(sanitizeSettings(settings)));
}
