#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/resolve-go-toolchain.sh"
resolve_go_toolchain "$ROOT"

echo "== go test =="
"$GO_BIN" test ./internal/protocol ./internal/redact ./internal/lockfile ./internal/forward ./internal/backend ./internal/engine

echo "== race (portable core) =="
"$GO_BIN" test -race ./internal/protocol ./internal/redact ./internal/lockfile ./internal/forward ./internal/engine ./internal/backend

echo "== build host helper =="
bash "$ROOT/scripts/build.sh"
HOST_BIN="$ROOT/dist/$("$GO_BIN" env GOOS)-$("$GO_BIN" env GOARCH)/monkeycraft-tailscale-helper"
"$HOST_BIN" -version

echo "== compile-only windows/linux amd64 =="
for pair in windows/amd64 linux/amd64 linux/arm64 darwin/amd64; do
  GO_BIN="$GO_BIN" GOOS="${pair%/*}" GOARCH="${pair#*/}" bash "$ROOT/scripts/build.sh"
done

echo "== java harness 17/21/25 =="
bash "$ROOT/scripts/run-java-harness.sh" "$HOST_BIN"
