<div align="center">

# 🐒 MonkeyCraft

<img src="https://raw.githubusercontent.com/use-ai-for-mc/monkeycraft/master/mods/26.1/src/main/resources/assets/monkeycraft/icon.png" alt="MonkeyCraft Logo" width="128" height="128">

### *Play Minecraft from anywhere. Really anywhere.*

**Stream and control your Minecraft game from your phone or browser**

[![Minecraft](https://img.shields.io/badge/Minecraft-1.19%20%7C%201.21.11%20%7C%2026.1%20%7C%2026.2-green.svg)](https://www.minecraft.net/)
[![Mod release](https://img.shields.io/badge/Mod-1.4.3-blue.svg)](https://github.com/use-ai-for-mc/monkeycraft/releases/tag/v1.4.3)
[![Fabric](https://img.shields.io/badge/Fabric-client--side-orange.svg)](https://fabricmc.net/)
[![License](https://img.shields.io/badge/License-CC0--1.0-purple.svg)](LICENSE)

</div>

---

**[MonkeyCraft Mod 1.4.3 is available](https://github.com/use-ai-for-mc/monkeycraft/releases/tag/v1.4.3)** for Minecraft **26.2, 26.1, 1.21.11, and 1.19**. Each installer is approximately **27 MB** and includes the Flutter web client and optional built-in Tailscale for Windows x64 and Apple Silicon Macs. This release updates the Mod; the App Store client remains iOS 1.4.1.

## Supported Versions

| Minecraft | Java | Fabric Loader | Mod 1.4.3 download |
|-----------|------|---------------|--------------------|
| 26.2 | 25+ | 0.19.3+ | [26.2 JAR](https://github.com/use-ai-for-mc/monkeycraft/releases/download/v1.4.3/monkeycraft-1.4.3-26.2.jar) |
| 26.1 | 25+ | 0.18.4+ | [26.1 JAR](https://github.com/use-ai-for-mc/monkeycraft/releases/download/v1.4.3/monkeycraft-1.4.3-26.1.jar) |
| 1.21.11 | 21+ | 0.18.4+ | [1.21.11 JAR](https://github.com/use-ai-for-mc/monkeycraft/releases/download/v1.4.3/monkeycraft-1.4.3-1.21.11.jar) |
| 1.19 | 17+ | 0.14.0+ | [1.19 JAR](https://github.com/use-ai-for-mc/monkeycraft/releases/download/v1.4.3/monkeycraft-1.4.3-1.19.jar) |

Install the matching Fabric API as well. Choose one JAR for your Minecraft version; `-sources.jar` files are for developers.

Built-in Tailscale supports **Windows x64** and **Apple Silicon Macs running ARM64 Java**. Linux and Intel Macs can still use the Mod over LAN or system Tailscale. Helpers are bundled in the JAR; no component download is required.

---

## 📱 Client Availability

- **iOS 1.4.1** — Available on the [Apple App Store](https://apps.apple.com/app/id6759430770).
- **Web** — [Open the live web client](https://use-ai-for-mc.github.io/monkeycraft/). Supports desktop Chrome/Edge and iPhone Safari. Use **Connect with Tailscale** to sign in, select your game computer, and pair in Minecraft. Direct-address browser video requires HTTPS and a reachable secure WebSocket (`wss://`) endpoint; `localhost` is also supported for development.
- **Android** — Not publicly released yet. Google Play closed-testing and production-release preparation is in progress; Android public availability will be announced separately.


## ✨ What Can You Do?

MonkeyCraft lets you **play Minecraft remotely** from the iOS app or a supported browser. Android public release preparation is in progress.

🎮 **Imagine these scenarios:**

- 🛋️ **Couch Gaming** — Keep playing while someone else uses the computer
- 🚇 **On the Go** — Continue your world from your phone during commute
- 🏠 **Around the House** — Check on your farm or AFK fishing from anywhere
- 👥 **Share Your Game** — Let a friend play on your world from their phone

---

## 🎯 Features

### 📹 Live Video Streaming

Watch your Minecraft game in real-time on your phone with:

| Setting | Options |
|---------|---------|
| 📐 Resolution | Low, Medium, High |
| 🎨 Color Mode | Normal, High Perf (12-bit), Retro (6-bit), Grayscale |
| ⚡ FPS | 1–20 frames per second |

### 🗺️ 2D Map Mode

Switch to a **top-down view** of the world around you, streamed as H.264 video just like the
first-person feed. Handy for navigation, base layout, or following someone else on the server.

### 🕹️ Touch Controls

Full gameplay control with intuitive touch interface:

| Control | Action |
|---------|--------|
| 🕹️ **Virtual Joystick** | Move around (WASD) |
| 👆 **Look Pad** | Look around by dragging + tap to click |
| 🦘 **Jump Button** | Jump (Space) |
| 🦆 **Sneak Button** | Sneak/crouch (Shift) |
| 🔢 **Hotbar** | Select items in your hotbar |
| 🧭 **Auto-Face Movement** | Optional: Automatically face movement direction |

### 💬 Chat System

- 📨 **Send Messages** — Chat with other players on the server
- 📥 **Receive Messages** — See all incoming chat with rich formatting
- 🔗 **Click Links** — Tap on links and commands in chat

### 🔔 Smart Notifications

Stay informed even when not actively playing:

| Type | Description |
|------|-------------|
| ⏰ **Timed Notification** | Get reminded at a specific time with countdown |
| 📳 **Instant Nudge** | Receive immediate alerts from in-game events |

### 🎵 Spatial Audio

When the server you're on runs [OpenAudioMc](https://openaudiomc.net/) or the MCParks v1
audio system, MonkeyCraft can route the audio session to your phone:

- 🎧 **Server-side spatial audio** — voice, ambience, music played by the server reaches your phone
- 🔊 **Volume slider** — adjust MCParks playback volume independently in Settings
- 🔁 **Soft-refresh on resume** — when the app returns from background, the audio session reconnects without a full re-pair

### 😴 Hibernation Mode

Need to step away but stay connected?

- ⏸️ **Pause Streaming** — Stops video to save bandwidth
- 🔗 **Keep Connection** — Stays logged in to the server
- 💬 **Chat Available** — Still send and receive messages
- 📱 **Live Activity (iOS)** — See countdown on your lock screen

### 🧭 Remote Server Join

Connect from your phone while Minecraft is still at the title screen:

- 📋 **Saved server list** — browse the multiplayer servers saved on your client
- ⌨️ **Direct connect** — type any server address to join
- 🚪 **Hands-free** — with *Start Server at Launch* enabled, pick and join a server entirely from the app

### 🔐 Secure Connection

- 🛡️ **Pairing and Passwords** — Approve a pairing request in Minecraft, or connect with the Mod password; iOS 1.4.1 uses the password or password QR code
- 🔒 **HMAC Authentication** — Cryptographic challenge-response
- 🌐 **Network Control** — Restrict to localhost, local network, or anywhere
- 📱 **QR Code Setup** — Quick scan to enter password

---

## 🎮 How It Works

### 1️⃣ Install the Mod

Install the MonkeyCraft mod on your **Fabric** Minecraft client (1.19, 1.21.11, 26.1, or 26.2).

### 2️⃣ Start the Server

In Minecraft, type `/monkey start` to launch the WebSocket server.

### 3️⃣ Connect Your Phone or Browser

For the [live web client](https://use-ai-for-mc.github.io/monkeycraft/), choose **Connect with Tailscale**, sign in, select your computer, and approve the pairing request in Minecraft. On supported computers, `/monkey tailscale login` enables the bundled Tailscale connection; otherwise use system Tailscale.

For **iOS 1.4.1**, enter a reachable computer address and port (default: 9600), then enter the Mod password or scan its password QR code. LAN and system Tailscale connections remain available. Updating the Mod does not add the newer pairing interface to the old app.

The Mod also serves its bundled Flutter web client. Browser video needs a secure context: use HTTPS with a reachable `wss://` endpoint for direct-address connections, such as an existing Tailscale Serve HTTPS address. Bare LAN HTTP is not a cross-device browser video path. The hosted client's built-in Tailscale connection is a separate option.

### 4️⃣ Play!

Your Minecraft view appears on your phone. Use the touch controls to move, look, jump, and interact with the world.

---

## ⚙️ Configuration Options

Access settings via `/monkey config` or through ModMenu:

| Option | Default | What It Does |
|--------|---------|--------------|
| 🚪 **Port** | 9600 | The port number for connections |
| 🔑 **Password** | Random | Your connection password |
| 🌍 **Who Can Connect** | My local network | Base scope: This computer only / My local network / Anyone |
| 🔐 **Tailscale Access** | If detected | Accept Tailscale (`100.64.0.0/10`): If detected / Always / Never |
| ✅ **Command Allowlist** | All allowed | Which commands can be run remotely |
| ❌ **Command Denylist** | op, deop | Blocked commands |
| 🚀 **Auto-Launch** | Off | Start server automatically when joining a world |
| 🟢 **Start Server at Launch** | Off | Start the server when Minecraft finishes loading, so the app can connect from the title screen |
| 🔗 **Allow Remote Server Join** | On | Let the connected app make this client join a multiplayer server |

---

## 📋 In-Game Commands

| Command | Description |
|---------|-------------|
| `/monkey` | Show help (also prints your IPs while the server is running) |
| `/monkey start` | Start the WebSocket server |
| `/monkey stop` | Stop the server |
| `/monkey config` | Open settings screen |
| `/monkey tailscale login` | Enable and sign in to built-in Tailscale on supported computers |
| `/monkey tailscale status` | Show built-in Tailscale status |
| `/monkey tailscale stop` | Stop the built-in Tailscale connection |
| `/monkey tailscale logout` | Sign out of built-in Tailscale |

---

## 📱 App Screens

| Screen | Purpose |
|--------|---------|
| 🔐 **Login** | Enter server details and password |
| 🧭 **Server Picker** | Choose a multiplayer server to join when the client is at the title screen |
| 📹 **Stream** | Main gameplay with video and controls |
| 💬 **Chat** | Dedicated chat interface |
| ⚙️ **Settings** | Adjust video quality and preferences |

---

## 🚀 Getting Started

### Install Steps

1. **Install Fabric** — Download from [fabricmc.net](https://fabricmc.net/use/)
2. **Download MonkeyCraft** — Choose the matching [Mod 1.4.3 JAR](https://github.com/use-ai-for-mc/monkeycraft/releases/tag/v1.4.3) from the supported versions above
3. **Install Mod** — Place in your `mods` folder
4. **Choose a Client**
   - Web: [Open MonkeyCraft in your browser](https://use-ai-for-mc.github.io/monkeycraft/)
   - iOS: [Download MonkeyCraft from the Apple App Store](https://apps.apple.com/app/id6759430770)
   - Android: Google Play release preparation and closed testing are coming soon; Android is not publicly available yet
5. **Connect & Play!**

### Building from Source

Run each command from the repository root. Install the target JDK, Flutter and the Go toolchain first. Every Mod build requires the shared Flutter browser bundle and the Windows x64 / Apple Silicon macOS helper artifacts:

```bash
# Set FLUTTER_BIN to your Flutter executable when it is not on PATH.
# This is the production web bundle embedded by every Mod, rooted at /.
(cd flutter/monkeycraft && \
  FLUTTER_BIN=/absolute/path/to/flutter \
  MONKEYCRAFT_PAGES_PROVENANCE=0 \
  bash tool/build_web_release.sh / build/web)

(cd native/tailscale-helper && ./scripts/build-all.sh)
(cd mods/26.2 && ./gradlew build)

# Other Mod targets: Java 25, 21, and 17 bytecode respectively
(cd mods/26.1 && ./gradlew build)
(cd mods/1.21.11 && ./gradlew build)
(cd mods/1.19 && ./gradlew build)
```

If Flutter is on your `PATH`, omit `FLUTTER_BIN=/absolute/path/to/flutter`. The historical `web/` TypeScript client remains only as reference and test fixtures; `pnpm --dir web build` is not the production Mod browser build. To build the separate GitHub Pages artifact locally, use the same command with base `/monkeycraft/` and a distinct output:

```bash
(cd flutter/monkeycraft && \
  FLUTTER_BIN=/absolute/path/to/flutter \
  MONKEYCRAFT_PAGES_PROVENANCE=0 \
  bash tool/build_web_release.sh /monkeycraft/ build/pages)
```

This command creates local files only; it does not deploy or change the live Pages site. The 1.19 Gradle launcher requires Java 21 or later while compiling for Java 17. See the [helper build instructions](native/tailscale-helper/README.md) for Go toolchain selection.

For Android, install the NDK and build the pinned native libraries before building the app. Details and APK verification are in the [Android native dependency instructions](flutter/monkeycraft/android/third_party/libtailscale/README.md).

```bash
flutter/monkeycraft/android/third_party/libtailscale/build.sh
(cd flutter/monkeycraft && flutter pub get && flutter build apk)
```

For iOS, use macOS with Xcode and the pinned Go toolchain described in the [native dependency instructions](flutter/monkeycraft/ios/third_party/libtailscale/README.md), then build with your signing configuration:

```bash
flutter/monkeycraft/ios/third_party/libtailscale/build.sh
(cd flutter/monkeycraft && bash tool/build_ios_device_release.sh)
```

This device-build entry point clears shared native-asset caches and verifies
the platform and signing team of every embedded framework before installation.
Preserve any Android or Web build outputs you need before its clean step.

---

## ❓ FAQ

### Can I play on a server?

Yes! MonkeyCraft streams your Minecraft client, so you can play on any server or singleplayer world.

### Is there lag?

Video is encoded and streamed in real-time. For best results:
- Use a strong WiFi connection
- Lower resolution/FPS if needed
- Keep your computer close to your router

### Can multiple clients connect?

Only one controlling phone or browser can connect at a time.

### Does it work over the internet?

Yes. Use built-in Tailscale on Windows x64 or Apple Silicon Macs, or use system Tailscale on your game computer. The hosted web client can sign in to Tailscale directly. Default direct-address access remains limited to your local network.

### What commands can I run remotely?

By default, all commands are allowed except `op` and `deop`. Configure allowlist/denylist in settings.

---

<div align="center">

**Made with ❤️ by [weikengchen](https://github.com/weikengchen)**

</div>
