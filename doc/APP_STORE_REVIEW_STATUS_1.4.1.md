# App Store review status for MonkeyCraft 1.4.1

Last updated: 2026-06-14 18:36 +0800.

## Apple status

- App: MonkeyCraft.
- App Store Connect app ID: `6759430770`.
- Submitted version: iOS `1.4.1`.
- Submitted build: `1.4.1 (11)`.
- Current status after submission: `Waiting for Review`.
- Submission confirmation shown by App Store Connect: `1 Item Submitted`.
- App Store Connect said review can take up to 48 hours and will email when
  review is complete.
- Release setting: automatic release after App Review approval.

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
- Product page metadata saved.
- App Review contact/sign-in/reviewer notes saved.
- Pricing and availability set for global release.
- Privacy practices completed as Data Not Collected.
- App category, content rights, and age rating completed.
- App version added to the draft submission and submitted to App Review.

## Next steps

- Wait for Apple review.
- Keep the reviewer demo machine, Tailscale Funnel, and Minecraft/WebSocket
  service available while the review is pending.
- If Apple asks for more information, respond from the saved App Store Connect
  App Review notes and `doc/TEST_PROMPT_remote-server-selection.md`.
- Google Play production access is deferred until closed testing testers are
  available; APK sideload distribution is still usable meanwhile.
