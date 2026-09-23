# Flutter browser CI evidence

The Pages workflow installs Chrome for Testing `153.0.8010.52` with the pinned
`browser-actions/setup-chrome` commit
`54e7c7bf1c147ffca98dc47b796907454c8c1787` (the action's v2.2.0 release).

The Pages provenance manifest records six actual full-SHA Actions pins:
checkout, Node setup, Chrome setup, Pages artifact upload, Pages configuration,
and Pages deployment. The workflow has no pnpm installation because Flutter and
the built-in Node runtime are sufficient for its build and provenance test.

Google's [Chrome for Testing known-good versions list](https://googlechromelabs.github.io/chrome-for-testing/known-good-versions-with-downloads.json)
lists that exact version and its Linux x64 download:

`https://storage.googleapis.com/chrome-for-testing-public/153.0.8010.52/linux64/chrome-linux64.zip`

The CI runner invokes `flutter test --platform chrome` through
`flutter/monkeycraft/tool/run_browser_tests.py`. The script exports 65 H.264
access units from the repository's recorded `streaming-360x640` fixture,
removes MonkeyCraft's six-byte IDR header where present, and serves only that
temporary JSON fixture with CORS enabled. It runs browser audio, notification
backend, pointer/input, and H.264 reset tests.

Local result on 2026-09-19: all 23 browser tests passed with installed Google
Chrome `153.0.8010.53`. This is a local compatibility result, not a CI run; CI
uses the explicitly downloadable `153.0.8010.52` build above.

Latest combined-run log: `outputs/flutter-web-feasibility-2026-09-19/browser-suite-23.log`. The first invocation mistakenly supplied a JSON path to the fixture-name argument; it exited before tests. The corrected default-fixture invocation completed successfully.
