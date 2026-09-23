# App Encryption Documentation

Updated 2026-09-19. The embedded Tailscale build requires a release-specific review. The earlier conclusion that this app only used platform networking and HMAC is no longer a sufficient technical basis for an App Store Connect answer.

## Current build facts

- Runner and the Live Activity extension currently contain `ITSAppUsesNonExemptEncryption = false` in their source Info.plist files. This records the repository value; it is not proof that Apple has approved that answer for this build.
- Runner statically links the device libtailscale archive, starts an embedded node and dials through it. Its pinned dependencies include `tailscale/wireguard-go` and third-party cryptographic libraries.
- HTTPS/WSS through Flutter/WebKit, platform secure storage and HMAC-SHA256 authentication remain part of the product, but no longer describe all of its cryptographic functionality.
- System Tailscale and the embedded node remain optional connection paths. Optional use does not mean the linked implementation is absent from the app binary.

The precise inputs, source paths, current Apple guidance and unresolved release questions are recorded in [iOS embedded Tailscale export review](tailscale-integration/IOS_EXPORT_REVIEW.md).

## Release status

No App Store Connect questionnaire, approved encryption document, distribution-region selection or compliance code was inspected or submitted in this development round. Whether the present build qualifies for a documentation exemption remains unverified; the source plist value has not been changed on an assumed classification.

Before distributing this embedded-network version, the publisher should use the current functionality and final device archive to complete Apple's applicable questionnaire and reconcile the final bundle metadata with that assessment. This document does not choose a legal export classification or declare that additional documentation is or is not required. See [Apple's export compliance overview](https://developer.apple.com/help/app-store-connect/manage-app-information/overview-of-export-compliance).
