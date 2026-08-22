# Flutter Client Architecture

The Monkeycraft Flutter client (`flutter/monkeycraft/`) is a mobile app for iOS and Android that connects to the Minecraft mod via WebSocket to provide remote gameplay.

## Directory Structure

```
flutter/monkeycraft/lib/
├── main.dart                         # App entry point
├── auth/                             # Authentication screens
│   ├── login_screen.dart             # Connection setup screen
│   ├── pairing_payload.dart           # Versioned password + TLS pin parser
│   └── qr_scan_screen.dart            # Pairing QR scanner
├── chat/                             # Chat functionality
│   ├── chat_screen.dart              # In-game chat interface
│   └── chat_models.dart              # Chat message types
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
│   │   └── screen_controls.dart      # Screen touch controls
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
- QR code scanning for password and certificate SHA-256 pin
- Credential persistence via SharedPreferences
- WSS connection establishment with Pin-or-WebPKI certificate validation
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
Simple QR scanner using `mobile_scanner`. Version 2 pairing codes contain the password and the
SHA-256 fingerprint of the mod's persistent self-signed certificate. Legacy password-only codes
still parse, but cannot authorize an untrusted self-signed certificate.

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

Connections use WSS by default. A certificate is accepted when either:

1. Its SHA-256 fingerprint matches the value scanned from the pairing QR, or
2. The platform validates its public CA chain and hostname normally.

The first path covers direct LAN, Tailscale, raw TCP tunnels, and port forwarding. The second path
covers TLS-terminating services such as Cloudflare Tunnel, ngrok HTTP, and Tailscale Funnel. The
pin exception is installed on the connection's private `HttpClient`; it does not change certificate
validation for other app traffic.

**WebSocket Protocol:**
| Direction | Type | Description |
|-----------|------|-------------|
| Server→Client | `HELLO` | Authentication challenge with salt |
| Client→Server | `AUTH` | HMAC-SHA256 authentication response |
| Server→Client | `AUTH_OK` / `AUTH_RESPONSE` | Auth result; the client verifies the reciprocal HMAC before accepting `AUTH_OK`; it also carries `protocolVersion` + `capabilities[]` (including `TLS`) |
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
| Server→Client | `PLAYER_LIST` | Online player account names in tab-list order (`count` + `players[]`); 26.1/1.21.11 honor server `tabListOrder` (staff on top), 1.19 is alphabetical |
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
- Reconnection with exponential backoff (3 retries, ~7 seconds total)

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

### Unsupported Platforms
The app displays "Unsupported platform" on desktop/web.
