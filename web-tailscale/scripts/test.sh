#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "== go test =="
go test ./internal/...

echo "== go test -race =="
go test -race ./internal/wsframe ./internal/tcpbridge ./internal/rpcschema ./internal/ipnmachine ./internal/redact

echo "== go fuzz (short) =="
go test ./internal/wsframe -fuzz=FuzzReadFrame -fuzztime=5s

echo "== node js tests =="
node js/rpc_test.js
node js/ws-client_test.js
node js/tcp-websocket_test.js

echo "== chrome headless =="
node tests/browser/chrome-headless.mjs

echo "== patch dry-run =="
mkdir -p .build
if [[ ! -f .build/wasm_js.upstream.go ]]; then
  curl -fsSL "https://raw.githubusercontent.com/tailscale/tailscale/53a0d659afa51835dd7a9283873cca44261454f8/cmd/tsconnect/wasm/wasm_js.go" -o .build/wasm_js.upstream.go
fi
python3 scripts/patch-wasm-js.py .build/wasm_js.upstream.go .build/wasm_js.go
python3 - <<'PY'
from pathlib import Path
p = Path(".build/wasm_js.go").read_text()
for s in ["dialTcp", "stableId", "StableID", "connClose", "MonkeyCraft patch"]:
    assert s in p, s
print("patch ok")
PY

echo "all automated tests passed"
