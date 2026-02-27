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

| File | Purpose |
|------|---------|
| `src/main/java/.../MonkeycraftClient.java` | Mod entry point, tick events |
| `src/main/java/.../server/WebSocketServerHandler.java` | Protocol handling, all message types |
| `src/main/java/.../server/H264Streamer.java` | Video encoding |
| `flutter/monkeycraft/lib/screens/stream_screen.dart` | Main gameplay UI |
| `flutter/monkeycraft/lib/services/stream_proxy.dart` | WebSocket communication |
| `flutter/monkeycraft/lib/services/game_input_controller.dart` | Input state machine |

## Build Commands

```bash
# Java Mod
./gradlew build              # Build the mod JAR
./gradlew spotlessApply      # Format code (REQUIRED before commit)

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
| `CLIENT_STATUS` | Sync mode (streaming/chat), resolution, fps |
| `INPUT` | Key press/release (W, A, S, D, SPACE, SHIFT) |
| `LOOK_DELTA` | Camera yaw/pitch delta |
| `CLICK` | Mouse click (button: 0=left, 1=right) |
| `HOTBAR_SELECT` | Select hotbar slot 0-8 |
| `RUN_COMMAND` | Execute Minecraft command |
| `SEND_CHAT` | Send chat message |

### Server → Client
| Type | Purpose |
|------|---------|
| Binary | H.264 video access unit |
| `SERVER_STATUS` | Video state (active/hibernating) |
| `CHAT_MESSAGE` | Incoming chat |
| `NUDGE` | Immediate notification |
| `DISCONNECT` | Server-initiated disconnect |

## Current Input Modes

1. **Streaming Mode**: Normal gameplay with joystick, look pad, jump/sneak buttons
2. **Chat Mode**: Dedicated chat interface (video paused)

## Adding New Features

When adding new protocol messages:
1. Add handler in `WebSocketServerHandler.java:onMessage()`
2. Add sender in Flutter `stream_proxy.dart`
3. Update protocol documentation in `doc/FLUTTER_CLIENT.md`

## Testing

- Java: Run `./gradlew build` - compilation errors indicate issues
- Flutter: Run `flutter analyze` for static analysis

## Important Constraints

- Minecraft version: 1.21+
- Java version: 21+
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
- `doc/SCREEN.md` - Screen/container handling implementation
- `doc/PLAN.md` - Project planning and roadmap
