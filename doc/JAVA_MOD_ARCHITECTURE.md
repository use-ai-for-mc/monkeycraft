# Java Mod Architecture

The Monkeycraft mod (`src/main/java/`) is a client-side Fabric mod that enables remote control of Minecraft through a WebSocket server. It captures gameplay video, streams it to connected mobile clients, and processes input commands from those clients.

## Directory Structure

```
src/main/java/com/chenweikeng/monkeycraft/
├── MonkeycraftClient.java       # Mod entry point & initialization
├── api/v1/                      # Public API for other mods
│   ├── MonkeycraftApi.java      # API facade with events
│   ├── MonkeycraftConnectedListener.java
│   ├── MonkeycraftDisconnectedListener.java
│   ├── MonkeycraftCommandExecutionListener.java
│   ├── MonkeycraftChatListener.java
│   ├── CommandExecutionResult.java
│   ├── ChatMessageContext.java
│   └── ChatMessageResult.java
├── server/                      # Core server functionality
│   ├── WebSocketServerHandler.java  # WebSocket protocol handler
│   ├── H264Streamer.java        # Video encoding pipeline
│   └── ChatHandler.java         # Chat message routing
├── config/                      # Configuration
│   ├── ModConfig.java           # Config model & persistence
│   └── ConfigScreenFactory.java # Cloth Config UI
├── ui/                          # User interface
│   └── PasswordQrOverlay.java   # In-game QR code display
├── integration/                 # Third-party integrations
│   └── ModMenuIntegration.java  # ModMenu config screen
├── mixin/                       # Minecraft mixins
│   ├── MinecraftMixin.java      # Block pause screen during streaming
│   ├── ClientPacketListenerMixin.java  # Chat interception
│   └── NativeImageAccessor.java # Access pixel data
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
| `START_STREAM` | `handleStartStream` | Begin video capture with resolution/FPS |
| `STOP_STREAM` | `handleStopStream` | Stop video capture |
| `INPUT` | `handleInput` | Key press/release (WASD, SPACE, SHIFT, arrows) |
| `LOOK_DELTA` | `handleLookDelta` | Camera yaw/pitch delta |
| `CLICK` | `handleClick` | Mouse button 0 (left) or 1 (right) |
| `HOTBAR_SELECT` | `handleHotbarSelect` | Select hotbar slot 0-8 |
| `RUN_COMMAND` | `handleRunCommand` | Execute Minecraft command |
| `SEND_CHAT` | `handleSendChat` | Send chat message |
| `ENTER_CHAT` | `handleEnterChat` | Enter chat mode |
| `EXIT_CHAT` | `handleExitChat` | Exit chat mode |
| `REQUEST_KEYFRAME` | `handleRequestKeyframe` | Request I-frame reset |
| `HIBERNATION_PING` | `handleHibernationPing` | Keep-alive during hibernation |

**Public Methods (via API):**
- `sendTimedNotification()` / `cancelTimedNotification()`
- `sendNudge()`
- `startHibernation()` / `endHibernation()` / `setHibernationMessage()`
- `disconnectClient()`

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
4. Send binary frame to WebSocket client
5. Track pending frames for backpressure

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

---

## Configuration

### ModConfig.java
Singleton config persisted to `config/monkeycraft.json`.

**Fields:**
| Field | Type | Default | Description |
|-------|------|---------|-------------|
| `enabled` | boolean | `true` | Enable mod functionality |
| `autoLaunch` | boolean | `false` | Auto-start server on world join |
| `port` | int | `9600` | WebSocket server port |
| `password` | String | random | Authentication password (Base58) |
| `commandAllowlist` | List | `["*"]` | Allowed command patterns |
| `commandDenylist` | List | `["op *", "deop *"]` | Denied command patterns |
| `defaultBehavior` | String | `"ALLOW"` | Default if not in list |

**Command Pattern Matching:**
- `"*"` matches all commands
- `"gamemode *"` matches commands starting with `gamemode`
- `"home"` matches exact command

### ConfigScreenFactory.java
Creates Cloth Config UI for in-game configuration.

**Fields Exposed:**
- Enable/disable toggle
- Auto-launch toggle
- Port number field
- Password text field
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

## API Package (v1)

### MonkeycraftApi.java
Public API facade exposing events and methods for external mods.

**Events:**
| Event | Listener | Description |
|-------|----------|-------------|
| `CONNECTION` | `MonkeycraftConnectedListener` | Client authenticated |
| `DISCONNECTION` | `MonkeycraftDisconnectedListener` | Client disconnected |
| `COMMAND_EXECUTION` | `MonkeycraftCommandExecutionListener` | Command from client |
| `INCOMING_CHAT` | `MonkeycraftChatListener` | Chat from server |
| `OUTGOING_CHAT` | `MonkeycraftChatListener` | Chat to server |

**Methods:**
- `setTimedNotification(fireAtEpochMs, title, body, sound)`
- `cancelTimedNotification()`
- `sendImmediateNotification(title, body, sound)`
- `startHibernation(message)`
- `setHibernationMessage(message)`
- `endHibernation()`
- `isClientConnected()`
- `isHibernating()`

### ChatMessageContext.java
Mutable context passed to chat listeners.

**Fields:**
| Field | Type | Modifiable |
|-------|------|------------|
| `message` | String | Yes (via `setMessage()`) |
| `senderUuid` | String | No |
| `senderName` | String | No |
| `outgoing` | boolean | No |

### ChatMessageResult.java
Enum for chat listener return values.

| Value | Meaning |
|-------|---------|
| `ALLOW` | Allow message unchanged |
| `MODIFY` | Allow with modified message |
| `DENY` | Block message entirely |
| `PASS` | Continue to next listener |

### CommandExecutionResult.java
Enum for command listener return values.

| Value | Meaning |
|-------|---------|
| `ALLOW` | Allow immediately |
| `DENY` | Deny immediately |
| `PASS` | Continue to config allowlist/denylist |

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
- `NativeImageAccessor`
- `ClientPacketListenerMixin`

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
