# What the Flutter client does, and what not to copy

> 2026-09-19 用户最新决定：浏览器改为 Flutter 与 iOS/Android 共用界面和业务逻辑，仅浏览器适配分层。独立 `web/` 停止继续开发验收及发布，保留为行为参考与测试资产。本文后续有关独立重写、Flutter Web 放弃或冻结的描述属于历史，不再作为当前实施指令。当前执行见 `doc/PRODUCT_ROADMAP_EXECUTION.md`。
The Flutter app under `flutter/monkeycraft/` is frozen and kept as a behavioural
reference. This file records the behaviours the web client must reproduce and the
defects it must not. File references are to `flutter/monkeycraft/lib/`.

## Behaviours to keep

| Area | Behaviour | Source |
|---|---|---|
| Connect timeouts | 5 s connect, 4 min auth (pairing needs a human) | `auth/login_screen.dart` |
| Auth mode default | password if one is saved for this `keyId`; else pair if the host is an IP literal in loopback/RFC1918/link-local/CGNAT/ULA; else password | `auth/login_auth_policy.dart`, `auth/pairing_eligibility.dart` |
| Credential vault | `keyId -> {password, lastServer, lastSeen}`, 8 entries LRU; lookup by `keyId` from HELLO overrides typed password; drop entry on "invalid signature" | `auth/credential_store.dart`, `stream/stream_proxy.dart` |
| Server field on web | defaults to the page origin (`https:` to `wss:`, `http:` to `ws:`); bare `host:port` to `ws:`; bare hostname to `wss:` | `auth/web_origin_server.dart`, `stream/transport/server_url.dart` |
| QR payload | the password verbatim, no wrapper | `ui/PasswordQrOverlay.java` |
| Heartbeat | 1 s tick; `HEARTBEAT` after 3 s silence; lost after 5 s without ack; paused while hidden | `stream/stream_proxy.dart` |
| Reconnect | 1 s, 2 s, 4 s, then back to login; auth failure goes straight to login; retry counter reset on each `HEARTBEAT_ACK` | `stream/session_controller.dart` |
| ACK | sent synchronously on receipt of every video frame, never for map frames | `stream/stream_proxy.dart` |
| Decode queue | max queue 3; drop deltas while over; reset and request keyframe on key-while-full or after 12 consecutive drops; wait for key after any reset or error | `stream/video/decode_queue_policy.dart` |
| WebCodecs config | `optimizeForLatency: true`, `hardwareAcceleration: "no-preference"`, no `description`, codec from SPS bytes, `isConfigSupported` before use; chunk timestamp `frameIndex * 1e6/fps` | `stream/video/web_h264_decoder.dart` |
| Look sensitivity | 0.12° per logical px, 16 ms coalescing, no empty flushes; mouse look starts after ~28 px drag; touch looks immediately; touch long-press 200 ms is right click | `stream/widgets/look_pad.dart`, `stream/look_delta_coalescer.dart` |
| Joystick | hysteresis 0.35 press / 0.25 release per axis, edge-triggered INPUT | `stream/game_input_controller.dart` |
| Hotbar keys | digits 1–9 select slots; Q/E/F are momentary INPUT press then release after 50 ms | `stream/screens/stream_screen.dart` |
| Screen mode | when `SCREEN_STATE.isOpen`, pointer events map to `SCREEN_CLICK`/`SCREEN_HOVER` normalised over the displayed video rect; ESC palette with ESC, shift toggle, left/right/hover click mode | `stream/widgets/screen_controls.dart` |
| Chat | `SUBSCRIBE_CHAT` on open (5 s wait for cache), `UNSUBSCRIBE_CHAT` on close, 100-message rolling cap, `/` text goes to `RUN_COMMAND`; player count polled every 5 s only when `PLAYER_LIST` capability present; player list fetched on tap | `chat/chat_screen.dart` |
| Chat banners | hibernation message > immediate body > nudge, each dismissible | `chat/chat_screen.dart` |
| Server picker | shown when `WORLD_STATE.phase != IN_WORLD`; `LIST_SERVERS`, direct-connect field, accept-resource-pack toggle default on; `JOIN_RESULT.error` in a snackbar | `serverpicker/server_picker_screen.dart` |
| Hand-off to picker | when `WORLD_STATE.phase == MENU` during streaming, keep the socket and switch screens | `stream/screens/stream_screen.dart` |
| Hibernation | release all inputs, tear down decoder, optionally auto-open chat; on exit request keyframe and resume | `stream/screens/stream_screen.dart` |
| Settings | fps 1–20 (default 10), colorMode 0–3, resolution preset low/medium/high (scale 0.5/0.75/1.0, max edge 640/960/1280), invert look Y (default on), auto-switch ride/chat, auto-face movement, data saver (gated on capability), control layout auto/touch/mouse, device name | `stream/stream_settings.dart` |
| Requested resolution | viewport × devicePixelRatio × scale, long edge capped, rounded down to even, min 2 | `stream/stream_resolution.dart` |
| Web keep-alive | when the window is blurred but visible, keep painting | `platform/web_frame_keep_alive_web.dart` |
| OpenAudioMC | open the `https://session.openaudiomc.net/...` link in a new tab | `audio/openaudiomc_service_web.dart` |
| Map screen | parse `MM` frames; top-down video; tap-to-entity within 3 blocks; `MAP_INTERACT` on rideable | `map/map_screen.dart` |

## Defects not to reproduce

1. **Resolution renegotiation from layout.** `stream_screen.dart` schedules a full
   restart from inside `build` whenever `MediaQuery.size` moves more than 10 px,
   with no coalescing. Every restart resets the decoder, blanks the video behind a
   "Waiting for correct resolution" overlay, and sends `CLIENT_STATUS`. Combined
   with the sticky last-header size in `stream_proxy.dart` and the server only
   sending the header on the first IDR after a reset, this is the reconnect loop.
   The web client sizes the canvas from decoded frames and only renegotiates on
   explicit events with debounce and hysteresis.
2. **Frame acceptance gate.** `session_controller.dart` drops every frame until a
   header matching the *requested* size arrives, and re-asserts the request without
   asking for a keyframe. Drop the gate entirely; decode what arrives.
3. **Fire-and-forget decoder resets.** `decoder.reset()` is not awaited; frames
   during the gap are discarded and not counted. Make decoder lifecycle explicit and
   awaited, and never recreate the decoder on resize.
4. **ESC palette gated on pointer kind.** On web `_autoPreferTouch` flips to false
   after the first mouse click, hiding the palette even though a screen is open.
   Gate the palette on `SCREEN_STATE` only.
5. **Keyboard.** Shift never fires (`keyLabel` is `"Shift Left"`, matched against
   `"ShiftLeft"`); Escape, Q, E, F, arrows are unbound. Use `KeyboardEvent.code` and
   bind everything the server understands.
6. **ESC key-up never sent**, only `pressed:true`.
7. **Chat and map buttons are not excluded from the look pad**, so clicking them
   also sends a game click.
8. **`SCREEN_HOVER` on every mouse move**, unthrottled.
9. **Saved server address unreachable on web**: always overwritten by the page
   origin. Keep origin as the default but let a saved override win.
10. **Password in plaintext localStorage** by design; unchanged for now (see plan,
    section on storage) but do not mirror into two stores.
11. **Platform-view leak**: a new `<canvas>` and view registration per decoder
    instance. One canvas for the life of the screen.
12. **Every settings change tears down and re-authenticates the socket.** Apply
    settings by sending `CLIENT_STATUS`; reconnect only when the endpoint changes.
13. **Map projection** hard-codes FOV 70° and camera height 20 and ignores yaw.
    Port as-is for parity and mark as known.
14. **`jsQR` loaded from a CDN `<script>`.** Bundle it.
15. **36 MB of dead WASM Tailscale** shipped in every web build. Do not ship.
16. **`flutter_service_worker.js`** may still control the origin after the switch.
    The new `index.html` must unregister any service worker and clear caches once.

## Legacy Flutter Web surface (not native App deprecation)

This historical list applies only to the abandoned Flutter Web target. Native iOS/Android Tailscale, park audio, MPEG-TS relay, Live Activity and notifications remain maintained product capabilities under `doc/PRODUCT_ROADMAP_2026-09.md`. Do not delete them using this list.

`SCREEN_TAP`, `ENTER_CHAT`/`EXIT_CHAT`, `LEAVE_WORLD` (no UI), `PLAYER_POSE`
(parsed, unused), `HIBERNATION_STATUS` model, in-page Tailscale transports
(`stream/tailscale/`, `stream/transport/tailscale_*`, `ws_frame.dart`), MPEG-TS
relay (`stream/mpeg_ts_muxer.dart`, `stream/proxy/video_relay_io.dart`), MCParks and
OpenAudioMC headless WebViews, Live Activity, iOS timed notifications, chat
background picker, `web-client-handoff/` (previous, superseded plan).
