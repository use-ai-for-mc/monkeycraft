# MonkeyCraft Client

Flutter mobile app for remote Minecraft control.

## Version

1.4.1+10

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

### iOS (App Store Connect)

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

### Android (Google Play)

1. Update version in `pubspec.yaml` (version name and build number)
2. Build the release AppBundle:
   ```bash
   flutter build appbundle --release
   ```
3. The AAB will be at: `build/app/outputs/bundle/release/app-release.aab`
4. Upload to Google Play Console:
   - Go to your app → Release → Testing/Production
   - Create new release
   - Upload the `.aab` file
   - Update release notes
   - Save and roll out
## Release Checklist

- [ ] Update `pubspec.yaml` version
- [ ] Test on both iOS and Android
- [ ] Build release artifacts
- [ ] Upload to respective stores
- [ ] Update release notes
