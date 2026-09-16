#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SRC="$ROOT/web-tailscale"
DEST="$ROOT/flutter/monkeycraft/web/tailscale"
mkdir -p "$DEST"
cp "$SRC/js/worker.js" "$SRC/js/rpc.js" "$SRC/js/fake-backend.js" "$DEST/"
if [[ -f "$SRC/dist/wasm_exec.js" ]]; then
  cp "$SRC/dist/wasm_exec.js" "$DEST/"
fi
if [[ -f "$SRC/dist/main.wasm" ]]; then
  cp "$SRC/dist/main.wasm" "$DEST/"
  echo "copied main.wasm $(wc -c < "$DEST/main.wasm" | tr -d ' ') bytes"
else
  echo "warning: $SRC/dist/main.wasm missing; run web-tailscale/scripts/build-wasm.sh" >&2
fi
