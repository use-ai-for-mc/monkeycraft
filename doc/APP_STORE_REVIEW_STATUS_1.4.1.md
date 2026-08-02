# App Store review status for MonkeyCraft 1.4.1

Last updated: 2026-06-18 23:18 +0800.

## Apple status

- App: MonkeyCraft.
- App Store Connect app ID: `6759430770`.
- Submitted version: iOS `1.4.1`.
- Submitted build: `1.4.1 (11)`.
- Current status after resubmission: resubmitted after metadata and App Review
  Information updates.
- Current App Review issue category shown in App Store Connect:
  `Performance - App Completeness`.
- Submission confirmation shown by App Store Connect: `1 Item Submitted`.
- Release setting: automatic release after App Review approval.
- Refusal issue: App Review said the app's description and promotional text
  included references to a third-party game title, creating a misleading
  association risk.
- Follow-up App Review issue: Apple asked for detailed responses about the
  app's VPN functionality and whether VPN-collected information is collected,
  used, shared, or stored.

## Reviewer access

- The private App Review Information in App Store Connect contains the live
  reviewer connection details.
- Do not duplicate the review password in repo docs.
- Reviewer server URL recorded in App Store Connect uses the public Tailscale
  Funnel endpoint with port `8443`.
- Local Tailscale status was checked before submission: the Funnel endpoint on
  `:8443` forwards to the local Java WebSocket service on `127.0.0.1:9600`.
- The user confirmed the external connection succeeded before final submission.

## What was completed

- Production build `1.4.1 (11)` selected.
- iPhone and iPad screenshots uploaded.
- Product page metadata was saved for the original submission.
- App Review contact/sign-in/reviewer notes saved.
- Pricing and availability set for global release.
- Privacy practices completed as Data Not Collected.
- App category, content rights, and age rating completed.
- App version added to the draft submission and submitted to App Review.
- Updated metadata draft prepared in `doc/APP_STORE_METADATA_1.4.1.md` to
  remove the named third-party game title from Promotional Text, Description,
  Keywords, and App Review Notes.
- Updated App Review Information and reply draft prepared in
  `doc/APP_STORE_METADATA_1.4.1.md` to clarify that MonkeyCraft has no VPN
  functionality, no Network Extension entitlement, no packet tunnel, and no
  VPN data collection or sharing.
- The user applied the metadata/App Review Information updates and resubmitted
  the app in App Store Connect on 2026-06-18.

## Next steps

- Wait for the follow-up App Review result.
- Keep the reviewer demo machine, Tailscale Funnel, and WebSocket service
  available while the review is pending.
- If App Review keeps the `Performance - App Completeness` issue open, first
  check whether the reviewer could reach the live demo service and whether the
  App Review Information notes still include complete connection instructions.
- If Apple asks for more information after resubmission, respond from the saved
  App Store Connect App Review notes,
  `doc/APP_STORE_METADATA_1.4.1.md`, and
  `doc/TEST_PROMPT_remote-server-selection.md`.
- Google Play production access is deferred until closed testing testers are
  available; APK sideload distribution is still usable meanwhile.
