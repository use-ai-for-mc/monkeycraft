# Java Mod Architecture

The Monkeycraft mod (`src/main/java/`) is a client-side Fabric mod that enables remote control of Minecraft through a WebSocket server. It captures gameplay video, streams it to connected mobile clients, and processes input commands from those clients.

## Directory Structure

```
src/main/java/com/chenweikeng/monkeycraft/
├── MonkeycraftClient.java       # Mod entry point & initialization
├── server/                      # Core server functionality
│   ├── WebSocketServerHandler.java  # WebSocket protocol handler
│   ├── WebSocketApiProvider.java    # External API adapter
│   ├── H264Streamer.java        # Video encoding pipeline
│   ├── ChatHandler.java         # Chat message routing
│   └── ChatSegment.java         # Rich text chat formatting
├── config/                      # Configuration
│   ├── ModConfig.java           # Config model & persistence
│   ├── ConfigScreenFactory.java # Cloth Config UI
│   ├── NetworkScope.java        # Base access scope ("Who Can Connect")
│   ├── TailscaleAccess.java     # Tailscale 100.64/10 access policy
│   └── AllowConnectionsFrom.java # Legacy enum (config migration only)
├── ui/                          # User interface
│   └── PasswordQrOverlay.java   # In-game QR code display
├── integration/                 # Third-party integrations
│   └── ModMenuIntegration.java  # ModMenu config screen
├── mixin/                       # Minecraft mixins
│   ├── MinecraftMixin.java      # Block pause screen during streaming
│   ├── KeyboardMixin.java       # Track local keypress timestamps
│   ├── ClientPacketListenerMixin.java  # Chat interception
│   ├── NativeImageAccessor.java # Access pixel data
│   ├── GameRendererAccessor.java # Access GuiRenderer
│   └── GuiRendererAccessor.java # Access frame number
└── utils/                       # Utilities
    ├── CryptoUtils.java         # HMAC-SHA256 authentication
    ├── NetworkUtils.java        # Local IP detection
    └── ImageUtils.java          # Crop/resize operations
```

---

## Entry Point

### MonkeycraftClient.java
Main mod initializer implementing `ClientModInitializer`.

**Responsibilities:**
- Register client commands (`/monkey start`, `/monkey stop`, `/monkey ip`, `/monkey config`)
- Handle server auto-launch on world join
- Process game tick events for video capture
- Manage cursor/mouse state during streaming
- Coordinate screenshot capture and streaming

**Commands:**
| Command | Description |
|---------|-------------|
| `/monkey` | Show help |
| `/monkey start` | Start WebSocket server |
| `/monkey stop` | Stop WebSocket server |
| `/monkey ip` | Display local IP addresses |
| `/monkey config` | Open configuration screen |

**Tick Events:**
- Detects Q key press to disconnect client (hold Q)
- Manages mouse button release timing
- Auto-releases cursor when client connects
- Blocks screens from opening while streaming
- Applies look deltas from client
- Captures and streams frames at configured FPS

---

## Server Package

### WebSocketServerHandler.java
Singleton managing the WebSocket server lifecycle and protocol.

**Key State:**
- `server`: MonkeycraftWebSocketServer instance
- `authenticatedSession`: Current authenticated WebSocket connection
- `streamer`: H264Streamer for video encoding
- `streamConfig`: Current resolution, FPS, color mode
- `isHibernating`: Hibernation state

**Authentication Flow:**
1. Server sends `HELLO` with random salt
2. Client responds with `AUTH` containing salt + HMAC signature
3. Server verifies: `HMAC(password, serverSalt + clientSalt)`
4. Server responds with `AUTH_OK` + mutual signature

**Message Handlers:**
| Message | Handler | Description |
|---------|---------|-------------|
| `CLIENT_STATUS` | `handleClientStatus` | Sync mode, resolution, FPS, settings |
| `START_STREAM` | `handleStartStream` | Begin video capture with resolution/FPS |
| `STOP_STREAM` | `handleStopStream` | Stop video capture |
| `INPUT` | `handleInput` | Key press/release (WASD, SPACE, SHIFT, arrows) |
| `LOOK_DELTA` | `handleLookDelta` | Camera yaw/pitch delta |
| `CLICK` | `handleClick` | Mouse button 0 (left) or 1 (right) |
| `SCREEN_CLICK` | `handleScreenClick` | Click on screen overlay |
| `SCREEN_KEY` | `handleScreenKey` | Key press for screen overlay |
| `HOTBAR_SELECT` | `handleHotbarSelect` | Select hotbar slot 0-8 |
| `RUN_COMMAND` | `handleRunCommand` | Execute Minecraft command |
| `SEND_CHAT` | `handleSendChat` | Send chat message |
| `ENTER_CHAT` | `handleEnterChat` | Enter chat mode |
| `EXIT_CHAT` | `handleExitChat` | Exit chat mode |
| `REQUEST_KEYFRAME` | `handleRequestKeyframe` | Request I-frame reset |
| `HIBERNATION_PING` | `handleHibernationPing` | Keep-alive during hibernation |
| `LIST_SERVERS` | `WorldJoinHandler` | Request the saved multiplayer server list |
| `JOIN_SERVER` | `WorldJoinHandler` | Make the client connect to a multiplayer server |
| `LEAVE_WORLD` | `WorldJoinHandler` | Disconnect from the current world to the title screen |

**Pre-join control (`WorldJoinHandler`):** when `serverAutoStart` is `AT_TITLE_SCREEN` the
WebSocket server runs from game launch (persistently across worlds), so the app can connect at
the title screen. The mod pushes a `WORLD_STATE` message (`MENU` / `CONNECTING` / `IN_WORLD`) on
every phase change, replies to `LIST_SERVERS` with `SERVER_LIST`, and answers `JOIN_SERVER` with
`JOIN_RESULT`. `JOIN_SERVER` accepts an optional `acceptResourcePack` boolean — when true, the
mod calls `ServerData.setResourcePackStatus(ENABLED)` so MC skips the in-game resource-pack
prompt for picker-driven joins.

**Public Methods (via API):**
- `sendTimedNotification()` / `cancelTimedNotification()`
- `sendNudge()`
- `startHibernation()` / `endHibernation()` / `setHibernationMessage()`
- `disconnectClient()`

### WebSocketApiProvider.java
Adapter implementing the external `MonkeycraftApiProvider` interface from `monkeycraft-api`.

Bridges the external API to `WebSocketServerHandler` methods:
- `setTimedNotification()` / `cancelTimedNotification()`
- `sendImmediateNotification()`
- `startHibernation()` / `setHibernationMessage()` / `endHibernation()`
- `isClientConnected()` / `isHibernating()`

### H264Streamer.java
Video encoding pipeline using JCodec.

**Configuration:**
- Width/height (even dimensions only)
- Color mode (0=Normal, 1=High Perf, 2=Retro, 3=Grayscale)
- FPS (1-20)

**Encoding Process:**
1. Receive `NativeImage` from screenshot
2. Convert RGBA to YUV420 (with optional color reduction)
3. Encode to H.264 NAL units via JCodec
4. Send binary frame to WebSocket client (with resolution header on IDR frames)
5. Track pending frames for backpressure

**Resolution Header:**
- IDR frames include 6-byte header: `0x4D 0x43` + width (2 bytes) + height (2 bytes)
- Allows client to verify frame resolution matches expected

**Backpressure:**
- Drops frames if >1 pending
- Requests IDR frame after drops
- Client ACKs frames to advance pipeline

### ChatHandler.java
Routes chat messages between Minecraft and connected client.

**Incoming (Server→Client):**
- Intercepts player chat via `ClientPacketListenerMixin`
- Intercepts system chat via mixin
- Invokes `INCOMING_CHAT` API listeners
- Sends `CHAT_MESSAGE` to WebSocket client

**Outgoing (Client→Server):**
- Receives `SEND_CHAT` from WebSocket
- Invokes `OUTGOING_CHAT` API listeners
- Sends to Minecraft server via `player.connection.sendChat()`

### ChatSegment.java
Converts Minecraft `Component` to structured JSON segments for rich text display.

**Features:**
- Parses color, bold, italic, underline, strikethrough, obfuscated
- Extracts click events (OPEN_URL, RUN_COMMAND, SUGGEST_COMMAND, COPY_TO_CLIPBOARD)
- Extracts hover events (SHOW_TEXT)
- Handles legacy formatting codes

---

## Configuration

### ModConfig.java
Singleton config persisted to `config/monkeycraft.json`.

**Fields:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable mod functionality |
| `serverAutoStart` | enum | `OFF` | When the WS server auto-starts: `OFF` (manual via `/monkey start`) / `AT_TITLE_SCREEN` (at MC launch, persistent — required for the remote server picker) / `ON_WORLD_JOIN` (on world join, stops on disconnect). Legacy `autoLaunch` / `startServerAtLaunch` keys are read once and migrated transparently on load. |
| `port` | int | `9600` | WebSocket server port |
| `password` | String | random | Authentication password (Base58) |
| `networkScope` | enum | `LOCAL_NETWORK` | Base access scope (Who Can Connect) |
| `tailscaleAccess` | enum | `IF_DETECTED` | Tailscale 100.64/10 access policy |
| `commandAllowlist` | List | `["*"]` | Allowed command patterns |
| `commandDenylist` | List | `["op *", "deop *"]` | Denied command patterns |
| `defaultBehavior` | String | `"ALLOW"` | Default if not in list |
| `allowRemoteServerJoin` | boolean | `true` | Allow the app to make the client join a multiplayer server |

**Command Pattern Matching:**
- `"*"` matches all commands
- `"gamemode *"` matches commands starting with `gamemode`
- `"home"` matches exact command

### NetworkScope.java
Base access scope ("Who Can Connect"):

| Value | Description |
|-------|-------------|
| `THIS_COMPUTER` | Only 127.0.0.1 |
| `LOCAL_NETWORK` | LAN / RFC1918 IPs (default) |
| `ANYONE` | No restriction (any source IP) |

### TailscaleAccess.java
Governs the Tailscale `100.64.0.0/10` range, independently of (and additively to) the scope:

| Value | Description |
|-------|-------------|
| `IF_DETECTED` | Accept Tailscale IPs when a local Tailscale daemon is detected (default) |
| `ALWAYS` | Always accept the Tailscale range |
| `NEVER` | Never accept the Tailscale range |

### AllowConnectionsFrom.java
Legacy enum, retained only to migrate old configs to `networkScope` + `tailscaleAccess`.

### ConfigScreenFactory.java
Creates Cloth Config UI for in-game configuration.

**Fields Exposed:**
- Enable/disable toggle
- Auto-launch toggle
- Port number field
- Password text field
- Allow connections from dropdown
- Command allowlist (string list)
- Command denylist (string list)
- Default behavior dropdown

---

## User Interface

### PasswordQrOverlay.java
Renders QR code on HUD when server is running but no client connected.

**Behavior:**
- Generates QR code from password using ZXing
- Displays 64x64 QR in bottom-right corner
- Only shows when: server running AND no client connected
- Uses dynamic texture for efficient rendering

---

## Mixins

### MinecraftMixin.java
Prevents unwanted UI behavior during streaming.

**Injections:**
- `setScreen`: Blocks `PauseScreen` when cursor auto-released
- `setWindowActive`: Prevents window inactive handling during streaming

### KeyboardMixin.java
Tracks local keyboard activity for idle detection.

**Injections:**
- `keyPress`: Records timestamp of last local keypress in `MonkeycraftClient.lastLocalKeyInputTime`

### ClientPacketListenerMixin.java
Intercepts incoming chat messages.

**Injections:**
- `handlePlayerChat`: Extracts player message, routes to `ChatHandler`
- `handleSystemChat`: Extracts system message, routes to `ChatHandler`

### NativeImageAccessor.java
Accessor mixin to access private `getPixelABGR` method.

**Purpose:**
- Direct pixel access for RGBA→YUV conversion
- Avoids reflection overhead in hot path

### GameRendererAccessor.java
Accessor for `GameRenderer.guiRenderer`.

### GuiRendererAccessor.java
Accessor for `GuiRenderer.frameNumber`.

---

## Utilities

### CryptoUtils.java
HMAC-SHA256 authentication utilities.

**Methods:**
- `generateSalt()`: Generate 16-byte random salt (Base64)
- `computeHmac(key, data)`: Compute HMAC-SHA256 (Base64)

### NetworkUtils.java
Local network utilities.

**Methods:**
- `getLocalIpAddresses()`: List non-loopback IPv4 addresses
- `getLocalIpAddressesWithPort(port)`: Format IPs with port

### ImageUtils.java
Image manipulation utilities.

**Methods:**
- `resize(source, width, height)`: Scale image
- `crop(source, x, y, width, height)`: Crop region

---

## External API

The public API is provided by the separate `monkeycraft-api` library (`com.github.weikengchen:monkeycraft-api` on JitPack).

See: https://github.com/weikengchen/monkeycraft-api

**API Features:**
- Connection events (connect/disconnect)
- Command execution interception
- Chat message interception (incoming/outgoing)
- Timed notifications
- Hibernation control
- Client state queries

---

## Resources

### fabric.mod.json
Fabric mod metadata.

**Key Fields:**
- `id`: `monkeycraft`
- `environment`: `client`
- `entrypoints.client`: `MonkeycraftClient`
- `entrypoints.modmenu`: `ModMenuIntegration`
- `depends`: fabricloader, minecraft ~1.21.11, java 21, fabric-api
- `suggests`: modmenu

### monkeycraft.mixins.json
Mixin configuration.

**Registered Mixins:**
- `MinecraftMixin`
- `KeyboardMixin`
- `NativeImageAccessor`
- `ClientPacketListenerMixin`
- `GameRendererAccessor`
- `GuiRendererAccessor`

---

## Dependencies

From `build.gradle`:
| Dependency | Purpose |
|------------|---------|
| Java-WebSocket | WebSocket server |
| JCodec | H.264 encoding |
| ZXing | QR code generation |
| Cloth Config | Config UI |
| ModMenu | Mod menu integration |
| Fabric API | Minecraft mod framework |
| monkeycraft-api | Public API for external mods |
