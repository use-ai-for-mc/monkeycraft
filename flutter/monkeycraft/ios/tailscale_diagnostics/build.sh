#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIN=80771313ac4127973677c993889fe215abcf1fbd
SOURCE="$ROOT/third_party/libtailscale/src"
OUT="$ROOT/tailscale_diagnostics/out"
GO_BINARY="${LIBTAILSCALE_DIAGNOSTIC_GO:-/opt/homebrew/bin/go}"
GOFMT_BINARY="$(dirname "$GO_BINARY")/gofmt"
PRODUCT_ARCHIVE="$ROOT/third_party/libtailscale/out/libtailscale_ios.a"
PRODUCT_HASH=ead2e2938edba8eb9ef55aa7bd8027bd25cd2901c2df9da0e6a6c603a2e8beb9

need() { command -v "$1" >/dev/null 2>&1 || { echo "missing required tool: $1" >&2; exit 1; }; }
need ditto
need git
need xcodebuild
test -x "$GO_BINARY" || { echo "missing required Go tool: $GO_BINARY" >&2; exit 1; }
test -x "$GOFMT_BINARY" || { echo "missing required gofmt tool: $GOFMT_BINARY" >&2; exit 1; }
export GOTOOLCHAIN=go1.26.3
test "$("$GO_BINARY" version)" = "go version go1.26.3 darwin/arm64" || { echo "unexpected Go version: $("$GO_BINARY" version)" >&2; exit 1; }
MODULE_CACHE="$($GO_BINARY env GOMODCACHE)"
test "$(shasum -a 256 "$PRODUCT_ARCHIVE" | awk '{print $1}')" = "$PRODUCT_HASH" || { echo "product archive hash changed" >&2; exit 1; }
test -z "$(git -C "$SOURCE" status --porcelain)" || { echo "pinned source is not clean" >&2; exit 1; }
TEMP_ROOT="${TMPDIR:-/tmp}"
TEMP_ROOT="${TEMP_ROOT%/}"
WORK="$(mktemp -d "$TEMP_ROOT/monkeycraft-libtailscale.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$OUT"
ditto "$SOURCE" "$WORK/libtailscale"
ditto "$MODULE_CACHE/tailscale.com@v1.94.1" "$WORK/tailscale.com"
chmod -R u+w "$WORK/tailscale.com"
test "$(git -C "$WORK/libtailscale" rev-parse HEAD)" = "$PIN"
test "$(grep -E '^require tailscale.com v1\.94\.1$' "$WORK/libtailscale/go.mod" | wc -l | tr -d ' ')" = 1
(cd "$WORK/libtailscale" && "$GO_BINARY" mod verify)
(cd "$WORK/tailscale.com" && git apply --check "$ROOT/tailscale_diagnostics/controlclient-numeric.patch" && git apply "$ROOT/tailscale_diagnostics/controlclient-numeric.patch")
(cd "$WORK/libtailscale" && git apply --check "$ROOT/tailscale_diagnostics/libtailscale-numeric.patch" && git apply "$ROOT/tailscale_diagnostics/libtailscale-numeric.patch")
"$GOFMT_BINARY" -w "$WORK/tailscale.com/control/controlclient/monkeycraft_diagnostics.go" "$WORK/libtailscale/tailscale.go"
test -z "$("$GOFMT_BINARY" -d "$WORK/tailscale.com/control/controlclient/monkeycraft_diagnostics.go" "$WORK/libtailscale/tailscale.go")"
printf '\nreplace tailscale.com => %s\n' "$WORK/tailscale.com" >> "$WORK/libtailscale/go.mod"
(
  cd "$WORK/tailscale.com/control/controlclient"
  "$GO_BINARY" test -run TestMonkeycraftDiagnosticBoundedConcurrentReset
)
(
  cd "$WORK/libtailscale"
  "$GO_BINARY" mod verify
  CGO_ENABLED=1 GOOS=ios GOARCH=arm64 CC="$WORK/libtailscale/swift/script/clangwrap-ios.sh" "$GO_BINARY" build -buildmode=c-archive -ldflags=-w -tags=ios -o "$OUT/libtailscale_ios_diagnostic.a"
)
cp "$WORK/libtailscale/tailscale.h" "$OUT/tailscale.h"
shasum -a 256 "$OUT/libtailscale_ios_diagnostic.a" | awk '{print $1}' > "$OUT/libtailscale_ios_diagnostic.a.sha256"
"$GO_BINARY" version > "$OUT/go-version.txt"
printf '{"libtailscaleCommit":"%s","tailscaleModule":"v1.94.1","goVersion":"%s","controlPatchSHA256":"%s","libPatchSHA256":"%s","productArchiveSHA256":"%s"}\n' "$PIN" "$("$GO_BINARY" version)" "$(shasum -a 256 "$ROOT/tailscale_diagnostics/controlclient-numeric.patch" | awk '{print $1}')" "$(shasum -a 256 "$ROOT/tailscale_diagnostics/libtailscale-numeric.patch" | awk '{print $1}')" "$PRODUCT_HASH" > "$OUT/MANIFEST.json"
test "$(shasum -a 256 "$PRODUCT_ARCHIVE" | awk '{print $1}')" = "$PRODUCT_HASH"
echo "diagnostic archive built at $OUT/libtailscale_ios_diagnostic.a"
