# Flutter Web MVP status

## Done

- Flutter Web scaffolding under `flutter/monkeycraft/web/`.
- Platform capabilities + conditional imports so `dart:io`, Live Activity, Headless WebView, QR, and VideoRelay do not run on web.
- Shared `MonkeycraftVideoDecoder` / `VideoSurface`. Native still uses Texture + MethodChannel; web uses WebCodecs + canvas.
- Annex-B NAL helpers: IDR/SPS/PPS detection and `avc1.xxxxxx` codec string from SPS.
- Decode queue policy: drop deltas when `decodeQueueSize` is high; reset and `REQUEST_KEYFRAME` after sustained backlog or decoder error.
- Existing StreamScreen / MapScreen / chat / login reused. Desktop WASD/Space/Shift and 1–9 hotbar keys added.
- Unit tests for NAL parsing, queue policy, and physical keys.

## How to run

```bash
cd flutter/monkeycraft
flutter run -d chrome
```

Login Server field: `host:port` of the running MonkeyCraft mod. Password is the same as the mobile client. Serve from `http://localhost` so WebCodecs is a secure context and `ws://` is allowed.

## Known limits

- QR, native notifications, Live Activity, OpenAudioMC, and MCParks audio are no-ops on web.
- Chat custom background picker is hidden on web.
- GitHub Pages (`https://use-ai-for-mc.github.io/monkeycraft/`): CI workflow `.github/workflows/pages.yml` builds Flutter web with `--base-href /monkeycraft/` and deploys on `master`. Enable Pages → Source: GitHub Actions.
- HTTPS Pages + `ws://` LAN/localhost: Chrome may prompt for Local Network Access; Safari often blocks mixed `ws://`. Tailscale/`wss://` is the internet path.
- Firefox Android is out of scope.

## Live test (desktop Chrome, localhost)

Against a running 26.2 Mod at `127.0.0.1:9600` (`http://127.0.0.1:7357/`):

- Login + HMAC auth: `AUTH_OK` (`PLAYER_LIST`, `DATA_SAVER`).
- StreamScreen opens. Hibernation overlay shown while riding (video paused by the Mod, expected).
- Chat: cached + live messages, player count 83, player list dialog.
- Continuous H.264 decode not yet observed — Mod was hibernating (~4–5 min remaining). Retry when `SERVER_STATUS.videoState` is `ACTIVE`.

## Design notes

- Protocol unchanged. Frames still arrive as one Annex-B access unit per WebSocket binary message.
- `VideoDecoderConfig.description` is omitted so input stays Annex-B.
- Default codec `avc1.420028`; SPS bytes override if they differ.
