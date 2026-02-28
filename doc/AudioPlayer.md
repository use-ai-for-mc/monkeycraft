# OpenAudioMc Integration for MonkeyCraft

## Overview

OpenAudioMc is a Minecraft server plugin that provides:
- Region-based music and sound effects
- Speaker blocks for in-world audio
- All without requiring client-side mods

Players connect via a web client URL they receive when joining the server. The web client handles all audio playback through the browser's Web Audio API.

## Integration

When the app receives a URL starting with `https://session.openaudiomc.net/#`, open it in a headless WebView for passive audio playback.

## Flutter Package

```yaml
dependencies:
  flutter_inappwebview: ^6.1.5
```

Use `HeadlessInAppWebView` to run the OpenAudioMc web client without visible UI.

## Platform-Specific Configuration

### iOS - Info.plist

Add background mode capability in Xcode (Signing & Capabilities → + Capability → Background Modes → check "Audio, AirPlay, and Picture in Picture"):

```xml
<key>UIBackgroundModes</key>
<array>
    <string>audio</string>
</array>
<key>NSMicrophoneUsageDescription</key>
<string>Not used - passive audio only</string>
```

### Android - AndroidManifest.xml

```xml
<uses-permission android:name="android.permission.INTERNET" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
<uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK" />
<uses-permission android:name="android.permission.WAKE_LOCK" />
<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />
```

## Implementation Example

```dart
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class OpenAudioMcService {
  static const _urlPrefix = 'https://session.openaudiomc.net/#';
  
  HeadlessInAppWebView? _headlessWebView;

  static bool isOpenAudioMcUrl(String url) {
    return url.startsWith(_urlPrefix);
  }

  Future<void> initialize() async {
    _headlessWebView = HeadlessInAppWebView(
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        mediaPlaybackRequiresUserGesture: false,
      ),
      onWebViewCreated: (controller) {
        print('OpenAudioMc WebView created');
      },
      onLoadStop: (controller, url) {
        print('OpenAudioMc loaded: $url');
      },
    );
    
    await _headlessWebView!.run();
  }

  Future<void> connect(String sessionUrl) async {
    if (_headlessWebView == null) {
      await initialize();
    }
    
    await _headlessWebView!.webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri(sessionUrl)),
    );
  }

  Future<void> disconnect() async {
    await _headlessWebView?.webViewController?.loadUrl(
      urlRequest: URLRequest(url: WebUri('about:blank')),
    );
  }

  Future<void> dispose() async {
    await _headlessWebView?.dispose();
    _headlessWebView = null;
  }
}
```

## URL Detection

When receiving URLs (e.g., from chat messages or server protocol), check:

```dart
if (OpenAudioMcService.isOpenAudioMcUrl(url)) {
  await openAudioMcService.connect(url);
}
```

## Getting the Session URL

Extend the existing WebSocket protocol to include the OpenAudioMc session URL:

```json
{
  "type": "OPENAUDIOMC_SESSION",
  "url": "https://session.openaudiomc.net/#..."
}
```

The Java mod captures this URL when OpenAudioMc generates it and forwards it to the Flutter client.

## Summary

| Aspect | Value |
|--------|-------|
| URL prefix | `https://session.openaudiomc.net/#` |
| Package | `flutter_inappwebview` |
| Mode | Passive audio only (no voice chat) |
| Permissions | INTERNET (Android), none required (iOS) |

## Audio Player State Detection

### Checking if Audio is Playing

Detect if the audio player is running by checking for a range input:

```js
!!document.querySelector('input[type="range"]')
```

If this exists → audio is playing. If not → need to start audio session.

### Starting Audio Session

When audio is not playing, find and click the "Start audio session" button (after page is ready):

```js
// Wait for page ready, then click
[...document.querySelectorAll('button')].find(btn => btn.outerText === 'Start audio session')?.click()
```

### Session URI Monitoring

When login succeeds, the URI changes to include a session ID:

```
https://session.openaudiomc.net/?session=d2Vpa2VuZzpmYWRkNzRhZC04YjRlLTQ4MmQtYjU5ZC1iZGI0Y2ZmMGI3ZWI6M2RiZDY0ZjAtODExMC00YjI5LWJkMmYtNGEwZjFlZDNhNTIxOmViZA==
```

**Reconnection Logic:**
1. Save the session URI when it first appears (takes a few seconds after clicking start)
2. Periodically check if session ID is still in URI
3. If session ID disappears → reload to the saved session URI
4. If reload fails multiple times → declare audio connection lost
5. On successful reload → audio connection resumed

### WebSocket Protocol: Audio Connection Status

Suppress connection messages during reconnection attempts by sending status to MC mod:

```json
{
  "type": "INFO",
  "title": "openaudiomc",
  "data": {
    "connected": true
  }
}
```

The MC mod receives this packet to know audio state:
- `connected: true` → audio playing normally
- `connected: false` → audio disconnected or reconnecting

Currently the MC mod receives but does not act on this packet (future: could show indicator to user).

## References

- OpenAudioMc: https://openaudiomc.net/
- flutter_inappwebview: https://pub.dev/packages/flutter_inappwebview
