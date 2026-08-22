# App Encryption Documentation

MonkeyCraft does not use non-exempt encryption.

## App Store Connect Declaration

- `ITSAppUsesNonExemptEncryption`: `false`
- App Store Connect answer: the app does not use non-exempt encryption.
- No additional export compliance documentation is expected for the current iOS build.

## Technical Basis

The iOS app uses platform-provided network and storage security:

- HTTPS/WSS connections are handled through the Flutter/iOS networking stack and WebKit.
- Saved passwords are stored through `flutter_secure_storage`, which uses the platform secure storage facilities.
- MonkeyCraft sessions use standard TLS through the Flutter/iOS networking stack. Direct connections authenticate the mod's self-signed certificate with a SHA-256 fingerprint scanned from the in-game QR code; TLS-terminating domain tunnels use normal platform WebPKI validation.
- The app includes the Dart `crypto` package for HMAC-SHA256 authentication challenge responses and SHA-256 certificate fingerprints. It does not implement a proprietary cipher or TLS protocol.

The app does not include proprietary encryption algorithms, custom encryption protocols, encrypted file storage, VPN functionality, secure messaging, or cryptographic functionality whose primary purpose is confidentiality.

## If This Changes

Revisit this declaration before release if the app adds any of the following:

- Custom encryption or decryption of app data.
- Bundled proprietary cryptographic libraries beyond standard platform TLS and hashing/HMAC.
- End-to-end encrypted messaging, encrypted media storage, VPN/proxy tunneling, or secure file transfer.
- Non-standard or proprietary cryptographic algorithms.
