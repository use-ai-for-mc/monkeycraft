# MonkeyCraft web client: engineering plan

> 2026-09-19 用户最新决定：浏览器改为 Flutter 与 iOS/Android 共用界面和业务逻辑，仅浏览器适配分层。独立 `web/` 停止继续开发验收及发布，保留为行为参考与测试资产。本文后续有关独立重写、Flutter Web 放弃或冻结的描述属于历史，不再作为当前实施指令。当前执行见 `doc/PRODUCT_ROADMAP_EXECUTION.md`。
Status: active. The M0–M4 statements below are historical (2026-09-16), not current-run evidence.
The current product authority is `../doc/PRODUCT_ROADMAP_2026-09.md`; results and
remaining acceptance checks are tracked in `../doc/PRODUCT_ROADMAP_EXECUTION.md`.
Supersedes `web-client-handoff/` (Aug 2026), which planned Flutter-web reuse; that
direction is abandoned.

## 0. Decision and scope

- The browser client is rewritten as a plain HTML5 / TypeScript application in
  `web/`. Flutter web is dropped from the build. The Flutter iOS/Android app in
  `flutter/monkeycraft/` remains a maintained first-class product, including native
  notifications, lock-screen countdowns and park audio.
- The 26.2 mod owns port 9600 and serves the client from the jar's `web/`
  resource directory. The new client ships as static files into the same place.
  26.2 is validated first; P3 ports applicable serving features to the other three versions.
- Protocol, pairing rules, single-session rule and the binary H.264 AU contract are
  frozen. See `docs/PROTOCOL.md`. The client must interoperate with the mod as it
  is in the current working tree.
- Video stays WebCodecs `VideoDecoder` + canvas, secure context required. No WASM
  H.264, no in-page Tailscale.
- Browser limitations: native Live Activity and reliable OS-scheduled reminders are
  App capabilities. Retain available park-audio browser links. Optional protocol
  additions require capability gating; version ports follow roadmap P3.

Reference documents in this directory:

- `docs/PROTOCOL.md`: the wire contract, derived from the Java server.
- `docs/LEGACY_CLIENT_NOTES.md`: Flutter behaviours to keep and defects not to copy.

## 1. Facts that shape the plan

1. **The working tree is the implementation reference.** Protect existing user
   changes. Do not commit, push or deploy publicly unless explicitly requested.
2. **No protocol spec existed.** The Flutter code was the only description.
   `docs/PROTOCOL.md` now is; it must be kept authoritative.
3. **The two live bugs are design bugs, not typos.** Resolution is renegotiated
   from layout inside `build`, the frame gate drops everything until a matching
   header arrives, and the palette is gated on pointer kind. The rewrite removes
   these mechanisms rather than patching them (`docs/LEGACY_CLIENT_NOTES.md`).
4. **Server quirks the client must absorb**: half the frames are IDR with the
   6-byte header in non-dataSaver mode; `ACK` is mandatory per video frame; no
   SPA fallback; no cache headers; no `Origin` check; `SCREEN_TAP` is a no-op;
   letterboxed screens map clicks differently from video; timed-notification key
   names differ between `TIMED_STATUS` and `SERVER_STATUS`.
5. **Web has no audio, notification, or Tailscale feature to lose.** Everything
   Flutter web actually does in the browser today is: login/pair/QR, stream,
   controls, chat, server picker, map, settings, OpenAudioMC link in a new tab.

## 2. Target architecture

### 2.1 Stack

| Concern | Choice | Why |
|---|---|---|
| Language | TypeScript, strict | protocol types as discriminated unions |
| Bundler / dev server | Vite | static output, dev proxy for the WebSocket |
| UI | Preact (+ signals) for forms and lists; hand-written DOM/canvas for the stream screen | small, and the stream screen must not re-render on every state tick |
| Unit tests | Vitest in Node | protocol core is DOM-free |
| Browser tests | Playwright (Chromium; WebKit when available) | WebCodecs, pointer lock, touch |
| Lint / format | Biome | one tool |
| Package manager | pnpm (present at `/opt/homebrew/bin/pnpm`, Node 26) | |
| QR | `BarcodeDetector` when available, bundled `jsqr` fallback | no CDN script |
| Routing | hash routes | server has no SPA fallback |

No global state library. No CSS framework; one stylesheet with CSS variables.

### 2.2 Directory layout

```
web/
  PLAN.md                     this file
  docs/PROTOCOL.md
  docs/LEGACY_CLIENT_NOTES.md
  package.json  pnpm-lock.yaml  vite.config.ts  tsconfig.json  biome.json
  index.html                  unregisters stale service workers, mounts app
  public/                     manifest.webmanifest, icons
  src/
    protocol/                 DOM-free. messages.ts (types), codec.ts (parse/serialize),
                              auth.ts (HMAC via WebCrypto, mutual verify),
                              frames.ts (MC/MM header, map frame), h264.ts (NAL scan,
                              SPS bytes, codec string), capabilities.ts
    transport/                socket.ts (WebSocket wrapper, text/binary split, ACK),
                              handshake.ts (HELLO→AUTH/PAIR state machine),
                              heartbeat.ts, reconnect.ts, endpoint.ts (origin→ws URL)
    session/                  session.ts (mode, video state, screen/world state,
                              timed notification, hibernation), resolution.ts
                              (requested size policy), settings.ts, storage.ts
    video/                    decoder.ts (WebCodecs lifecycle), queue-policy.ts,
                              renderer.ts (canvas sizing/letterbox), stats.ts
    input/                    keyboard.ts, pointer.ts (pointer lock, drag look,
                              click/long-press), touch-pads.ts (joystick, buttons),
                              look-coalescer.ts, move-vector.ts, screen-mode.ts
    ui/                       app.tsx (router), login/, picker/, stream/ (stream
                              screen shell, overlays, palette, hotbar), chat/,
                              settings/, map/, components/
    platform/                 visibility.ts, wake-lock.ts, fullscreen.ts,
                              notifications.ts, tab-lock.ts, qr.ts
  test/
    unit/                     vitest
    browser/                  playwright
    fixtures/                 recorded sessions (json lines + AU blobs)
  tools/
    record-session.ts         Node client: connects to a real mod, records fixture
    probe.ts                  Node client: auth + frame counter (manual test aid)
    replay-server.ts          fake mod for dev: serves fixture over ws://
```

Build output is `web/dist/`. Gradle copies it into the jar as `web/`.

### 2.3 Data flow

```
WebSocket ──text──▶ codec.parse ──▶ handshake ──▶ session (state)  ──▶ ui (Preact)
           └─binary─▶ frames.split ─┬─▶ ACK (immediately)
                                    ├─▶ MC header → resolution event
                                    └─▶ h264 AU → queue-policy → decoder → renderer(canvas)
input (keyboard/pointer/touch) ──▶ input/* ──▶ codec.serialize ──▶ WebSocket
```

### 2.4 Design rules that remove the two bugs

**Video and resolution**

- The canvas is created once per stream screen. Its backing store is set from
  `VideoFrame.displayWidth/Height`; its CSS box is computed by the renderer
  (`object-fit: contain` math done in JS so the same rect feeds click mapping).
- The decoder is created once, reconfigured only when the SPS NAL bytes differ
  from the last configured SPS, and recreated only after a WebCodecs error.
  Never on resize, never on `CLIENT_STATUS`.
- Frames are never dropped for "wrong resolution". Whatever the server sends is
  decoded and shown. A resolution header only updates the "server size" field.
- Requested resolution is a policy, not a render side effect: computed from the
  viewport at stream start, on orientation change, on settings apply, and on a
  debounced (500 ms) `ResizeObserver` event that changes either axis by more than
  10 % **and** results in a different even size. Sending it does not touch the
  decoder.
- `ACK` is sent in the socket message handler before any decode work.
- Queue policy as in Flutter (max 3, drop deltas, reset after 12 drops or a
  key-while-full), but "reset" means flush and wait for key plus
  `REQUEST_KEYFRAME`; it does not destroy the decoder.

**Screen mode and ESC**

- The palette and screen-mode pointer mapping are gated on `SCREEN_STATE.isOpen`
  only. Pointer kind selects the default control layout, nothing else.
- Keyboard uses `KeyboardEvent.code`: `KeyW/A/S/D`, `Space`, `ShiftLeft/Right`,
  `KeyQ/E/F`, `Digit1..9`, `Arrow*`, `Escape` (`SCREEN_KEY` down and up when a
  screen is open). Keys are ignored while a text input has focus. All keys are
  released on blur, visibility hidden, hibernation, mode change, disconnect.

## 3. Milestones

Each milestone ends with the listed acceptance checks passing and a short entry
in `web/CHANGELOG.md`. Effort is an estimate in focused sessions.

### M0. Baseline and contract (1 session) — done

1. Record the branch, working-tree changes and protocol baseline without committing
   user work. Preserve an inspectable diff.
2. Scaffold `web/` (Vite + TS + Preact + Vitest + Playwright + Biome), empty
   app that renders "MonkeyCraft" and passes lint/test/build.
3. `tools/record-session.ts`: connects to the Prism instance, authenticates with
   the saved password, sends `CLIENT_STATUS`, records 30 s of JSON and binary
   messages into `test/fixtures/<name>/`. Record one streaming session, one with
   an inventory screen open, one hibernation transition.
4. CI: add a `web` job to `.github/workflows/build.yml` (install, lint, test,
   build, upload `dist`). Do not wire it into the jar yet.
5. Move `web-client-handoff/` to `doc/archive/web-client-handoff/` with a note
   that it is superseded. (Done in the plan PR.)

Acceptance: `pnpm lint && pnpm test && pnpm build` green locally and in CI; at
least one recorded fixture with ≥ 200 access units.

### M1. Protocol core, Node-testable (2 sessions) — done

`src/protocol`, `src/transport`, `src/session` without UI.

- Message types and parsers for every type in `docs/PROTOCOL.md`; unknown types
  tolerated.
- Auth: HMAC-SHA256 via `crypto.subtle`, mutual verification of `AUTH_OK.signature`
  (reversed salt order), PAIR flow with 180 s client timer, legacy
  `AUTH_RESPONSE {success:true}` tolerated.
- Handshake state machine driven by injected socket; tests replay fixtures and
  golden-check every outgoing message.
- Frame splitter: `MC` header, `MM` map frame, bare AU; NAL scan; SPS bytes;
  codec string from SPS.
- Heartbeat 3 s / 5 s with visibility pause; reconnect 1/2/4 s; counter reset on
  `HEARTBEAT_ACK`; `1006` handled.
- Session reducer: mode, videoState, screen/world state, timed notification
  (both key spellings), hibernation, capabilities.
- `tools/probe.ts`: authenticates against the real mod, sends `CLIENT_STATUS`,
  prints frames/s and header sizes for 20 s. Replaces the ad-hoc probe script.

Acceptance: unit coverage on `protocol/` and `transport/` ≥ 90 % lines; probe
runs against the Prism instance and reports ≥ 8 fps at the requested size.

### M2. Video pipeline (2 sessions) — done (10-minute soak pending: the test instance rides continuously)

`src/video` plus a bare stream page (canvas only, no controls).

- Decoder lifecycle per section 2.4; `isConfigSupported` gate with a clear
  unsupported message.
- Queue policy with tests; stats counters (received, decoded, dropped, errors,
  keyframe requests, queue size, measured fps) exposed to a debug overlay
  toggled by `?debug=1`.
- Renderer: single canvas, backing size from frames, contain-fit rect exposed
  for input mapping, devicePixelRatio respected.
- Playwright test: feed a fixture's AUs through the decoder in Chromium, assert
  decoded count and that resizing the viewport 20 times causes zero decoder
  recreations and zero `CLIENT_STATUS` beyond the debounced policy.

Acceptance: 10 minutes continuous video on the Prism instance in desktop Chrome
via HTTPS Serve with no reconnect; window resize and browser zoom never blank
the picture; console shows one decoder configure per SPS change.

### M3. Stream screen and input (2–3 sessions) — done (letterbox click check on the pause menu pending)

- Keyboard map, pointer lock mouse look (fallback to drag), click and right
  click, wheel to change hotbar slot, touch joystick / look pad / jump / shift /
  hotbar, long-press right click.
- Screen mode: `SCREEN_CLICK`/`SCREEN_HOVER` (hover throttled to 30 Hz) mapped
  over the renderer rect; ESC palette with ESC (down+up), shift toggle,
  click-mode chips; verify the letterbox inconsistency on the pause menu and add
  compensation if needed.
- Overlays: reconnecting, hibernation, waiting for video, decoder unsupported,
  timed countdown, nudge banner.
- Control layout auto/touch/mouse; hand-off to server picker on `MENU`.
- Wake Lock while streaming; fullscreen toggle; orientation lock where allowed.

Acceptance: both original bugs verified fixed on desktop Chrome and Android
Chrome (ESC palette visible whenever a screen is open regardless of last input
device; no reconnect loop during resize). Inventory drag-drop works.

### M4. Login, pairing, chat, picker, settings, map (2–3 sessions) — done

- Login: origin default with saved override, password/pair modes per
  `login_auth_policy`, QR scan (BarcodeDetector / jsqr), pairing code card with
  countdown, all error messages from `LEGACY_CLIENT_NOTES.md`.
- Storage: new namespace `monkeycraft.*`. No import of the Flutter `flutter.*`
  keys; users pair or enter the password once. Password stays in localStorage
  (unchanged threat model; revisit later).
- Tab lock via Web Locks: second tab shows "already open in another tab".
- Chat: subscribe lifecycle, segments renderer (colour, styles, click/hover
  events, `monkeycraft://` and OpenAudioMC links), banners, player count/list.
- Server picker, settings (all fields; apply sends `CLIENT_STATUS`, no reconnect),
  map screen (MM frames, projection as-is, `MAP_INTERACT`).
- Web Notifications for `NUDGE` when the tab is hidden.

Acceptance: feature checklist in section 5 all ticked on desktop Chrome and
Android Chrome; Safari desktop for login/chat at least.

### M5. Packaging, switch-over, cleanup (1 session)

- `mods/26.2/build.gradle`: copy `web/dist` instead of
  `flutter/monkeycraft/build/web`; require a built browser bundle for distributable JARs.
- `mods/26.2/build-and-deploy.sh`: replace `flutter build web` with
  `pnpm --dir web install --frozen-lockfile && pnpm --dir web build`.
- `.github/workflows/build.yml`: the 26.2 job builds `web` before Gradle so the
  released jar contains the client. `release.yml` likewise.
- A historical plan deleted `.github/workflows/pages.yml`; the current roadmap P4 adds a manual-only Pages workflow. It builds and verifies the project-path artifact by default, and deploys only with explicit `publish=true`. The Mod JAR keeps its default web artifact; this round’s Pages artifact is not published.
- `index.html` unregisters `flutter_service_worker.js` and clears caches once.
- Server change, non-protocol, approved: send `Cache-Control: no-cache` for
  `index.html` in `HttpOrWebSocketChannel` so a cached index never points at
  vanished hashed assets.
- Docs: `AGENTS.md` (build commands, key files), `doc/PROJECT_STRUCTURE.md`,
  `doc/FLUTTER_CLIENT.md` web section replaced by a pointer to `web/`,
  `doc/WEB_TAILNET_PLAN.md` step 5 marked done.
- Flutter: remove the web target from scripts only. Do not delete Dart code.

Acceptance: `build-and-deploy.sh` produces a jar whose `/` serves the new client
on the Prism instance; `curl -sI https://<serve-url>/` shows the new index.

### M6. Mobile browser proof (1–2 sessions, with the user's devices)

Per `doc/WEB_TAILNET_PLAN.md` step 6: iPhone Safari and home-screen app,
Android Chrome and home-screen app, over Tailscale Serve. Measure fps at the
medium preset, background/lock resume, 30 minutes without reconnect. Record
findings in `web/docs/MOBILE_RESULTS.md`. This gates browser acceptance and roadmap P4; native apps continue to be maintained.

Estimated total: 11–14 sessions.

## 4. Verification strategy

| Layer | How | Where |
|---|---|---|
| Protocol | golden tests against recorded fixtures; every outgoing message asserted | `test/unit` |
| Decoder | Playwright, Chromium, fixture AUs | `test/browser` |
| Live | `tools/probe.ts` against the Prism instance; manual checklist | `web/docs/TEST_CHECKLIST.md` (written in M3) |
| Regression of the two bugs | Playwright: toggle `SCREEN_STATE` and pointer kinds, assert palette; resize storm, assert decoder configure count | `test/browser` |

Manual test environment: the Prism "ImagineFun Add-Ons" instance with the 26.2
jar, reached through `tailscale serve --bg --https=10800 http://127.0.0.1:9600`.
Do not test WebCodecs over plain `http://127.0.0.1`; secure-context behaviour on
loopback differs by browser and confuses results.

## 5. Feature checklist (parity with Flutter web)

- [ ] Login with origin default, editable server, password, remember toggle
- [ ] Pair mode with code card and countdown; `PAIR_FAILED` messages
- [ ] QR scan by camera and by image file
- [ ] Credential vault keyed by `keyId`; invalid-signature eviction
- [ ] Stream: video, fps setting, colour mode, resolution preset, data saver (capability-gated)
- [ ] Keyboard, mouse (pointer lock), touch controls, control layout setting
- [ ] Screen mode: click, hover, ESC, shift, click-mode chips; inventory drag-drop
- [ ] Hotbar select by digit, wheel, touch grid; Q/E/F
- [ ] Hibernation overlay, waiting overlay, reconnecting overlay, decoder unsupported message
- [ ] Timed notification countdown; nudge banner; Web Notification when hidden
- [ ] Chat: cached + live, segments, click/hover events, commands, denied messages, banners, player count/list
- [ ] Server picker: list, direct connect, resource pack toggle, join errors, hand-off
- [ ] Map: MM frames, position pill, controls, ride sheet
- [ ] Settings: all fields persisted; device name in AUTH
- [ ] OpenAudioMC link opens in a new tab
- [ ] Reconnect 1/2/4 s then login; server `DISCONNECT`; `1006` after background
- [ ] Tab lock; service-worker cleanup

## 6. Risks

| Risk | Mitigation |
|---|---|
| WebKit WebCodecs behaviour differs (Safari 16.4+) | M2 Playwright WebKit run where possible; M6 on real iPhone; keep decoder wrapper thin |
| Letterboxed-screen click offset | explicit verification item in M3 |
| IDR/P alternation doubles bandwidth | client-side nothing to do; note as a candidate server fix outside this plan |
| Cached `index.html` after jar update | `Cache-Control: no-cache` on index.html in M5; hashed asset names regardless |
| Pointer lock unavailable on iOS | drag look fallback is the touch path anyway |
| Two tabs racing for the single session | Web Locks tab lock |
| Fixture drift when the server changes | fixtures are re-recorded by a tool, not hand-edited |

## 7. Decisions taken (2026-09-16)

1. Current working tree committed on a branch and opened as a PR, together with this plan.
2. `web-client-handoff/` moved to `doc/archive/web-client-handoff/`.
3. `Cache-Control: no-cache` on `index.html` approved for M5.
4. GitHub Pages workflow deleted.
5. No import of Flutter localStorage keys.

Everything else in this plan proceeds without further sign-off.
