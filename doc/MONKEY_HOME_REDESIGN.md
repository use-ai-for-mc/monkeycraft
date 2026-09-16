# /monkey Home Screen Redesign

> **Status: implemented in `mods/26.2`** (2026-09-09). Direction adjusted during
> implementation: this is a game screen, not a terminal — the visual language is
> warm framed panels (dark bevel + accent bar), a pulsing status dot, and
> playful quest-style copy, not minimalism. Code lives in
> `ui/MonkeyPanelScreen.java` (home page + footer) and `ui/TailscaleLoginCopy.java`
> (`HOME_*` / `QUEST_*` constants). First-pairing tutorial collapse is driven by
> the new `ModConfig.phonePairedOnce` flag (Option C below).

Status page + first settings stop after the setup wizard. Vanilla widgets only:
text, `fill()` panels, `Button` (blue, 20px tall). Screen width 320–480px,
body scrolls. English in-game copy. 26.2.

Color grammar used below (vanilla formatting codes):

| Code | Role |
|------|------|
| `§f` white | section labels, step text |
| `§6§l` gold bold | the hero value — the one thing to act on |
| `§e` yellow | waiting / attention status |
| `§a` green | running / connected / good |
| `§c` red | problem / stopped-by-error |
| `§7` gray | one-line explanations |
| `§8` dark gray | tooltips, footnotes |

---

## 1. Hierarchy rules

1. **One status, one place.** The colored status line under the title is the
   only place state appears. The title bar never carries state; no second strip.
2. **One hero value.** The address the phone needs appears exactly once,
   centered, gold bold, with Copy next to it. Never repeated in prose.
3. **One "why" sentence.** Directly under the hero, gray, ≤ 15 words. Answers
   "what is this name" — nothing more.
4. **Action rank: state action > Copy > utility row.** Stop / Connect method /
   More settings live in one small row pinned to the bottom. They never sit
   above the hero, never share a row with the primary action, never render at
   full width.
5. **No meta text.** Nothing on the screen describes the screen. No
   "This is the MonkeyCraft status page".
6. **No paragraph over 2 lines.** Longer explanations become a tooltip on the
   relevant button or a "More settings" sub-screen.
7. **Above the fold at 320px:** status, hero, why-line, first-step block.
   Everything else may scroll.

---

## 2. Main wireframe — embedded Tailscale · running · waiting for phone

```
┌────────────────────────────────────────────────────────────┐
│ MonkeyCraft                                    (§f, title) │
│ ● Waiting for phone                            (§e)        │
├────────────────────────────────────────────────────────────┤
│                                                            │
│              On your phone, connect to:        (§7)        │
│                                                            │
│           monkeycraft-qdJy               [ Copy ]          │
│                  (§6§l, hero)              (50×20 button)  │
│                                                            │
│   Built-in Tailscale — no Tailscale app needed on this     │
│   computer. Any phone on your tailnet sees this name. (§7) │
│                                                            │
│   First phone?                                 (§f)        │
│   1. Open MonkeyCraft on the phone             (§f)        │
│   2. Sign in to the same Tailscale account     (§f)        │
│   3. Tap monkeycraft-qdJy, then tap Pair       (§f)        │
│   Then tap Allow on the pop-up here. Keep this screen      │
│   open while you pair.                         (§7)        │
│                                                            │
│   After the first time, phones connect without a password. │
│                                                (§8)        │
├────────────────────────────────────────────────────────────┤
│ [ More settings… ] [ Connect method… ] [ Stop server ]     │
│         (~125×20 each, 6px gaps, utility row)              │
└────────────────────────────────────────────────────────────┘
```

Answers at a glance:

1. *Can a phone connect now?* → the `● Waiting for phone` line (yellow = yes,
   ready and listening).
2. *What does the phone use?* → the gold hero + one gray why-line.
3. *What does a first-timer do next?* → the three one-line steps.
4. *Where are Stop / change path / settings?* → bottom utility row, visually
   quiet, always in the same place in every state.

Note: these three steps are the **phone-side next action**, not a recap of the
5-step wizard — the wizard list stays in the wizard.

---

## 3. State variants

Layout never reflows: title, status line, divider, hero zone, help zone,
utility row stay fixed. Only content and the state action change.

### 3a. Phone connected

```
│ ● Phone connected — iPhone-15                  (§a)        │
├────────────────────────────────────────────────────────────┤
│              Connected phone:                  (§7)        │
│                                                            │
│              iPhone-15                                     │
│                  (§6§l, hero)                              │
│                                                            │
│   Everything is working. You can close this screen.   (§7) │
│   Video and controls run on the phone.            (§7)     │
```

Utility row unchanged (Stop server still reachable). A new phone arriving
during a connection falls back to state 2 (waiting copy) — the connected
phone is unaffected.

### 3b. Stopped (user pressed Stop server)

```
│ ■ Stopped — phones can't connect               (§7)        │
├────────────────────────────────────────────────────────────┤
│                                                            │
│              [ Start server ]   (primary, 120×20, centered)│
│                                                            │
│   The name monkeycraft-qdJy is kept for next time.    (§7) │
```

Utility row shows `[ More settings… ] [ Connect method… ]` only —
Stop is replaced by the primary Start button.

### 3c. Needs Tailscale sign-in

```
│ ● Sign-in needed                               (§c)        │
├────────────────────────────────────────────────────────────┤
│   This computer must sign in to Tailscale once.     (§f)   │
│                                                            │
│           [ Sign in to Tailscale ]   (primary, 150×20)     │
│                                                            │
│   Opens your browser. Use the same account the phone       │
│   will sign in with.                              (§7)     │
```

No hero — there is no address to show yet. After sign-in, return to state 2.

### 3d. Pairing approval (phone tapped Pair)

```
│ ● iPhone-15 wants to connect                   (§e)        │
├────────────────────────────────────────────────────────────┤
│   Only allow a phone you recognize.               (§f)     │
│                                                            │
│        [ Allow ]                [ Deny ]                   │
│        (100×20, §a-tinted)      (100×20, §c-tinted)        │
│                                                            │
│   Allow remembers this phone. Deny blocks it once.  (§7)   │
```

This replaces the hero zone while pending; the utility row stays.

### 3e. Tailscale failed to start

```
│ ● Tailscale failed to start                    (§c)        │
├────────────────────────────────────────────────────────────┤
│   Could not reach the Tailscale service. Check this        │
│   computer's internet connection, then try again.   (§f)   │
│                                                            │
│              [ Try again ]   (primary, 120×20)             │
│                                                            │
│   Detail: <one-line error, truncated>             (§8)     │
```

One-line error detail in dark gray for power users; never a stack trace.

### 3f. System Tailscale (Connect method = system)

Same as state 2; only the why-line and hero value change:

```
│              On your phone, connect to:        (§7)        │
│           <this-computer's-tailnet-name>   [ Copy ]        │
│   Uses the Tailscale app already on this computer. The     │
│   phone must be on the same tailnet.              (§7)     │
```

### 3g. LAN only (Connect method = LAN)

```
│              On your phone, connect to:        (§7)        │
│                                                            │
│           192.168.1.23:25575             [ Copy ]          │
│                  (§6§l, hero)                              │
│                                                            │
│   Local network only — the phone must be on this Wi-Fi.    │
│   No Tailscale needed.                            (§7)     │
```

Plus one extra gray line under the first-steps block:

```
│   Phones on other networks can't reach this address. (§8)  │
```

---

## 4. Layout metrics (vanilla)

- Screen: center panel, content width = min(440, screenWidth − 40).
- Title at y=10, status line at y=24, `fill()` divider at y=36.
- Content padding 20px sides, 8px between text lines, 16px between sections.
- Hero zone height fixed (~64px) across all states so buttons never jump.
- Buttons: 20px high. Utility row pinned at height − 28; each button ~125px,
  6px gaps; row is the only element below the second divider.
- Primary action buttons (Start / Sign in / Try again / Allow·Deny) centered
  in the hero zone.
- Body scrolls only the zone between the two dividers; title, status, and
  utility row never scroll.

---

## 5. Compact vs. tutorial-first — recommendation

**Option A — Tutorial-first (static):** the 3-step block is always full size.
Simple, but daily users pay a permanent tax for a one-time need.

**Option B — Compact (static):** always one hint line ("New phone? Open
MonkeyCraft on it and tap monkeycraft-qdJy"). Bad for exactly the audience
this screen serves: first-timers.

**Option C — State-adaptive (recommended):** full tutorial block until the
first successful pairing, then auto-collapse to the single hint line. One
layout, no toggle, no extra settings. First-timers get guidance at the exact
moment they need it; daily users get a clean status page. Persist
`firstPhoneConnected` in config to drive the collapse.

---

## 6. Copy deck

| Region | State | Current | Proposed | Why |
|---|---|---|---|---|
| Title bar | all | `MonkeyCraft ▪ Waiting for phone · monkeycraft-qdJy` | `MonkeyCraft` | State belongs in one place (the status line). Title carrying state + address is duplication #1. |
| Status strip | waiting | Dark strip: `Waiting for phone` / `Built-in Tailscale · monkeycraft-qdJy` | `● Waiting for phone` (yellow, under title) | Strip duplicated the title and pre-empted the hero. Address moves to the hero, once. |
| Status strip | connected | (same strip pattern) | `● Phone connected — iPhone-15` (green) | One line, verb-first, color = meaning. |
| Status strip | stopped | — | `■ Stopped — phones can't connect` (gray) | Answers Q1 instantly; sets up the Start button. |
| Status strip | needs login | — | `● Sign-in needed` (red) | Problem color; the fix is the primary button below. |
| Status strip | approval | — | `● iPhone-15 wants to connect` (yellow) | Attention, not error. |
| Status strip | failed | — | `● Tailscale failed to start` (red) | States the failure in plain words. |
| Body intro | waiting | `This is the MonkeyCraft status page. It shows whether a phone can reach...` | *(removed)* | Meta text describing the page. The layout must answer, not narrate. |
| Top buttons | all | `Stop server` / `Change how phones connect` (two equal blue buttons, top of body) | Bottom utility row: `More settings…` `Connect method…` `Stop server` | Two equal primaries competed with the hero and were the loudest thing on screen. They're rare actions — quiet, consistent, bottom. |
| Hero label | waiting | `Ready for a phone` | `On your phone, connect to:` | Names the user's task, not the system's mood. |
| Hero value | waiting | `Name on the phone  monkeycraft-qdJy` + separate `monkeycraft-qdJy [Copy]` row | `monkeycraft-qdJy` (gold bold, centered) + `[ Copy ]` beside it | Address appeared 3× (title, strip, label row, copy row = 4×). Once, big, copyable. |
| Why-line | waiting | Paragraph: `This computer is on Tailscale as monkeycraft-qdJy. MonkeyCraft runs that node here, so you do not install...` | `Built-in Tailscale — no Tailscale app needed on this computer. Any phone on your tailnet sees this name.` | Same facts, one breath, no jargon wall. |
| Why-line | system Tailscale | (same paragraph) | `Uses the Tailscale app already on this computer. The phone must be on the same tailnet.` | The "why" must match the actual connection path. |
| Why-line | LAN | (same paragraph) | `Local network only — the phone must be on this Wi-Fi. No Tailscale needed.` | Sets the key expectation (Wi-Fi only) in one line. |
| First steps | waiting (pre-first-pair) | `On the phone, open MonkeyCraft with Tailscale and choose monkeycraft-qdJy. The phone asks to pair; Allow or Deny appears on this screen...` | `First phone?` + `1. Open MonkeyCraft on the phone` / `2. Sign in to the same Tailscale account` / `3. Tap monkeycraft-qdJy, then tap Pair` | The recipe as a run-on sentence forced re-reading. Three one-line steps are scannable mid-task. |
| Pairing note | waiting | (inside the same paragraph) | `Then tap Allow on the pop-up here. Keep this screen open while you pair.` (gray) | The one behavior the screen needs from the user, pulled out of the paragraph. |
| Everyday note | waiting | `Everyday connections do not use a password.` | `After the first time, phones connect without a password.` (dark gray footnote) | Kept — it's genuinely useful — but demoted to footnote rank. |
| Footer | all | `Stop server pauses new connections. Change how phones connect if you want the Tailscale app on this computer, or only the local Wi-Fi.` | *(removed; becomes tooltips on the utility buttons)* | Prose explaining buttons is a sign the buttons aren't self-explanatory. Tooltip keeps the info at the point of need. |
| Approval body | approval | (pop-up only) | `Only allow a phone you recognize.` + `[ Allow ] [ Deny ]` + `Allow remembers this phone. Deny blocks it once.` | Approval is a state of the home screen, not a bolt-on; consequence of each choice stated in 8 words. |
| Failed detail | failed | — | `Detail: <one-line error>` (dark gray, truncated) | Debug info available without turning the page into debug output. |

---

## 7. What to remove

1. Title-bar state suffix (`▪ Waiting for phone · monkeycraft-qdJy`).
2. The dark duplicate status strip under the title.
3. The `This is the MonkeyCraft status page…` intro paragraph.
4. Both top blue buttons (`Stop server` / `Change how phones connect`) —
   relocated to the bottom utility row, restyled quiet.
5. The `Ready for a phone` paragraph (replaced by why-line + steps).
6. The duplicate `Name on the phone` label row (address shows once, as hero).
7. The gray footer explaining the buttons (becomes tooltips).

Net effect: one status, one hero, one why-line, one next action, one quiet
utility row — a designed MC screen, not debug output.
