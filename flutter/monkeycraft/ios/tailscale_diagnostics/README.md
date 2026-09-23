# iOS Tailscale numeric diagnostics

`build.sh` copies the pinned ignored libtailscale source and pinned `tailscale.com v1.94.1` module to an isolated temporary directory, applies the two tracked patches, and writes a separate device archive to `tailscale_diagnostics/out`. It verifies the product archive before and after building; it never changes it.

The recorder is process-global and resets at native node startup. It records only a bounded 64-event ring with fixed stage numbers: 1 before register `Do`, 2 after `Do`, 3 after a non-200 response body read, 4 after register decode. Each event contains numeric sequence, reset-relative offset milliseconds, elapsed milliseconds, attempt, and HTTP status (zero means no response). The C string returned by `tailscale_diagnostic_json` is owned by the caller and must be released with `free`.

For a signed diagnostic archive, use `build_release.py` after building this library. It replaces only the library archive for that invocation and verifies that the product archive is absent from the diagnostic link flags. The normal Release configuration continues to link only `third_party/libtailscale/out/libtailscale_ios.a`.

The signing build runs `clean build` in its dedicated DerivedData directory and then verifies the complete app signature. This prevents stale Flutter framework resources from passing an incremental Xcode build with an invalid application seal. Only install after that verification succeeds.
