# Release 1.4.1 prep

Status as of 2026-06-14.

## Version state

| Component | Version |
| --- | --- |
| Flutter app | `1.4.1+10` |
| Minecraft 1.19 mod | `1.4.1-1.19` |
| Minecraft 1.21.11 mod | `1.4.1-1.21.11` |
| Minecraft 26.1 mod | `1.4.1-26.1` |

## Main changes since the previous public build

- Remote server selection from the mobile app, with title-screen server picker support.
- Config rename for server startup behavior: `serverAutoStart` replaces the confusing legacy auto-launch/start-at-launch flags, with migration for old config keys.
- Optional `acceptResourcePack` flag on remote server joins; the mobile picker defaults it on.
- Data Saver mode, advertised by the mod via the `DATA_SAVER` capability and sent by the app in `CLIENT_STATUS`.
- Safer mobile session lifecycle: reconnects stop after leaving the stream screen, double-dispose paths are guarded, and held inputs are released when a remote session ends.
- Video path cleanup: MPEG-TS PCR handling, 3-byte Annex-B start codes, and removal of unused Flutter dependencies.

## Validation completed

| Target | Result | Notes |
| --- | --- | --- |
| iOS simulator | Passed | `flutter run --debug --no-resident` built, installed, and `simctl launch` started `com.chenweikeng.monkeycraft`. |
| Android emulator | Passed | `flutter run --debug --no-resident` built, installed, and launched `MainActivity`; pre-bump installed app reported `versionName=1.4.0`, `versionCode=9`. |
| Android release AAB | Passed | Built `flutter/monkeycraft/build/app/outputs/bundle/release/app-release.aab` (`1859b952a5691559bc3b0e231036aef33e97d7b5a91bad6be237bdd8b8a813ca`). |
| iOS release IPA | Pending Xcode build | Build from Xcode after the `1.4.1+10` version bump. |
| Minecraft 1.19 | Passed | PrismLauncher `Fabric 1.19`; WS auth returned `DATA_SAVER`; JVM DebugBridge readback confirmed `dataSaver=true`, `640x360`, `fps=10`. |
| Minecraft 1.21.11 | Passed | PrismLauncher `ImagineFun`; WS auth returned `DATA_SAVER`; JVM DebugBridge readback confirmed `dataSaver=true`, `640x360`, `fps=10`. |
| Minecraft 26.1 | Passed with limited readback | PrismLauncher `26.1`; WS auth returned `DATA_SAVER`; `CLIENT_STATUS dataSaver:true` sent successfully and socket stayed open. This profile has no DebugBridge jar, so JVM readback was not available. |

## Pre-tag checklist

- [ ] Commit the iOS simulator platform fix if simulator testing should remain supported from a clean checkout.
- [x] Build release app artifacts locally or via CI:
  - `flutter build ipa --release`
  - `flutter build appbundle --release`
- [ ] Confirm App Store Connect/TestFlight and Google Play release notes.
- [ ] Do not create tags until the final release decision is made.
