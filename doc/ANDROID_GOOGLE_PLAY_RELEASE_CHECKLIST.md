# Android Google Play Release Checklist

MonkeyCraft Android is not publicly released yet. This checklist covers local
release preparation and the Google Play closed-testing path; it does not claim
that a Play Console release has been uploaded or published.

## Current local release facts

| Item | Current value | Source / action |
| --- | --- | --- |
| App name | `MonkeyCraft` | `android/app/src/main/AndroidManifest.xml` |
| Application ID | `com.chenweikeng.monkeycraft` | `android/app/build.gradle.kts` |
| Version name | `1.4.1` | `flutter/monkeycraft/pubspec.yaml` |
| Version code | `10` | `flutter/monkeycraft/pubspec.yaml` (`1.4.1+10`) |
| Release artifact | `build/app/outputs/bundle/release/app-release.aab` | Produced by `flutter build appbundle --release` |

The local `versionCode` is `10`. Whether code `10` has already been used in
Google Play cannot be verified without Play Console access. Check the existing
Play Console releases before uploading; do not bump the version code solely for
this preparation task.

## Android configuration and signing

- The release build uses Flutter's `versionName` and `versionCode` values from
  `pubspec.yaml`.
- The release signing configuration is loaded from the local
  `android/key.properties` file only when that ignored file exists and contains
  a `storeFile` value.
- `android/key.properties`, keystores, passwords, and upload credentials must
  remain local and must never be committed. This repository intentionally does
  not contain those private values.
- Before upload, confirm that the locally configured upload key is the key
  registered for this Play Console app and that the resulting AAB is signed with
  the intended upload key.

## Store listing preparation

- [ ] **App name:** `MonkeyCraft`
- [ ] **Short description:** prepare a concise description such as:
  `Control your own Minecraft client remotely from your phone with the MonkeyCraft Fabric mod.`
- [ ] **Full description:** describe the mobile client as a companion to the
  MonkeyCraft Fabric mod, including remote video, touch controls, chat, and
  connection setup. Do not describe MonkeyCraft as the game itself, a hosted
  server, a VPN, or a public game service, and do not imply official association
  with Minecraft, Mojang, or Microsoft.
- [ ] **App icon:** provide the final Android launcher icon at the Play Console
  required size and format.
- [ ] **Screenshots:** capture current Android UI screenshots for the listing;
  do not use unfinished debug screens or disclose private server addresses.
- [ ] **Privacy Policy URL:** publish `doc/PRIVACY_POLICY.md` at a stable public
  HTTPS URL and enter that exact URL in Play Console. No public URL is confirmed
  in this repository yet; do not invent one in the listing.
- [ ] **Data Safety:** complete the Play Console Data Safety form from the
  actual app behavior, permissions, dependencies, and privacy policy. Review
  local connection settings, WebSocket traffic, notification permissions, media
  access, and any third-party SDK behavior before answering; do not guess.
- [ ] **Content rating:** complete the Play Console content-rating
  questionnaire and retain the generated rating for the listing.
- [ ] **App access / reviewer instructions:** explain that the app is a
  companion client for a user-controlled MonkeyCraft Fabric mod and requires a
  reachable test Minecraft client. Provide any temporary reviewer server,
  account, or access details only in Play Console's private reviewer fields;
  never commit credentials, private network addresses, or tokens here.

## Closed testing

- [ ] Create or select a Google Play **Closed testing** track.
- [ ] Upload the locally built AAB to the closed-testing track only. Android is
  not a public production release at this stage.
- [ ] Add the tester list and distribute the opt-in link through a private
  channel.
- [ ] Track tester feedback, crashes, device coverage, and opt-in status for
  the entire test period.
- [ ] If this is a new personal developer account created after November 13,
  2023, keep at least **12 testers continuously opted in for 14 days** before
  applying for production access. Confirm the account type and dates in the
  current Play Console; this requirement is not marked complete here.

Google's current requirement is documented at:
<https://support.google.com/googleplay/android-developer/answer/14151465>

## Production access

- [ ] After the closed-test requirement is satisfied, apply for production
  access from the Play Console dashboard.
- [ ] Complete the production-access questions about the closed test, the app,
  and production readiness.
- [ ] Record the Play Console decision and any requested follow-up testing.
- [ ] Only after production access is granted and the listing is ready, create a
  production release. Until then, do not state that Android is publicly
  available.

## Local release gate

Run these commands from `flutter/monkeycraft`:

```bash
flutter pub get
flutter analyze
flutter build appbundle --release
```

Confirm the generated file, size, SHA-256, `versionName`, and `versionCode`
before handing the AAB to the Play Console owner. Keep the artifact local or
transfer it through an approved private channel; do not add it to the Git
repository.
