# Project Structure

## Overview
This is a **Fabric Minecraft Mod** project (Monkeycraft/Remotecraft) that enables remote control of Minecraft through WebSocket.

## Directory Structure

```
remotecraft-template-1.21.11/
├── src/                          # Source code
│   └── main/
│       ├── java/                 # Java source files
│       │   └── com/chenweikeng/monkeycraft/
│       │       ├── MonkeycraftClient.java    # Main entry point
│       │       ├── api/v1/                   # Public API
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
├── gradle.properties             # Project properties
├── settings.gradle               # Gradle settings
├── HOW-TO-USE.md                 # Usage guide
└── LICENSE                       # MIT License
```

## Key Components

### Java Source (`src/main/java/`)
| Package | Purpose |
|---------|---------|
| `api/v1/` | Public API for external integrations |
| `config/` | Mod configuration & settings screen |
| `server/` | WebSocket server, H264 streaming, chat handling |
| `mixin/` | Minecraft code mixins for injection |
| `ui/` | UI overlays (e.g., QR code display) |
| `utils/` | Crypto, network, image utilities |

### Resources (`src/main/resources/`)
- `fabric.mod.json` - Mod metadata (ID, version, dependencies)
- `monkeycraft.mixins.json` - Mixin configuration
- `assets/monkeycraft/` - Language files, icon

### Flutter App (`flutter/monkeycraft/`)
Companion mobile app for remote Minecraft control.

## Cleaned Up Items

The following were removed/cleaned:
- `bin/` - Eclipse IDE output folder (was incorrectly present; already in .gitignore)

## Build Commands

```bash
./gradlew build        # Build the mod
./gradlew jar          # Create JAR
./gradlew clean        # Clean build artifacts
```
