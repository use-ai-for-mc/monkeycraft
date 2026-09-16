import type { ClientMessage } from "../../protocol/messages.ts";

interface Props {
  selected: number;
  expanded: boolean;
  onToggle: () => void;
  onSelect: (slot: number) => void;
  send: (msg: ClientMessage) => void;
  /** Q/E/F momentary keys; hidden while a GUI is open. */
  showKeys: boolean;
}

const KEYS: Array<{ key: "Q" | "E" | "F"; label: string }> = [
  { key: "E", label: "E" },
  { key: "Q", label: "Q" },
  { key: "F", label: "F" },
];

export function Hotbar({ selected, expanded, onToggle, onSelect, send, showKeys }: Props) {
  const tap = (key: "Q" | "E" | "F") => {
    send({ type: "INPUT", key, pressed: true });
    setTimeout(() => send({ type: "INPUT", key, pressed: false }), 50);
  };
  return (
    <div class="hotbar" onPointerDown={(e) => e.stopPropagation()}>
      <button type="button" class="pill" onClick={onToggle} aria-label="Hotbar">
        {selected + 1}
      </button>
      {expanded && (
        <div class="grid">
          {Array.from({ length: 9 }, (_, i) => (
            <button
              type="button"
              key={i}
              class={i === selected ? "slot selected" : "slot"}
              onClick={() => onSelect(i)}
            >
              {i + 1}
            </button>
          ))}
          {showKeys &&
            KEYS.map((k) => (
              <button type="button" key={k.key} class="slot key" onClick={() => tap(k.key)}>
                {k.label}
              </button>
            ))}
        </div>
      )}
    </div>
  );
}
