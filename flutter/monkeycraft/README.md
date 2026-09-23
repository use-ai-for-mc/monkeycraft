# MonkeyCraft Client

Flutter mobile app for remote Minecraft control.

## Version

1.4.1+10

## Mobile App Availability

- **iOS 1.4.1** is now available on the [Apple App Store](https://apps.apple.com/app/id6759430770).
- **Android** is not publicly released yet; Google Play closed-testing and production-release preparation is in progress.

## Development

```bash
flutter pub get
flutter run
```

## Testing on Device

### Android

1. Enable USB debugging on your phone
2. Connect phone via USB
3. Verify device is detected:
   ```bash
   flutter devices
   ```
4. Run in release mode:
   ```bash
   flutter run --release
   ```

### iOS

1. Connect iPhone via USB
2. Trust the computer on your phone
3. Verify device is detected:
   ```bash
   flutter devices
   ```
4. Run in release mode:
   ```bash
   flutter run --release
   ```

### Live LAN stream integration (simulators)

The opt-in live fixture authenticates against a locally running Minecraft server and verifies the native decoder. It does not run without an explicit command. Supply a password-only JSON file with mode `0600`; the runner reads it at runtime, creates a random single-use loopback route, and passes only that temporary route to Flutter.

```bash
python3 tool/run_live_native_stream.py \
  --config-path /private/path/password-only.json \
  --server ws://127.0.0.1:9600 \
  --device <booted-ios-simulator-udid> \
  --reconnect
```

For a booted Android emulator, use its emulator serial and the host alias:

```bash
python3 tool/run_live_native_stream.py \
  --config-path /private/path/password-only.json \
  --server ws://10.0.2.2:9600 \
  --device emulator-5554 \
  --reconnect
```

The runner accepts a booted iOS simulator or an `emulator-*` Android emulator, never a physical device. For Android it creates and removes its own random-port `adb reverse` mapping for the one-time configuration route. It is not physical-device validation. Do not place passwords in `--dart-define` values or test output.

## Building for Release

### iOS device-signed package

Build a signed device `Runner.app` with the repeatable helper:

```bash
FLUTTER_BIN=/Users/cusgadmin/if-local/flutter/bin/flutter \
  tool/build_ios_device_release.sh
```

The helper always runs `clean`, `pub get`, a signed `build ios --release`, and `tool/verify_ios_app.py`. It has no unsigned-build option. Flutter stores iOS native assets in a shared `build/native_assets/ios` directory, so do not run simulator and device builds from the same checkout without this clean device-build boundary. The verifier rejects simulator slices and nested bundles whose signing team differs from Runner before an archive is installed.

### iOS (Apple App Store)

1. Ensure you have a valid Apple Developer account and certificates configured in Xcode
2. Update `version:` in `pubspec.yaml`
3. Build the release archive:
   ```bash
   flutter build ipa --release
   ```
4. Open Xcode to archive and validate:
   ```bash
   open build/ios/archive/Runner.xcarchive
   ```
5. In Xcode: Product → Archive → Distribute App → App Store Connect
6. Upload to App Store Connect and submit for review

### Android (Google Play preparation)

1. Update version in `pubspec.yaml` (version name and build number)
2. Build the release AppBundle:
   ```bash
   flutter build appbundle --release
   ```
3. The AAB will be at: `build/app/outputs/bundle/release/app-release.aab`
4. Android is not publicly released yet. When Play Console access and the store listing are ready, upload the `.aab` to a **Closed testing** track first; do not roll it out to Production until the closed-testing and production-access requirements are complete. See [`doc/ANDROID_GOOGLE_PLAY_RELEASE_CHECKLIST.md`](../../doc/ANDROID_GOOGLE_PLAY_RELEASE_CHECKLIST.md).
## Release Checklist

- [ ] Update `pubspec.yaml` version
- [ ] Test on both iOS and Android
- [ ] Build release artifacts
- [ ] Confirm the iOS App Store listing and release notes
- [ ] Complete the Android Google Play closed-testing checklist
- [ ] Update release notes
