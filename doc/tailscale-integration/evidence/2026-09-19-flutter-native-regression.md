# Flutter Native Regression Evidence — 2026-09-19

This record covers build-only regression checks of the shared Flutter client. No
device or simulator was started, no application was installed, and a successful
build is not treated as product or device acceptance.

## Environment

- Flutter 3.41.2
- Xcode 27.0 (27A266a), Apple Silicon host
- Android SDK Build Tools 36.1.0

## Android Debug APK

Command:

```sh
/Users/cusgadmin/if-local/flutter/bin/flutter build apk --debug
```

Result: passed in 40.9 seconds. The resulting
`build/app/outputs/flutter-apk/app-debug.apk` was 166 MB. `apksigner verify
--verbose` verified its APK Signature Scheme v2 signature. The debug APK did
not contain v1, v3, v3.1, or v4 signatures, which is normal for this output.

Build log:
`outputs/flutter-web-feasibility-2026-09-19/native-android-debug-apk-build.log`.

## iOS Simulator Debug

The normal Flutter command was first attempted:

```sh
/Users/cusgadmin/if-local/flutter/bin/flutter build ios --simulator --debug
```

It failed in Flutter tool packaging before a simulator could be run. Flutter
3.41.2 invokes Xcode 27's `lipo` with `-verify_arch arm64 x86_64`; the installed
Xcode 27 tool rejects the multiple architecture invocation with `-verify_arch
requires exactly one input file`. The same Flutter framework reports both
architectures through `lipo -archs`, and each architecture validates separately.
This is a Flutter-tool/Xcode-27 command-line compatibility issue, not evidence
of a missing framework architecture or a Runner source compilation failure.

To isolate source and dependency compilation without modifying Flutter, the
same generated workspace was built for the Apple Silicon simulator architecture
only:

```sh
xcodebuild -workspace ios/Runner.xcworkspace -scheme Runner \
  -configuration Debug -sdk iphonesimulator \
  -destination 'generic/platform=iOS Simulator' \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=YES build
```

Result: passed. The emitted Runner executable is a signed `arm64` Mach-O with
`LC_BUILD_VERSION platform IOSSIMULATOR`, minimum OS 16.6 and SDK 27.0. This
validates the Apple Silicon simulator build path only; it does not validate an
Intel simulator slice, app launch, Tailscale login, notifications, background
audio, or a physical iPhone.

Build logs:

- `outputs/flutter-web-feasibility-2026-09-19/native-ios-simulator-build.log`
- `outputs/flutter-web-feasibility-2026-09-19/native-ios-simulator-arm64-xcodebuild.log`
