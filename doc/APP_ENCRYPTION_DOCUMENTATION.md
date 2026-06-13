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
- The app includes the Dart `crypto` package only for HMAC-SHA256 authentication challenge responses. This is a standard hash-based message authentication code used to prove knowledge of the connection password; it is not used to encrypt or decrypt user content, media, files, or network traffic.

The app does not include proprietary encryption algorithms, custom encryption protocols, encrypted file storage, VPN functionality, secure messaging, or cryptographic functionality whose primary purpose is confidentiality.

## If This Changes

Revisit this declaration before release if the app adds any of the following:

- Custom encryption or decryption of app data.
- Bundled cryptographic libraries for confidentiality beyond hashing/HMAC.
- End-to-end encrypted messaging, encrypted media storage, VPN/proxy tunneling, or secure file transfer.
- Non-standard or proprietary cryptographic algorithms.
