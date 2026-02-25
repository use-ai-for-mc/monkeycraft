# Project Structure

## Overview
This is a **Fabric Minecraft Mod** project (Monkeycraft) that enables remote control of Minecraft through WebSocket.

## Directory Structure

```
monkeycraft/
├── src/                          # Source code
│   └── main/
│       ├── java/                 # Java source files
│       │   └── com/chenweikeng/monkeycraft/
│       │       ├── MonkeycraftClient.java    # Main entry point
│       │       ├── config/                   # Configuration
│       │       ├── integration/              # ModMenu integration
│       │       ├── mixin/                    # Mixin classes
│       │       ├── server/                   # WebSocket server
│       │       ├── ui/                       # UI components
│       │       └── utils/                    # Utility classes
│       └── resources/
│           ├── fabric.mod.json               # Fabric mod metadata
│           ├── monkeycraft.mixins.json       # Mixin config
│           └── assets/monkeycraft/           # Mod assets (lang, icon)
│
├── flutter/                      # Flutter companion app
│   └── monkeycraft/
│
├── gradle/                       # Gradle wrapper
├── build/                        # Gradle build output (gitignored)
├── doc/                          # Documentation
│
├── build.gradle                  # Gradle build config
├── gradle.properties             # Project properties (version, deps)
├── settings.gradle               # Gradle settings
├── build-and-deploy.sh           # Build & deploy to local Modrinth
├── HOW-TO-USE.md                 # Usage guide
└── LICENSE                       # MIT License
```

## Key Components

### Java Source (`src/main/java/`)
| Package | Purpose |
|---------|---------|
| `config/` | Mod configuration & settings screen |
| `server/` | WebSocket server, H264 streaming, chat handling, API provider |
| `mixin/` | Minecraft code mixins for injection |
| `ui/` | UI overlays (e.g., QR code display) |
| `utils/` | Crypto, network, image utilities |

### Resources (`src/main/resources/`)
- `fabric.mod.json` - Mod metadata (ID, version, dependencies)
- `monkeycraft.mixins.json` - Mixin configuration
- `assets/monkeycraft/` - Language files, icon

### Flutter App (`flutter/monkeycraft/`)
Companion mobile app for remote Minecraft control.

### External Dependencies
- **monkeycraft-api** (`com.github.weikengchen:monkeycraft-api`) - Public API library for external mod integrations

## Build Commands

```bash
./gradlew build        # Build the mod
./gradlew jar          # Create JAR
./gradlew clean        # Clean build artifacts
./gradlew spotlessApply # Format code
```

## Deployment

```bash
./build-and-deploy.sh  # Build and copy to local Modrinth profile
```
