# Project Structure

## Overview
This is a **Fabric Minecraft Mod** project (Monkeycraft) that enables remote control of Minecraft through WebSocket.

## Directory Structure

```
monkeycraft/
├── mods/                         # One mod tree per Minecraft target
│   ├── 26.1/                     # Minecraft 26.1, Java 25
│   ├── 1.21.11/                  # Minecraft 1.21.11, Java 21
│   └── 1.19/                     # Minecraft 1.19, Java 17
│       └── src/main/
│           ├── java/com/chenweikeng/monkeycraft/
│           │   ├── MonkeycraftClient.java    # Mod entry point
│           │   ├── MapDataHandler.java       # 2D map mode (data side)
│           │   ├── CameraController.java     # Smooth-look camera
│           │   ├── FrameCaptureManager.java  # Per-tick frame grabber
│           │   ├── config/                   # ModConfig, ConfigScreen
│           │   ├── integration/              # ModMenu integration
│           │   ├── mixin/                    # Mixins / accessors
│           │   ├── server/                   # WebSocket server + handlers
│           │   ├── ui/                       # In-game overlays (QR)
│           │   └── utils/                    # Crypto, image, network
│           └── resources/
│               ├── fabric.mod.json
│               ├── monkeycraft.mixins.json
│               └── assets/monkeycraft/       # icon, lang
│
├── flutter/monkeycraft/          # Flutter companion app
├── doc/                          # Documentation
├── .github/workflows/            # Build & release CI
├── AGENTS.md                     # Notes for AI agents
├── HOW-TO-USE.md                 # External mod API guide
└── LICENSE                       # CC0-1.0
```

Each `mods/<mc-version>/` directory is a self-contained Gradle project
with its own `build.gradle`, `gradle.properties`, wrapper, and
`build-and-deploy.sh`.

## Key Components

### Java Source (`mods/<mc>/src/main/java/com/chenweikeng/monkeycraft/`)
| Package | Purpose |
|---------|---------|
| `config/` | ModConfig, Cloth-Config screen, NetworkScope + TailscaleAccess enums (AllowConnectionsFrom is legacy/migration) |
| `server/` | WebSocket server, H.264 streaming, chat / command / input / screen handlers, API provider |
| `mixin/` | Mixin classes and `@Invoker` accessors |
| `ui/` | In-game overlays (e.g. password QR) |
| `utils/` | Crypto (HMAC-SHA256), network (local IPs), image |
| (root)  | `MonkeycraftClient`, `MapDataHandler`, `CameraController`, `FrameCaptureManager` |

### Resources (`mods/<mc>/src/main/resources/`)
- `fabric.mod.json` — Mod metadata
- `monkeycraft.mixins.json` — Mixin registration
- `assets/monkeycraft/` — Language files, icon

### Flutter App (`flutter/monkeycraft/`)
Companion mobile app for remote Minecraft control.

### External Dependencies
- **monkeycraft-api** — published as one artifact per Minecraft target,
  e.g. `com.github.weikengchen:monkeycraft-api:1.0.0-mc26.1`. The mod
  consumes it via JitPack; external mods integrating with Monkeycraft
  do the same. See [HOW-TO-USE.md](../HOW-TO-USE.md).

## Build Commands

Each mod is its own Gradle project — `cd` into the target first.

```bash
cd mods/26.1     && ./gradlew build           # MC 26.1   (Java 25)
cd mods/1.21.11  && ./gradlew build           # MC 1.21.11 (Java 21)
cd mods/1.19     && ./gradlew build           # MC 1.19   (Java 17)

./gradlew spotlessApply                       # Format code
./gradlew clean                               # Clean build artifacts
```

## Deployment

```bash
./build-and-deploy.sh  # (within mods/<mc>/) Build and copy to local Modrinth profile
```
