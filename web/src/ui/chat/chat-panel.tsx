import { useSignal } from "@preact/signals";
import { useEffect, useRef } from "preact/hooks";
import type { ChatMessage, ChatSegment, ClientMessage } from "../../protocol/messages.ts";
import { initialChat, outgoingChat, reduceChat } from "../../session/chat.ts";
import type { AppContext } from "../app.tsx";

interface Props {
  ctx: AppContext;
  onClose: () => void;
}

const PLAYER_COUNT_INTERVAL_MS = 5000;
const OPENAUDIOMC_PREFIX = "https://session.openaudiomc.net/";

export function ChatPanel({ ctx, onClose }: Props) {
  const controller = ctx.controller;
  const chat = useSignal(initialChat);
  const draft = useSignal("");
  const showPlayers = useSignal(false);
  const listRef = useRef<HTMLDivElement>(null);
  const inputRef = useRef<HTMLInputElement>(null);
  const send = (msg: ClientMessage) => controller.send(msg);

  useEffect(() => {
    controller.setMode("CHAT");
    send({ type: "SUBSCRIBE_CHAT" });
    const off = controller.onEvent((ev) => {
      if (ev.kind === "message") chat.value = reduceChat(chat.value, ev.msg);
      if (ev.kind === "authenticated") send({ type: "SUBSCRIBE_CHAT" });
    });
    const hasPlayerList = controller.serverSupports("PLAYER_LIST");
    let timer: ReturnType<typeof setInterval> | null = null;
    if (hasPlayerList) {
      send({ type: "GET_PLAYER_COUNT" });
      timer = setInterval(() => send({ type: "GET_PLAYER_COUNT" }), PLAYER_COUNT_INTERVAL_MS);
    }
    return () => {
      off();
      if (timer) clearInterval(timer);
      send({ type: "UNSUBSCRIBE_CHAT" });
      controller.setMode("STREAMING");
    };
  }, [controller, chat]);

  // Stick to the bottom when new messages arrive.
  useEffect(() => {
    const el = listRef.current;
    if (!el) return;
    const nearBottom = el.scrollHeight - el.scrollTop - el.clientHeight < 80;
    if (nearBottom) el.scrollTop = el.scrollHeight;
  }, [chat.value.messages]);

  const submit = (e: Event) => {
    e.preventDefault();
    const out = outgoingChat(draft.value);
    if (!out) return;
    if (send(out)) draft.value = "";
  };

  const onClick = (seg: ChatSegment) => {
    const ev = seg.clickEvent;
    if (!ev) return;
    switch (ev.action) {
      case "run_command":
        send({
          type: "RUN_COMMAND",
          command: ev.value.startsWith("/") ? ev.value : `/${ev.value}`,
        });
        break;
      case "suggest_command":
        draft.value = ev.value;
        inputRef.current?.focus();
        break;
      case "copy_to_clipboard":
        void navigator.clipboard?.writeText(ev.value);
        break;
      case "open_url":
        if (ev.value.startsWith(OPENAUDIOMC_PREFIX) || /^https?:\/\//.test(ev.value)) {
          window.open(ev.value, "_blank", "noopener");
        }
        break;
    }
  };

  const state = controller.state.value;
  const banner = state.hibernating
    ? { text: state.hibernationMessage ?? "Paused", cls: "hib" }
    : state.nudge
      ? { text: [state.nudge.title, state.nudge.body].filter(Boolean).join(" — "), cls: "nudge" }
      : null;

  return (
    <section class="chat" data-testid="chat-panel">
      <header>
        <button type="button" onClick={onClose} aria-label="Back to game">
          ‹
        </button>
        <h2>Chat</h2>
        {chat.value.playerCount !== null && (
          <button
            type="button"
            class="players"
            onClick={() => {
              showPlayers.value = true;
              send({ type: "GET_PLAYER_LIST" });
            }}
          >
            👥 {chat.value.playerCount}
          </button>
        )}
      </header>
      {banner && <div class={`chat-banner ${banner.cls}`}>{banner.text}</div>}
      {chat.value.notice && <div class="chat-banner deny">{chat.value.notice.text}</div>}
      <div class="messages" ref={listRef}>
        {!chat.value.loaded && <p class="muted">Loading…</p>}
        {chat.value.loaded && chat.value.messages.length === 0 && (
          <p class="muted">No messages yet</p>
        )}
        {chat.value.messages.map((m, i) => (
          <Message key={`${m.timestamp}-${i}`} message={m} onClick={onClick} />
        ))}
      </div>
      <form class="composer" onSubmit={submit}>
        <input
          ref={inputRef}
          type="text"
          value={draft.value}
          placeholder="Message or /command"
          autocapitalize="off"
          autocorrect="off"
          onInput={(e) => {
            draft.value = (e.currentTarget as HTMLInputElement).value;
          }}
        />
        <button type="submit" class="primary">
          Send
        </button>
      </form>
      {showPlayers.value && (
        <div class="sheet-host">
          <button
            type="button"
            class="sheet-backdrop"
            aria-label="Close"
            onClick={() => (showPlayers.value = false)}
          />
          <div class="sheet">
            <h3>Players online ({chat.value.playerCount ?? "?"})</h3>
            {chat.value.players ? (
              <ul>
                {chat.value.players.map((p) => (
                  <li key={p}>{p}</li>
                ))}
              </ul>
            ) : (
              <p class="muted">Loading…</p>
            )}
          </div>
        </div>
      )}
    </section>
  );
}

function Message({
  message,
  onClick,
}: {
  message: ChatMessage;
  onClick: (s: ChatSegment) => void;
}) {
  return (
    <div class="msg">
      <span class="sender">{message.sender}</span>
      <span class="body">
        {message.segments.map((s, i) => (
          <Segment key={i} seg={s} onClick={onClick} />
        ))}
      </span>
    </div>
  );
}

function Segment({ seg, onClick }: { seg: ChatSegment; onClick: (s: ChatSegment) => void }) {
  const style: Record<string, string> = {};
  if (seg.color && /^#[0-9a-f]{6}$/i.test(seg.color)) style.color = seg.color;
  if (seg.bold) style.fontWeight = "700";
  if (seg.italic) style.fontStyle = "italic";
  const deco = [seg.underlined ? "underline" : "", seg.strikethrough ? "line-through" : ""]
    .filter(Boolean)
    .join(" ");
  if (deco) style.textDecoration = deco;
  const title = seg.hoverEvent ? seg.hoverEvent.segments.map((s) => s.text).join("") : undefined;
  if (seg.clickEvent) {
    return (
      <button
        type="button"
        class="seg-link"
        style={style}
        title={title}
        onClick={() => onClick(seg)}
      >
        {seg.text}
      </button>
    );
  }
  return (
    <span style={style} title={title}>
      {seg.text}
    </span>
  );
}
