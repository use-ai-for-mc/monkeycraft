# Changelog

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
