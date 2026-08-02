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

## Building for Release

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
