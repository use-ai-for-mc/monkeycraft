# Changelog

## 2026-09-19 — Android Chrome notifications and resume

- Use a scoped notification Service Worker for Android Chrome and resolve its icon under the build base; preserve unrelated workers and caches. Keep user-gesture permission requests and avoid an extra page sound after a system notification.
- Pause reconnect retries while hidden, resume when visible, and ignore stale retries after disconnect or a new connection. Move the reminder banner below the game toolbar.
- Web unit suite: 160 passed. Chromium: 20 passed; WebKit: 19 passed. Pages project: 19 passed; Pages root focused suite: 4 passed. Notification-display tests explicitly skip when the headless browser denies the requested permission.
- Actual Android Chrome133/API36 emulator verified live WSS video, rotation, native system notifications and notification tap, Home input release and resume. This is not physical-phone, audible-sound or public Pages evidence. See [runtime evidence](../doc/tailscale-integration/evidence/2026-09-19-android-browser.md).


## P1 browser reminder close-out (2026-09-18)

- Settings now has a user-gesture reminder enable action and a test sound. It requests notification permission only from that action and reports when the browser blocks it.
- `NUDGE.sound` now controls page audio. Hidden-tab system notifications suppress the page chime to avoid a second audible alert; `sound: false` still keeps the banner and eligible system notification.
- Timed alerts now replace prior schedules on update, cancel on an explicit null status, fire once per server deadline, and recover correctly after reconnect or a visible-page return.
- Touch movement and hold buttons release their input when the page loses focus or becomes hidden; keyboard input also releases during reconnect.
- This round: Biome, TypeScript, 139 Vitest assertions, Vite production build, and 17 Chromium Playwright replay tests passed. The optional live-Minecraft and soak tests are explicit opt-ins.

## M2 close-out, M3, M4 (2026-09-16)

- Replay server (`tools/replay-server.ts`): plays a fixture over ws:// with the real
  handshake, ACK backpressure, per-connection `/log`, and `/replay` test controls, so
  Playwright drives the whole app without Minecraft.
- Resize-storm and browser-zoom regression tests (one decoder, ≤ 3 CLIENT_STATUS).
- Input: keyboard via `KeyboardEvent.code` (WASD, Space, Shift, Q/E/F, arrows, digits,
  Escape), release-all on blur/hide/hibernation/screen change; Pointer Lock mouse look
  with drag fallback, clicks, wheel hotbar; touch drag look, tap, long-press right
  click; joystick with hysteresis, jump/sneak hold buttons, hotbar grid.
- Screen mode: SCREEN_CLICK/SCREEN_HOVER over the picture rect, ESC palette gated on
  SCREEN_STATE only (regression test), shift modifier, click-mode chips for touch.
  Verified live: E opens the inventory and the palette appears; Escape closes it.
- Chat, settings (apply without reconnect), server picker, map mode with ride sheet,
  QR scan (BarcodeDetector / bundled jsQR), pairing countdown, timed countdown,
  Web Locks tab lock, Web Notifications while hidden, Wake Lock, fullscreen.

## M1 + first slice of M2 (2026-09-16)

- Typed protocol messages and a tolerant codec (`src/protocol/messages.ts`, `codec.ts`),
  golden-checked against every recorded fixture.
- Handshake state machine with mutual `AUTH_OK` verification and the PAIR flow;
  heartbeat (3 s idle / 5 s ack, paused while hidden); reconnect 1/2/4 s.
- `Connection`: socket + handshake + immediate `ACK` + heartbeat, fake-socket tests.
- Session reducer, requested-size policy (viewport × DPR × preset, debounced,
  hysteresis), letterbox math, settings and credential vault (`monkeycraft.*` keys).
- `SessionController`: reconnect loop, `CLIENT_STATUS` sync, video fan-out, forget
  rejected passwords.
- Video: decode queue policy, `H264Decoder` (one decoder, reconfigure only on SPS
  change), `CanvasRenderer`.
- UI: login page (origin default, password/pair modes, pairing code) and a bare
  stream page with hibernation/reconnect overlays and a `?debug=1` stats overlay.
- Fixtures: `hibernating`, `streaming-360x640` (IDR/P alternation),
  `streaming-360x640-datasaver`, `inventory-360x640`. The recorder can wait for
  `ACTIVE` and drive an inventory open/close.
- Browser tests: decoder driven with fixture access units (single configure, zero
  errors on all three video fixtures); live end-to-end test through the Vite proxy
  (`MONKEYCRAFT_LIVE=1`), which passed against the 26.2 mod.

## M0 (2026-09-16)

- Scaffold: Vite + TypeScript + Preact, Vitest, Playwright, Biome, pnpm.
- `src/transport/endpoint.ts`: server address rules (same as the Flutter client).
- `src/protocol/auth.ts`: HMAC-SHA256 handshake via WebCrypto, mutual verification.
- `src/protocol/frames.ts`, `src/protocol/h264.ts`: binary demux, NAL scan, SPS codec string.
- `tools/probe.ts`, `tools/record-session.ts`: live probe and fixture recorder (Node, no deps).
- `index.html` unregisters the old Flutter service worker.
- CI job `web` in `.github/workflows/build.yml`.
