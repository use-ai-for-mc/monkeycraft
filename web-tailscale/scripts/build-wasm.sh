#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
LOCK="$ROOT/LOCK.json"
COMMIT="$(python3 -c 'import json; print(json.load(open("'"$LOCK"'"))["tailscale"]["commit"])')"
TAG="$(python3 -c 'import json; print(json.load(open("'"$LOCK"'"))["tailscale"]["tag"])')"
DIST="$ROOT/dist"
mkdir -p "$DIST" "$ROOT/third_party/tailscale"

GO_BIN="${GO_BIN:-go}"
export GOTOOLCHAIN="${GOTOOLCHAIN:-auto}"

CACHE="$ROOT/.build/cache"
SRC="$ROOT/.build/wasm-src"
mkdir -p "$CACHE" "$SRC"
RAW_GO="$CACHE/wasm_js.upstream.go"
if [[ ! -f "$RAW_GO" ]]; then
  echo "fetching wasm_js.go @$TAG"
  curl -fsSL "https://raw.githubusercontent.com/tailscale/tailscale/${COMMIT}/cmd/tsconnect/wasm/wasm_js.go" -o "$RAW_GO"
fi
curl -fsSL "https://raw.githubusercontent.com/tailscale/tailscale/${COMMIT}/LICENSE" -o "$ROOT/third_party/tailscale/LICENSE"
python3 "$ROOT/scripts/patch-wasm-js.py" "$RAW_GO" "$SRC/main.go"
rm -f "$SRC"/*.upstream.go "$SRC"/wasm_js.go

cat > "$SRC/go.mod" <<EOF
module monkeycraft.dev/web-tailscale-wasm

go 1.26.3

require tailscale.com $TAG
EOF

echo "go get tailscale.com@$TAG (may download matching Go toolchain)"
(
  cd "$SRC"
  "$GO_BIN" get "tailscale.com@$TAG"
  "$GO_BIN" mod tidy
  export GOOS=js GOARCH=wasm
  echo "building wasm with $("$GO_BIN" env GOVERSION)"
  "$GO_BIN" build -trimpath -ldflags "-s -w" -o "$DIST/main.wasm" .
  "$GO_BIN" env GOVERSION > "$DIST/.goversion"
  "$GO_BIN" env GOROOT > "$DIST/.goroot"
)

GO_VER="$(cat "$DIST/.goversion")"
GOROOT="$(cat "$DIST/.goroot")"
WASM_EXEC="$GOROOT/lib/wasm/wasm_exec.js"
if [[ ! -f "$WASM_EXEC" ]]; then
  WASM_EXEC="$GOROOT/misc/wasm/wasm_exec.js"
fi
if [[ ! -f "$WASM_EXEC" ]]; then
  echo "wasm_exec.js not found under $GOROOT" >&2
  exit 1
fi
cp "$WASM_EXEC" "$DIST/wasm_exec.js"
rm -f "$DIST/.goversion" "$DIST/.goroot"

RAW_SHA="$(shasum -a 256 "$DIST/main.wasm" | awk '{print $1}')"
EXEC_SHA="$(shasum -a 256 "$DIST/wasm_exec.js" | awk '{print $1}')"
SIZE="$(wc -c < "$DIST/main.wasm" | tr -d ' ')"
gzip -9 -k -f "$DIST/main.wasm"
GZ_SIZE="$(wc -c < "$DIST/main.wasm.gz" | tr -d ' ')"
python3 - "$DIST/VERSION.json" <<PY
import json, datetime, pathlib, sys
out = pathlib.Path(sys.argv[1])
doc = {
  "schemaVersion": 1,
  "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "tailscaleTag": "$TAG",
  "tailscaleCommit": "$COMMIT",
  "goVersion": "$GO_VER",
  "goos": "js",
  "goarch": "wasm",
  "ldflags": "-s -w",
  "wasm": {"path": "dist/main.wasm", "sha256": "$RAW_SHA", "bytes": int("$SIZE"), "gzipBytes": int("$GZ_SIZE")},
  "wasmExec": {"path": "dist/wasm_exec.js", "sha256": "$EXEC_SHA", "source": "GOROOT/lib/wasm/wasm_exec.js"},
  "license": "BSD-3-Clause",
  "cdn": "forbidden",
}
out.write_text(json.dumps(doc, indent=2) + "\n")
print(out.read_text())
PY
echo "ok sha256=$RAW_SHA bytes=$SIZE gzip=$GZ_SIZE"
