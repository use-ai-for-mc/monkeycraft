import type { ClickMode } from "../../input/screen-mode.ts";

interface Props {
  expanded: boolean;
  onToggle: () => void;
  onEscape: () => void;
  shiftActive: boolean;
  onShift: (active: boolean) => void;
  clickMode: ClickMode;
  onClickMode: (mode: ClickMode) => void;
  /** Touch users need the click-mode chips; a mouse has real buttons. */
  showClickModes: boolean;
}

/** ESC palette shown whenever a Minecraft GUI is open (SCREEN_STATE), regardless of input device. */
export function ScreenPalette(p: Props) {
  return (
    <div class="palette" data-testid="screen-palette" onPointerDown={(e) => e.stopPropagation()}>
      <button type="button" class="puck" onClick={p.onToggle} aria-label="Screen controls">
        ⌘
      </button>
      {p.expanded && (
        <div class="tray">
          <button type="button" class="esc" onClick={p.onEscape}>
            ESC
          </button>
          <button
            type="button"
            class={p.shiftActive ? "chip active" : "chip"}
            onClick={() => p.onShift(!p.shiftActive)}
          >
            ⇧
          </button>
          {p.showClickModes &&
            (["left", "right", "hover"] as const).map((m) => (
              <button
                type="button"
                key={m}
                class={p.clickMode === m ? "chip active" : "chip"}
                onClick={() => p.onClickMode(m)}
              >
                {m === "left" ? "L" : m === "right" ? "R" : "H"}
              </button>
            ))}
        </div>
      )}
    </div>
  );
}
