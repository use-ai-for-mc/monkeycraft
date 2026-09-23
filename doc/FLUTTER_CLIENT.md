# Flutter Client Architecture

The Monkeycraft Flutter client (`flutter/monkeycraft/`) connects to the Minecraft mod via WebSocket to provide remote gameplay. iOS, Android, and the production browser client share its UI and business logic, with conditional platform adapters. The TypeScript / Preact app in `web/` is retained only for reference and test fixtures; see [the product roadmap](PRODUCT_ROADMAP_2026-09.md).

## Audio ownership protocol

Authenticated `INFO` packets use `{ "type": "INFO", "title": "openaudiomc", "data": { "active": true, "connected": false } }`. Native OpenAudioMc sends `active` before loading a session and releases it after page teardown, including failed initial loads or refreshes. `connected` describes the detected page state; neither field guarantees audible output. Stream/chat transport recovery reports current state again. Explicit stream exit releases audio before closing the transport.

All four Mod versions relay INFO through the existing `MonkeycraftApi.INFO_PACKET` on the Minecraft thread, checking that the sender is still the authenticated session. Inputs require a nonempty string title of at most 64 characters, object data, and a message of at most 8192 characters. This extends the existing message/API rather than adding a capability. Older receivers can ignore it, so automatic desktop audio handoff requires the matching receiver and provider update.

ImagineMoreFun 26.2 suppresses desktop session creation/retry while native `active` is true, preserving prior connection intent and volume. An explicit false releases it; a socket loss does not. External browser audio does not claim ownership. See [audio lifecycle and acceptance limits](AudioPlayer.md).

## Directory Structure

```
flutter/monkeycraft/lib/
├── main.dart                         # App entry point
├── auth/                             # Authentication screens
│   ├── login_screen.dart             # Connection setup screen
│   └── qr_scan_screen.dart           # QR code scanner for password
├── chat/                             # Chat functionality
│   ├── chat_screen.dart              # In-game chat interface
│   └── chat_models.dart              # Chat message types
├── platform/                         # Platform capabilities and file helpers
├── stream/                           # Streaming functionality
│   ├── screens/
│   │   ├── stream_screen.dart        # Main game streaming screen
│   │   └── stream_settings_screen.dart  # Stream quality settings
│   ├── widgets/
│   │   ├── virtual_joystick.dart     # Movement joystick
│   │   ├── look_pad.dart             # Camera look control
│   │   ├── jump_button.dart          # Jump action button
│   │   ├── shift_button.dart         # Sneak action button
│   │   ├── hotbar_selector.dart      # Hotbar slot selector
│   │   ├── screen_controls.dart      # Screen touch controls
│   │   └── video_surface.dart        # Native Texture / Web canvas
│   ├── video/                        # Shared decoder interface + WebCodecs
│   ├── stream_proxy.dart             # WebSocket communication hub
│   ├── session_controller.dart       # Session state management
│   ├── game_input_controller.dart    # Movement/input state machine
│   ├── hardware_h264_decoder.dart    # Native video decoder bridge
│   ├── stream_settings.dart          # Settings persistence
│   ├── stream_resolution.dart        # Resolution calculation
│   ├── look_delta_coalescer.dart     # Look input batching
│   └── mpeg_ts_muxer.dart            # H.264 to MPEG-TS conversion
├── shared/                           # Shared utilities
│   ├── protocol_models.dart          # Protocol types (ClientMode, VideoState)
│   ├── hibernation_models.dart       # Hibernation state types
│   ├── app_settings.dart             # Global app settings
│   └── keyboard_prewarmer.dart       # Keyboard warmup utility
├── notifications/                    # Notification handling
│   ├── notification_models.dart      # Notification types
│   ├── timed_notification_service.dart
│   ├── timed_notification_coordinator.dart
│   ├── ios_timed_notification_scheduler.dart
│   └── live_activity_service.dart    # iOS Live Activity
└── audio/
    └── openaudiomc_service.dart      # OpenAudioMC integration
```

---

## Screens

### LoginScreen (`screens/login_screen.dart`)
Entry point for the app. Handles:
- Host/port/password input
- QR code scanning for password
- Credential persistence via SharedPreferences
- WebSocket connection establishment
- Connection timeout handling

### StreamScreen (`screens/stream_screen.dart`)
The main gameplay screen. Responsibilities:
- Video stream display via hardware H.264 decoder
- Touch control overlay (joystick, buttons, look pad)
- App lifecycle management (pause/resume on background)
- Hibernation mode handling
- Notification display
- Command palette for executing Minecraft commands
- Settings navigation
- Orientation control

**Key state:**
- `_decoder`: Hardware H.264 video decoder
- `_input`: Game input controller
- `_sessionController`: Session state controller
- `_textureId`: Native texture ID for video display

### ChatScreen (`screens/chat_screen.dart`)
Dedicated chat interface:
- Displays incoming chat messages from server
- Sends chat messages (non-commands)
- Handles chat denied events
- Auto-scrolls to latest messages
- Rich text rendering with click/hover events

### QrScanScreen (`screens/qr_scan_screen.dart`)
Legacy QR scanner. New pairing uses an empty password + `/monkey accept` instead of the title-screen QR overlay.

### StreamSettingsScreen (`stream/screens/stream_settings_screen.dart`)
Configuration UI for:
- Resolution preset (Low/Medium/High)
- Color mode (Normal/High Perf/Retro/Grayscale)
- FPS (1-20)
- Auto-switch to chat during hibernation
- Auto-face movement (automatically face movement direction)

---

## Services

### StreamProxy (`stream/stream_proxy.dart`)
Central communication hub between Flutter app and Minecraft mod.

**WebSocket Protocol:**
| Direction | Type | Description |
|-----------|------|-------------|
    | Server→Client | `HELLO` | Authentication challenge with salt; `pairing: true` when `/monkey accept` is available; `keyId` names the current long-term password (capability `KEY_ID`) |
| Client→Server | `AUTH` | HMAC-SHA256 authentication response, or `{mode:"PAIR"}` to start pairing. All AUTH variants (pair, password, post-pair) may carry optional `deviceName` (user-editable in app settings, defaults to the device model) and `deviceModel`; the mod stores them as last-phone info and shows the name on `/monkey` and in the pairing prompt. Older mods ignore these fields |
| Server→Client | `PAIR_WAITING` | 8-character pairing code + `ttlMs` (phone displays it; PC runs `/monkey accept CODE`) |
| Server→Client | `PAIR_OK` | Long-term password after `/monkey accept`; phone stores it and continues with HMAC `AUTH` |
    | Server→Client | `AUTH_OK` / `AUTH_RESPONSE` | Auth result; `AUTH_OK` carries `protocolVersion` + `capabilities[]` (feature tokens like `PLAYER_LIST`, `DATA_SAVER`, `PAIRING`, `KEY_ID`) the client gates optional features on |
| Server→Client | Binary | H.264 video access unit (with optional 6-byte resolution header) |
| Client→Server | `ACK` | Video frame acknowledgment |
| Client→Server | `CLIENT_STATUS` | Sync mode/resolution/fps/autoFaceMovement/dataSaver (`dataSaver` lengthens the encoder GOP to cut bandwidth; gated on the `DATA_SAVER` capability) |
| Client→Server | `INPUT` | Key press/release |
| Client→Server | `LOOK_DELTA` | Camera movement |
| Client→Server | `CLICK` | Mouse click (left/right) |
| Client→Server | `SCREEN_CLICK` | Click on screen overlay |
| Client→Server | `SCREEN_KEY` | Key press for screen overlay |
| Client→Server | `RUN_COMMAND` | Execute Minecraft command |
| Client→Server | `HOTBAR_SELECT` | Select hotbar slot |
| Client→Server | `SEND_CHAT` | Send chat message |
| Client→Server | `ENTER_CHAT` / `EXIT_CHAT` | Chat mode toggle |
| Client→Server | `GET_PLAYER_COUNT` | Request online player count only (polled for the indicator) |
| Client→Server | `GET_PLAYER_LIST` | Request online player account names (on tap-to-view) |
| Client→Server | `HIBERNATION_PING` | Keep-alive during hibernation |
| Client→Server | `REQUEST_KEYFRAME` | Request I-frame |
| Server→Client | `TIMED` | Scheduled notification |
| Server→Client | `NUDGE` | Immediate notification |
| Server→Client | `HIBERNATION_START/END/STATUS/MESSAGE` | Hibernation events |
| Server→Client | `COMMAND_DENIED` | Command blocked |
| Server→Client | `DISCONNECT` | Server-initiated disconnect |
| Server→Client | `CHAT_MESSAGE` | Incoming chat |
| Server→Client | `CHAT_DENIED` | Outgoing chat blocked |
| Server→Client | `PLAYER_COUNT` | Online player count only (`count`) |
| Server→Client | `PLAYER_LIST` | Online player account names in tab-list order (`count` + `players[]`); 26.2/26.1/1.21.11 honor server `tabListOrder` (staff on top), 1.19 is alphabetical |
| Server→Client | `SERVER_STATUS` | Server state broadcast |
| Server→Client | `HEARTBEAT` | Server heartbeat |
| Client→Server | `HEARTBEAT_ACK` | Heartbeat acknowledgment |

**Internal MPEG-TS Muxer:**
- Converts H.264 access units to MPEG-TS packets
- Used for local TCP server that feeds native video decoder

### SessionController (`stream/session_controller.dart`)
State machine managing the streaming session.

**SessionState:**
| Field | Type | Description |
|-------|------|-------------|
| `mode` | `ClientMode` | `streaming` or `chat` |
| `videoState` | `VideoState` | `active` or `hibernating` |
| `connected` | bool | WebSocket connection status |
| `foreground` | bool | App in foreground |
| `waitingForStream` | bool | Waiting for video frames |
| `resolutionMismatch` | bool | Frame resolution doesn't match expected |
| `timedNotification` | `TimedNotification?` | Active timed notification |

**Key Logic:**
- Frame time tracking for "waiting for stream" detection
- Heartbeat monitoring for connection health
- Automatic stream restart on resolution change
- Resolution mismatch handling (waits for correct resolution, drops mismatched frames)
- Hibernation state transitions
- Reconnection with exponential backoff (3 retries, ~7 seconds total). Embedded Tailscale sessions re-resolve a loopback bridge (`openBridge`) on each resume/retry instead of reusing a stale `ws://127.0.0.1` URL.

### GameInputController (`stream/game_input_controller.dart`)
State machine for movement input:
- Converts joystick offsets to WASD key events
- Hysteresis thresholds for press/release
- Manages jump (SPACE) and sneak (SHIFT) states
- `releaseAll()` to reset all keys

### HardwareH264Decoder (`stream/hardware_h264_decoder.dart`)
Platform channel bridge to native video decoder:
- `createDecoder(fps)`: Initialize decoder, returns texture ID
- `pushAccessUnit(bytes)`: Queue H.264 NAL unit for decoding
- `reset()`: Flush decoder state
- `dispose()`: Release native resources

Uses Flutter Texture widget to display decoded video.

### StreamSettings & StreamSettingsStore (`stream/stream_settings.dart`)
- `StreamSettings`: Data class for fps, colorMode, resolutionPreset, autoSwitchRideChat, autoFaceMovement, dataSaver
- `StreamSettingsStore`: Persistence via SharedPreferences

### LookDeltaCoalescer (`stream/look_delta_coalescer.dart`)
Batches look delta events to reduce network overhead while maintaining responsiveness.

---

## Data Models

### Protocol Models (`shared/protocol_models.dart`)

```dart
enum ClientMode { streaming, chat }
enum VideoState { active, hibernating }

class ServerStatus {
  final VideoState videoState;
  final String? message;
  final int? timedFireAtEpochMs;
  final String? timedTitle;
  final String? timedBody;
  final bool timedSound;
  final String? timedCountDownText;
}
```

### ChatMessage (`chat/chat_models.dart`)
```dart
class ChatMessage {
  final String sender;
  final String? senderUuid;
  final String message;
  final int timestamp;
  final bool isOutgoing;
  final List<ChatSegment> segments; // Rich text segments
}
```

### HibernationEvent (`shared/hibernation_models.dart`)
Sealed class hierarchy:
- `HibernationStart(message)` - Enter hibernation
- `HibernationEnd` - Exit hibernation
- `HibernationStatus(active, message)` - Status poll response
- `HibernationMessage(message)` - Update display message

### Notification Models (`notifications/notification_models.dart`)
- `TimedNotification`: Scheduled at specific epoch timestamp with countdown text
- `NudgeNotification`: Immediate notification

---

## Widgets

### VirtualJoystick (`stream/widgets/virtual_joystick.dart`)
Touch-controlled analog joystick:
- Reports normalized (-1 to 1) X/Y offsets
- Visual feedback with movable knob
- Used for WASD movement

### LookPad (`stream/widgets/look_pad.dart`)
Full-screen touch area for camera control:
- Reports yaw/pitch deltas
- Supports excluded regions (avoids UI elements)
- Tap detection for left-click
- Long-press detection for right-click
- Uses coalescer for efficient batching

### JumpButton / ShiftButton (`stream/widgets/jump_button.dart`, `stream/widgets/shift_button.dart`)
Simple press/release buttons with visual feedback.

### HotbarSelector (`stream/widgets/hotbar_selector.dart`)
- `HotbarToggleButton`: Expands/collapses hotbar panel
- `HotbarGrid`: 9-slot grid (3x3 portrait, 1x9 landscape)
- Sends `HOTBAR_SELECT` command on slot tap

---

## Platform-Specific Notes

### iOS
- Uses VideoToolbox for hardware H.264 decoding
- Native plugin in `ios/Runner/` handles decoder lifecycle
- **Live Activity**: Shows countdown timer on lock screen via `LiveActivityService`
  - Uses `live_activities` package
  - App Group: `group.com.chenweikeng.monkeycraft`
  - Activity ID: `timed_countdown`

### Android
- Uses MediaCodec for hardware H.264 decoding
- Native plugin in `android/app/` handles decoder lifecycle

### Browser client

The maintained browser product is [`web/`](../web/PLAN.md), bundled into the Mod from `web/dist/`. Flutter remains the iOS/Android product; its legacy web target is not the browser release artifact. Both clients share pairing/HMAC, protocol semantics and the single-session constraint. Browser HTTPS, sound permissions and background limitations are documented in [WEB_TAILNET_PLAN.md](WEB_TAILNET_PLAN.md).
