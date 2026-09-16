#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIST="$ROOT/native/tailscale-helper/dist"
if [[ ! -d "$DIST/darwin-arm64" ]]; then
  echo "build helpers first: (cd native/tailscale-helper && ./scripts/build.sh)" >&2
  exit 1
fi
echo "Gradle processResources copies from $DIST into mods/26.2 on build."
ls -la "$DIST"/*/monkeycraft-tailscale-helper* 2>/dev/null || true
