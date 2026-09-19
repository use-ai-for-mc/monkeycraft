import { useSignal } from "@preact/signals";
import type { ResolutionPreset } from "../../session/resolution.ts";
import type { ControlLayout, Settings } from "../../session/settings.ts";
import type { AppContext } from "../app.tsx";

interface Props {
  ctx: AppContext;
  onClose: () => void;
  onLogout: () => void;
}

const COLOR_MODES = ["Normal", "High performance (12-bit)", "Retro (6-bit)", "Grayscale"];

export function SettingsPanel({ ctx, onClose, onLogout }: Props) {
  const draft = useSignal<Settings>({ ...ctx.settings.value });
  const confirmLogout = useSignal(false);
  const reminderStatus = useSignal<string | null>(null);
  const dataSaverSupported = ctx.controller.serverSupports("DATA_SAVER");
  const set = <K extends keyof Settings>(key: K, value: Settings[K]) => {
    draft.value = { ...draft.value, [key]: value };
  };
  const apply = () => {
    ctx.updateSettings(draft.value);
    // Stream parameters travel in CLIENT_STATUS; no reconnect needed.
    ctx.controller.syncStatus();
    onClose();
  };
  const d = draft.value;

  return (
    <section class="settings" data-testid="settings-panel">
      <header>
        <button type="button" onClick={onClose} aria-label="Close settings">
          ‹
        </button>
        <h2>Settings</h2>
        <button type="button" class="primary" onClick={apply}>
          Apply
        </button>
      </header>
      <div class="fields">
        <label>
          Device name
          <input
            type="text"
            maxLength={48}
            value={d.deviceName}
            placeholder="shown on the computer"
            onInput={(e) => set("deviceName", (e.currentTarget as HTMLInputElement).value)}
          />
        </label>
        <label>
          Resolution
          <select
            value={d.preset}
            onChange={(e) =>
              set("preset", (e.currentTarget as HTMLSelectElement).value as ResolutionPreset)
            }
          >
            <option value="low">Low</option>
            <option value="medium">Medium</option>
            <option value="high">High</option>
          </select>
        </label>
        <label>
          Color mode
          <select
            value={String(d.colorMode)}
            onChange={(e) =>
              set(
                "colorMode",
                Number((e.currentTarget as HTMLSelectElement).value) as Settings["colorMode"],
              )
            }
          >
            {COLOR_MODES.map((name, i) => (
              <option key={name} value={String(i)}>
                {name}
              </option>
            ))}
          </select>
        </label>
        <label>
          Frame rate: {d.fps} fps
          <input
            type="range"
            min={1}
            max={20}
            value={d.fps}
            onInput={(e) => set("fps", Number((e.currentTarget as HTMLInputElement).value))}
          />
        </label>
        <label>
          Controls
          <select
            value={d.controlLayout}
            onChange={(e) =>
              set("controlLayout", (e.currentTarget as HTMLSelectElement).value as ControlLayout)
            }
          >
            <option value="auto">Auto (follow last input)</option>
            <option value="touch">Touch</option>
            <option value="mouse">Mouse and keyboard</option>
          </select>
        </label>
        <label>
          Look sensitivity: {d.lookSensitivity.toFixed(2)}°/px
          <input
            type="range"
            min={0.02}
            max={0.5}
            step={0.01}
            value={d.lookSensitivity}
            onInput={(e) =>
              set("lookSensitivity", Number((e.currentTarget as HTMLInputElement).value))
            }
          />
        </label>
        <Toggle
          label="Invert look Y axis"
          value={d.invertLookY}
          onChange={(v) => set("invertLookY", v)}
        />
        <Toggle
          label="Auto-switch to chat on rides"
          value={d.autoSwitchRideChat}
          onChange={(v) => set("autoSwitchRideChat", v)}
        />
        <Toggle
          label="Auto-face movement"
          value={d.autoFaceMovement}
          onChange={(v) => set("autoFaceMovement", v)}
        />
        <Toggle
          label="Play page reminder sounds"
          value={d.reminderSound}
          onChange={(v) => set("reminderSound", v)}
        />
        <Toggle
          label={
            dataSaverSupported
              ? "Data saver (fewer keyframes)"
              : "Data saver — not supported by this server"
          }
          value={d.dataSaver && dataSaverSupported}
          disabled={!dataSaverSupported}
          onChange={(v) => set("dataSaver", v)}
        />
        <div class="reminders">
          <span>Browser reminders</span>
          <button
            type="button"
            onClick={() => {
              void ctx.alerts.enable().then((status) => {
                reminderStatus.value =
                  status === "ready"
                    ? "Sound and notifications are enabled where this browser allows them."
                    : "The browser blocked sound and notifications. Check its site permissions.";
              });
            }}
          >
            Enable reminders
          </button>
          <button
            type="button"
            onClick={() => {
              reminderStatus.value = ctx.alerts.test()
                ? "Test sound played."
                : "Enable reminders first, then try the test sound again.";
            }}
          >
            Test sound
          </button>
          {reminderStatus.value && <small>{reminderStatus.value}</small>}
        </div>
        <div class="logout">
          {confirmLogout.value ? (
            <>
              <span>Forget saved passwords and disconnect?</span>
              <button type="button" class="danger" onClick={onLogout}>
                Log out
              </button>
              <button type="button" onClick={() => (confirmLogout.value = false)}>
                Cancel
              </button>
            </>
          ) : (
            <button type="button" onClick={() => (confirmLogout.value = true)}>
              Log out
            </button>
          )}
        </div>
      </div>
    </section>
  );
}

function Toggle({
  label,
  value,
  onChange,
  disabled,
}: {
  label: string;
  value: boolean;
  onChange: (v: boolean) => void;
  disabled?: boolean;
}) {
  return (
    <label class="row">
      <input
        type="checkbox"
        checked={value}
        disabled={disabled}
        onChange={(e) => onChange((e.currentTarget as HTMLInputElement).checked)}
      />
      {label}
    </label>
  );
}
