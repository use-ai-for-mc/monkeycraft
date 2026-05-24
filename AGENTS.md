# AGENTS.md - Guide for AI Agents

This document provides essential context for AI agents working on the MonkeyCraft codebase.

## Project Overview

MonkeyCraft is a **remote Minecraft control system** consisting of:
1. **Java Fabric Mod** - Server-side component running in Minecraft
2. **Flutter Mobile App** - Client app for iOS/Android

## Architecture Summary

```
┌─────────────────────┐     WebSocket      ┌─────────────────────┐
│   Minecraft Client  │◄──────────────────►│   Flutter App       │
│   (Fabric Mod)      │    H.264 Video     │   (iOS/Android)     │
│                     │    Commands        │                     │
└─────────────────────┘                    └─────────────────────┘
```

## Key Files to Understand

Paths prefixed with `mods/<mc>/` exist in all three mod trees (`mods/26.1/`,
`mods/1.21.11/`, `mods/1.19/`) with the same role; differences are usually
narrow API adaptations.

| File | Purpose |
|------|---------|
| `mods/<mc>/src/main/java/.../MonkeycraftClient.java` | Mod entry point, tick events, command registration |
| `mods/<mc>/src/main/java/.../server/WebSocketServerHandler.java` | Protocol handling, all message types |
| `mods/<mc>/src/main/java/.../server/H264Streamer.java` | Video encoding |
| `mods/<mc>/src/main/java/.../MapDataHandler.java` | 2D map data frames |
| `flutter/monkeycraft/lib/stream/screens/stream_screen.dart` | Main gameplay UI |
| `flutter/monkeycraft/lib/stream/stream_proxy.dart` | WebSocket communication |
| `flutter/monkeycraft/lib/stream/game_input_controller.dart` | Input state machine |
| `flutter/monkeycraft/lib/stream/session_controller.dart` | Session state management |
| `flutter/monkeycraft/lib/audio/mcparks_v1_service.dart` | MCParks audio session (headless WebView) |

## Build Commands

```bash
# Java Mod — pick a target
cd mods/26.1     && ./gradlew build    # needs Java 25
cd mods/1.21.11  && ./gradlew build    # needs Java 21
cd mods/1.19     && ./gradlew build    # needs Java 17 (Gradle launcher needs 21+)
./gradlew spotlessApply                # Format code (REQUIRED before commit)

# Flutter App
cd flutter/monkeycraft
flutter build ios            # Build iOS
flutter build apk            # Build Android
```

## Code Style

- **Java**: Use spotless formatting (`./gradlew spotlessApply`)
- **Dart/Flutter**: Follow standard Dart conventions
- **No comments** unless explicitly requested

## WebSocket Protocol Summary

### Client → Server
| Type | Purpose |
|------|---------|
| `CLIENT_STATUS` | Sync mode (streaming/chat), resolution, fps, autoFaceMovement |
| `INPUT` | Key press/release (W, A, S, D, SPACE, SHIFT) |
| `LOOK_DELTA` | Camera yaw/pitch delta |
| `CLICK` | Mouse click (button: 0=left, 1=right) |
| `SCREEN_CLICK` | Click on screen overlay (normalized coordinates) |
| `SCREEN_KEY` | Key press for screen overlay |
| `HOTBAR_SELECT` | Select hotbar slot 0-8 |
| `RUN_COMMAND` | Execute Minecraft command |
| `SEND_CHAT` | Send chat message |
| `GET_PLAYER_COUNT` | Request online player count only (polled for the indicator) |
| `GET_PLAYER_LIST` | Request online player account names (on tap-to-view) |

### Server → Client
| Type | Purpose |
|------|---------|
| Binary | H.264 video access unit (IDR frames have 6-byte resolution header: `0x4D 0x43` + width + height) |
| `SERVER_STATUS` | Video state (active/hibernating), timed notifications |
| `CHAT_MESSAGE` | Incoming chat |
| `NUDGE` | Immediate notification |
| `DISCONNECT` | Server-initiated disconnect |
| `PLAYER_COUNT` | Online player count only (`count`) |
| `PLAYER_LIST` | Online player account names (`count` + `players[]`) |

## Current Input Modes

1. **Streaming Mode**: Normal gameplay with joystick, look pad, jump/sneak buttons
2. **Chat Mode**: Dedicated chat interface (video paused)

## Client State Handling

- **Resolution Mismatch**: When server sends frames with wrong resolution, client shows "Waiting for correct resolution..." overlay and drops mismatched frames
- **Reconnection**: Client retries 3 times with exponential backoff (~7 seconds total) before returning to login
- **Hibernation**: When server hibernates, video pauses but chat remains available

## Adding New Features

When adding new protocol messages:
1. Add handler in `WebSocketServerHandler.java:onMessage()`
2. Add sender in Flutter `stream_proxy.dart`
3. Update protocol documentation in `doc/FLUTTER_CLIENT.md`
4. If the message is an optional/feature-gated capability, add a token to `AuthenticationHandler.CAPABILITIES` (advertised in `AUTH_OK`) and gate the client with `proxy.serverSupports("TOKEN")` so older mods degrade gracefully

## Testing

- Java: Run `./gradlew build` - compilation errors indicate issues
- Flutter: Run `flutter analyze` for static analysis

## Important Constraints

- Minecraft targets: 1.19, 1.21.11, 26.1 (three parallel mod trees under `mods/`)
- Java versions: 17 (1.19), 21 (1.21.11), 25 (26.1) — matches each MC release
- Fabric mod (client-side only)
- Only ONE phone can connect at a time
- Video is H.264 encoded, max 20 FPS

## Minecraft Internals Research

**CRITICAL**: Package names, class names, and method signatures for Minecraft internals found online (including documentation sites, wikis, forums, and AI-generated content) are **extremely unreliable** and often incorrect or outdated.

When you need to reference Minecraft's internal classes:
1. **First choice**: Search the decompiled Minecraft jar in this project's build/cache directories
2. **Second choice**: Ask the user to locate the relevant class/method for you
3. **Never rely on**: Online sources for Minecraft package/class names without verification

## Documentation

For finding relevant implementation locations, check the `doc/` directory first - it's faster than searching the codebase:
- `doc/PROJECT_STRUCTURE.md` - Overall project organization
- `doc/JAVA_MOD_ARCHITECTURE.md` - Java mod internals
- `doc/FLUTTER_CLIENT.md` - Flutter app architecture and WebSocket protocol
- `doc/AudioPlayer.md` - In-app audio routing (OpenAudioMc / MCParks)
