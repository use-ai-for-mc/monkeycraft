<div align="center">

# 🐒 MonkeyCraft

<img src="https://raw.githubusercontent.com/use-ai-for-mc/monkeycraft/master/mods/26.1/src/main/resources/assets/monkeycraft/icon.png" alt="MonkeyCraft Logo" width="128" height="128">

### *Play Minecraft from anywhere. Really anywhere.*

**Stream and control your Minecraft game from your phone**

[![Minecraft](https://img.shields.io/badge/Minecraft-1.19%20%7C%201.21.11%20%7C%2026.1%20%7C%2026.2-green.svg)](https://www.minecraft.net/)
[![Fabric](https://img.shields.io/badge/Fabric-0.14.22+-orange.svg)](https://fabricmc.net/)
[![License](https://img.shields.io/badge/License-CC0--1.0-purple.svg)](LICENSE)

</div>

---

iOS client 1.4.1 is now available on the Apple App Store. Android client is not publicly released yet; Google Play closed-testing and production-release preparation is in progress. Please refer to the [wiki](https://github.com/use-ai-for-mc/monkeycraft/wiki) for the latest client release information.

---

## 📱 Mobile App Availability

- **iOS 1.4.1** — Available on the [Apple App Store](https://apps.apple.com/app/id6759430770).
- **Web** — [use-ai-for-mc.github.io/monkeycraft](https://use-ai-for-mc.github.io/monkeycraft/). Desktop Chrome/Edge. Open from the same machine or LAN as the Minecraft client (`ws://`), or over Tailscale (`wss://`).
- **Android** — Not publicly released yet. Google Play closed-testing and production-release preparation is in progress; Android public availability will be announced separately.


## ✨ What Can You Do?

MonkeyCraft lets you **play Minecraft remotely** from your iOS or Android phone. 

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

- 🛡️ **Password Protected** — Only those with your password can connect
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

Open the MonkeyCraft app, or the [web client](https://use-ai-for-mc.github.io/monkeycraft/), and:
- Enter your computer's IP address and port (default: 9600)
- Scan the QR code displayed in-game (mobile), or
- Enter the password manually

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

### Supported Versions

| Minecraft Version | Java | Mod Location |
|-------------------|------|--------------|
| 26.2 | 25+ | `mods/26.2/` |
| 26.1 | 25+ | `mods/26.1/` |
| 1.21.11 | 21+ | `mods/1.21.11/` |
| 1.19 | 17+ | `mods/1.19/` |

### Install Steps

1. **Install Fabric** — Download from [fabricmc.net](https://fabricmc.net/use/)
2. **Download MonkeyCraft** — Get the mod JAR for your Minecraft version
3. **Install Mod** — Place in your `mods` folder
4. **Get the App**
   - iOS: [Download MonkeyCraft from the Apple App Store](https://apps.apple.com/app/id6759430770)
   - Android: Google Play release preparation and closed testing are coming soon; Android is not publicly available yet
5. **Connect & Play!**

### Building from Source

```bash
# Build for Minecraft 26.2 (needs Java 25)
cd mods/26.2 && ./gradlew build

# Build for Minecraft 26.1 (needs Java 25)
cd mods/26.1 && ./gradlew build

# Build for Minecraft 1.21.11 (needs Java 21)
cd mods/1.21.11 && ./gradlew build

# Build for Minecraft 1.19 (needs Java 17)
cd mods/1.19 && ./gradlew build

# Build Flutter app
cd flutter/monkeycraft && flutter build apk

# Build Flutter web (GitHub Pages uses --base-href /monkeycraft/)
cd flutter/monkeycraft && flutter build web --release --base-href /monkeycraft/
```

---

## ❓ FAQ

### Can I play on a server?

Yes! MonkeyCraft streams your Minecraft client, so you can play on any server or singleplayer world.

### Is there lag?

Video is encoded and streamed in real-time. For best results:
- Use a strong WiFi connection
- Lower resolution/FPS if needed
- Keep your computer close to your router

### Can multiple phones connect?

Only one phone can connect at a time.

### Does it work over the internet?

By default, connections are restricted to your local network. You can enable internet access in settings, but proceed with caution.

### What commands can I run remotely?

By default, all commands are allowed except `op` and `deop`. Configure allowlist/denylist in settings.

---

<div align="center">

**Made with ❤️ by [weikengchen](https://github.com/weikengchen)**

</div>
