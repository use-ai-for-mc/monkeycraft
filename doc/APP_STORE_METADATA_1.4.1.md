# App Store metadata draft for MonkeyCraft 1.4.1

## Product page

Promotional text:

```text
Stream and control your own desktop game session from iPhone with live video, touch controls, chat, Data Saver, and quick QR pairing.
```

Description:

```text
MonkeyCraft is a companion remote-control app for a user-owned desktop game client.

Install the MonkeyCraft desktop companion mod, start the local private server, then connect from the app by scanning the QR code or entering the connection details manually. The desktop view streams to your phone and the app sends touch controls back to your own client.

Features:

- Live desktop game video streamed to your phone
- Touch controls for movement, looking, jumping, sneaking, clicking, and hotbar selection
- Dedicated chat screen with rich chat formatting
- Server picker support when your desktop client is at the title screen
- Data Saver mode for lower bandwidth sessions
- Timed notifications and countdowns for supported in-game events
- Optional web audio session routing
- Password-protected local/private-network connection

MonkeyCraft is designed for users who already run the supported Java desktop game client with the companion mod installed. It does not provide the game, game files, hosted game servers, or a public game service. Network access is user-provided over localhost, local Wi-Fi, or another private network path configured by the user outside MonkeyCraft.
```

Keywords:

```text
remote play,streaming,game controls,touch controls,private network,chat,qr pairing,data saver
```

Support URL:

```text
https://github.com/use-ai-for-mc/monkeycraft/wiki
```

Marketing URL:

```text
https://github.com/use-ai-for-mc/monkeycraft
```

Version:

```text
1.4.1
```

Copyright:

```text
2026 Weikeng Chen
```

## App Review

Sign-in required:

```text
Yes
```

User name:

```text
See App Store Connect private App Review Information.
```

Password:

```text
See App Store Connect private App Review Information.
```

Notes:

```text
MonkeyCraft lets a user control their own supported desktop game client from an iPhone over localhost, local Wi-Fi, or another private network path configured by the user outside MonkeyCraft.

Review path:
1. Install the MonkeyCraft companion mod on the desktop game client.
2. Launch the desktop game client and start the MonkeyCraft server from the companion mod.
3. In the iOS app, scan the QR code shown by the mod or enter the server and password manually.
4. Verify live streaming, touch controls, chat mode, stream settings, Data Saver, and disconnect behavior.

VPN clarification:
MonkeyCraft does not provide VPN functionality and does not create, configure, manage, or monitor a VPN connection. The app does not use Apple's Network Extension framework, does not include a packet tunnel or VPN profile, and has no VPN entitlement. It only opens a direct WebSocket connection to a server address entered or selected by the user. If a user independently uses Wi-Fi, cellular networking, or a third-party private-network/VPN app on their device, iOS routes traffic outside MonkeyCraft's control.

Information collected using VPN:
None. MonkeyCraft does not collect any user information using VPN because it has no VPN feature.

Purpose of VPN data collection:
Not applicable. No VPN data is collected. Locally, the app may store the user's server address, connection preferences, and password/credential material on the user's device so the user can reconnect to their own host. This information is used only to initiate and authenticate the user-requested connection to the user's own host.

Third-party sharing and storage:
No VPN data is shared with third parties because no VPN data is collected. MonkeyCraft does not operate a hosted service for user traffic, and the developer does not receive or store the user's video stream, controls, chat, server address, or password. During a session, video, controls, and chat are exchanged directly between the iOS app and the user-selected host.

This resubmission removes the named third-party title from the app's Promotional Text, Description, Keywords, and App Review Notes. The app does not include, distribute, sell, or provide access to that third-party game, hosted game servers, in-app purchases, or paid content. Network access is user-provided. The app uses HMAC-SHA256 only for password challenge authentication and does not use non-exempt encryption.
```

## App Review reply for Guideline 4.1(a)

```text
Hello App Review,

We revised the App Store Connect metadata to address Guideline 4.1(a). The Promotional Text, Description, Keywords, and App Review Notes no longer include the referenced third-party game title or terms that could imply association with another developer.

MonkeyCraft is an independently developed remote-control companion for a user-owned desktop game client. It does not distribute third-party game content, host game servers, provide third-party accounts, or sell paid content.

Please re-review version 1.4.1. Thank you.
```

## App Review reply for VPN functionality questions

```text
Hello App Review,

MonkeyCraft does not provide VPN functionality. The app does not create, configure, manage, or monitor VPN connections; it does not use Apple's Network Extension framework; it does not include a packet tunnel or VPN profile; and it has no VPN entitlement. The wording in the prior App Review Information was intended only to say that users may connect over a private network path they configure outside MonkeyCraft. I have revised the App Review Information to avoid describing this as app VPN functionality.

Responses to your questions:

1. What user information is the app collecting using VPN?

None. MonkeyCraft does not collect any user information using VPN because the app has no VPN feature.

2. For what purposes are you collecting this information?

Not applicable. No VPN data is collected.

For clarity, MonkeyCraft only opens a direct WebSocket connection to a server address entered or selected by the user. The app may store the user's server address, connection preferences, and password/credential material locally on the user's device so the user can reconnect to their own host. This locally stored information is used only to initiate and authenticate the user-requested connection to the user's own host.

3. Will the data be shared with any third parties? If so, for what purposes and where will this information be stored?

No VPN data is shared with third parties because no VPN data is collected. MonkeyCraft does not operate a hosted service for user traffic, and the developer does not receive or store the user's video stream, controls, chat, server address, or password. During a session, video, controls, and chat are exchanged directly between the iOS app and the user-selected host.

If a user independently chooses to run a third-party private-network or VPN app on their device, that networking is configured outside MonkeyCraft and handled by iOS and that third-party app. MonkeyCraft does not control that VPN connection and does not collect data from it.

Please continue reviewing version 1.4.1. Thank you.
```

## Screenshots

Prepared iPhone 6.5" screenshots:

```text
flutter/monkeycraft/store_screenshots/ios/appstore/01-login.png
flutter/monkeycraft/store_screenshots/ios/appstore/02-gameplay-controls.png
flutter/monkeycraft/store_screenshots/ios/appstore/03-stream-settings.png
```

Apple upload copies:

```text
flutter/monkeycraft/store_screenshots/ios/appstore_upload/01-login.png
flutter/monkeycraft/store_screenshots/ios/appstore_upload/02-gameplay-controls.png
flutter/monkeycraft/store_screenshots/ios/appstore_upload/03-stream-settings.png
```
