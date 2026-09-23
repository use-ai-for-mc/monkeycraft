#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/resolve-go-toolchain.sh"
resolve_go_toolchain "$ROOT"
for platform in darwin-amd64 darwin-arm64 linux-amd64 windows-amd64; do
  GO_BIN="$GO_BIN" GOOS="${platform%-*}" GOARCH="${platform#*-}" "$ROOT/scripts/build.sh"
done
