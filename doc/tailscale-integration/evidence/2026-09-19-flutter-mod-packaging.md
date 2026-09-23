# Flutter Web mod packaging evidence

Date: 2026-09-19

The final root-base Flutter Web build contained 49 regular files. Its ordered
path-and-SHA-256 tree digest was:

```
2b69f6412fa0b12465793a5e96351d5a4c62c891714fa2f4c9887fddab0d5024
```

For each target, `spotlessApply` followed by `./gradlew build` completed
successfully. The packaged `web/` entries were enumerated from the final JAR,
hashed individually, and compared with the root-base source tree. All 49
paths and hashes matched; no `tailscale/` experimental asset was present.

The final command was run from each target directory:
`mods/26.2`, `mods/26.1`, `mods/1.21.11`, and `mods/1.19`. Its exact command
was `./gradlew spotlessApply && ./gradlew build`. `JAVA_HOME` was unset; the
Gradle launcher resolved `/usr/bin/java`, OpenJDK `26.0.1+8-34`. The projects'
configured Java release targets remain 25 for 26.2/26.1, 21 for 1.21.11, and
17 for 1.19. No raw Gradle stdout/stderr file was redirected or saved. Build
success was observed from the command output, and the persisted test evidence
is the JUnit XML beneath each `build/test-results/test/` directory.

The machine-readable companion
`2026-09-19-flutter-mod-packaging.json` contains every root-base resource path
and SHA-256, every final JAR hash, the per-target embedded-resource comparison,
and the exact JUnit XML paths and totals.

| Minecraft target | Final JAR | JAR SHA-256 | Tests | HTTP port tests |
| --- | --- | --- | ---: | ---: |
| 26.2 | `monkeycraft-1.4.2-26.2.jar` | `509ebc70d5b96010add2f59a7e2d63b99f319c17250539d3f1057cb6eac627ca` | 66 passed | 9 passed |
| 26.1 | `monkeycraft-1.4.2-26.1.jar` | `2dd7439444f4ddfaa9dd5698fdbbf87f0a7d9b173edd5a4b0efaf697167c78cf` | 61 passed | 9 passed |
| 1.21.11 | `monkeycraft-1.4.2-1.21.11.jar` | `cd8a64df1dc36f7ad297775bfa2527aaced999ffacef47990b122be3fa60c8d1` | 61 passed | 9 passed |
| 1.19 | `monkeycraft-1.4.2-1.19.jar` | `5b7e3ca61cd3c4bfd052aad8afeb69ca44ac069d26d20cc1f4a77aa6b21c7601` | 61 passed | 9 passed |

The HTTP port suite includes four handoff regressions: a slow 7 MB CanvasKit
download does not delay WebSocket traffic; server stop closes an unhandshaken
slow HTTP handoff; the bounded HTTP capacity rejects a second slow request
while WebSocket traffic remains responsive; and the configurable deadline
closes a slow handoff. The same Java 17-compatible executor implementation and
tests were built for all four targets.

These are local build and automated-test results. No mod JAR was deployed to
PrismLauncher or used in a real Minecraft session in this packaging run.
