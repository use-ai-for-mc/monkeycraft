# Store go-live plan for 1.4.1

Status date: 2026-06-18.

## Current local state

- Flutter app version in source: `1.4.1+10`.
- Android release bundle present locally:
  `flutter/monkeycraft/build/app/outputs/bundle/release/app-release.aab`.
- Android release bundle previously recorded:
  SHA-256 `1859b952a5691559bc3b0e231036aef33e97d7b5a91bad6be237bdd8b8a813ca`.
- iOS export compliance is declared in the app and widget plists:
  `ITSAppUsesNonExemptEncryption = false`.

## Current App Store Connect state

- Production iOS version `1.4.1` was resubmitted after metadata and App Review
  Information updates.
- Current App Review issue category shown in App Store Connect:
  `Performance - App Completeness`.
- Build `1.4.1 (11)` is selected for the production version.
- Three iPhone 6.5" screenshots are uploaded.
- Product page metadata, contact information, and private App Review sign-in
  information were saved for the original submission.
- The review item was submitted successfully from the App Store Connect draft
  submission on 2026-06-14 at about 18:35 +0800.
- App Store Version Release is currently set to automatic release after App
  Review approval.
- Refusal issue: App Review said the app's description and promotional text
  included references to a third-party game title, creating a misleading
  association risk.
- Follow-up issue: App Review asked for detailed responses about the app's VPN
  functionality and whether VPN-collected information is collected, used,
  shared, or stored.
- The user applied the metadata/App Review Information updates and resubmitted
  the app in App Store Connect on 2026-06-18.
- Revised metadata and a response draft are in
  `doc/APP_STORE_METADATA_1.4.1.md`.

## Apple: TestFlight to production

Goal: wait for App Review follow-up after metadata-only remediation and VPN
clarification.

Done:

- Selected production build `1.4.1 (11)`.
- Uploaded screenshots.
- Filled product page metadata.
- Saved private App Review contact/sign-in/reviewer notes.
- Added the app version to the App Store Connect draft submission.
- Submitted iOS `1.4.1 (11)` to App Review.
- Resubmitted after removing flagged third-party-title metadata and adding the
  VPN/no-data-collection clarification to App Review Information.

Current Apple status:

1. App Store Connect shows the issue category as `Performance - App
   Completeness`.
2. Wait for the follow-up App Review result.
3. Keep the reviewer demo path online while the review is pending.
4. If the same category remains open, first verify reviewer access to the live
   demo service and the completeness of the App Review Information notes.

Private App Review notes in App Store Connect include the live reviewer demo
connection. Do not duplicate the review password in repo docs. The revised
notes should describe this review path:

```text
MonkeyCraft lets a user control their own supported desktop game client from an
iPhone over localhost, local Wi-Fi, or another private network path configured
by the user outside MonkeyCraft.

Review path:
1. Install the included MonkeyCraft companion mod on the desktop game client.
2. Launch the desktop game client and open the MonkeyCraft QR/password screen.
3. In the iOS app, scan the QR code or enter the connection details manually.
4. Verify the server picker, chat mode, streaming controls, and disconnect flow.

VPN clarification:
MonkeyCraft does not provide VPN functionality and does not create, configure,
manage, or monitor a VPN connection. The app does not use Apple's Network
Extension framework, does not include a packet tunnel or VPN profile, and has no
VPN entitlement. It only opens a direct WebSocket connection to a server address
entered or selected by the user. If a user independently uses Wi-Fi, cellular
networking, or a third-party private-network/VPN app on their device, iOS routes
traffic outside MonkeyCraft's control.

Information collected using VPN:
None. MonkeyCraft does not collect any user information using VPN because it has
no VPN feature.

Purpose of VPN data collection:
Not applicable. No VPN data is collected. Locally, the app may store the user's
server address, connection preferences, and password/credential material on the
user's device so the user can reconnect to their own host. This information is
used only to initiate and authenticate the user-requested connection to the
user's own host.

Third-party sharing and storage:
No VPN data is shared with third parties because no VPN data is collected.
MonkeyCraft does not operate a hosted service for user traffic, and the
developer does not receive or store the user's video stream, controls, chat,
server address, or password. During a session, video, controls, and chat are
exchanged directly between the iOS app and the user-selected host.

This resubmission removes the named third-party title from the app's
Promotional Text, Description, Keywords, and App Review Notes. The app does not
include, distribute, sell, or provide access to that third-party game, hosted
game servers, in-app purchases, or paid content. Network access is
user-provided. The app uses HMAC-SHA256 only for password challenge
authentication and does not use non-exempt encryption.
```

If review asks for a demo account or environment, provide a short screen
recording and the mod setup instructions from
`doc/TEST_PROMPT_remote-server-selection.md`.

## Google Play: unlock production access

Goal: run the mandatory closed test and then apply for production access.

Google's current requirement for newly created personal developer accounts is a
closed test with at least 12 testers opted in for 14 continuous days before
applying for production access.

1. In Play Console, keep using a closed testing track.
2. Upload `flutter/monkeycraft/build/app/outputs/bundle/release/app-release.aab`
   if it is not already the active closed-testing build.
3. Add at least 15-20 testers to the tester list, not just 12. This gives a
   buffer if someone never opts in or drops out.
4. Send testers the opt-in link and ask them to keep the test installed through
   the full 14-day window.
5. Ask each tester to do at least one real session:
   connect to their supported desktop game client, open the server picker, join
   a server, test streaming controls, open chat mode, toggle Data Saver, and
   disconnect.
6. Track tester status:

| Tester | Opted in | Installed | Tested session | Feedback received | Notes |
| --- | --- | --- | --- | --- | --- |
| 1 |  |  |  |  |  |
| 2 |  |  |  |  |  |
| 3 |  |  |  |  |  |
| 4 |  |  |  |  |  |
| 5 |  |  |  |  |  |
| 6 |  |  |  |  |  |
| 7 |  |  |  |  |  |
| 8 |  |  |  |  |  |
| 9 |  |  |  |  |  |
| 10 |  |  |  |  |  |
| 11 |  |  |  |  |  |
| 12 |  |  |  |  |  |
| 13 |  |  |  |  |  |
| 14 |  |  |  |  |  |
| 15 |  |  |  |  |  |

7. After the 14 continuous days, apply for production access from the Play
   Console dashboard.

## Tester invite copy

```text
I am preparing MonkeyCraft for release and need a few Android testers for the
Google Play closed test.

Please opt in with this link, install the app, and keep the test active for at
least 14 days. If you can, try one real session: connect to your supported
desktop game client, open the server picker, join a server, test the streaming
controls, chat mode, Data Saver, and disconnect/reconnect.

Useful feedback:
- Did setup or pairing feel confusing?
- Did video/control latency feel usable?
- Did anything crash, freeze, or disconnect unexpectedly?
- What Android device and version did you test on?
```

## Play production-access answer draft

```text
MonkeyCraft was tested by a closed group of Android testers before production.
Testers were asked to install the Google Play closed-testing build, connect the
mobile app to a supported desktop game client running the MonkeyCraft companion
mod, and exercise the main release flows: QR/manual pairing, server picker,
joining and leaving a server, streaming controls, chat mode, Data Saver,
notifications, and disconnect/reconnect behavior.

Feedback focused on setup clarity, device compatibility, stream/control
latency, crashes, freezes, and connection reliability. The 1.4.1 release was
also validated locally on Android emulator and iOS simulator, and the companion
mod side was regression-tested across all supported desktop game versions.

The app is ready for production because the core pairing, server selection,
streaming, chat, and session lifecycle flows have been exercised by testers and
the release build has passed local release validation.
```
