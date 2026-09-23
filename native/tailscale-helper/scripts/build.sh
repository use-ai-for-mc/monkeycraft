#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
source "$ROOT/scripts/resolve-go-toolchain.sh"
resolve_go_toolchain "$ROOT"

GOOS="${GOOS:-$("$GO_BIN" env GOOS)}"
GOARCH="${GOARCH:-$("$GO_BIN" env GOARCH)}"
COMMIT="$(git -C "$ROOT/../.." rev-parse --short HEAD 2>/dev/null || echo unknown)"
VERSION="${HELPER_VERSION:-0.1.0-p1}"
TS_VERSION="$("$GO_BIN" list -m -f '{{.Version}}' tailscale.com)"
OUT_DIR="${OUT_DIR:-$ROOT/dist/$GOOS-$GOARCH}"
NAME="monkeycraft-tailscale-helper"
if [[ "$GOOS" == windows ]]; then
  NAME="${NAME}.exe"
fi
mkdir -p "$OUT_DIR"
LDFLAGS="-s -w -X github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/version.Version=${VERSION} -X github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/version.GitCommit=${COMMIT} -X github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/version.Tailscale=${TS_VERSION}"

echo "building GOOS=$GOOS GOARCH=$GOARCH go=$GO_TOOLCHAIN_VERSION helperVersion=$VERSION tailscale=$TS_VERSION commit=$COMMIT"
CGO_ENABLED=0 GOOS="$GOOS" GOARCH="$GOARCH" "$GO_BIN" build -trimpath -ldflags "$LDFLAGS" -o "$OUT_DIR/$NAME" ./cmd/monkeycraft-tailscale-helper
HASH="$(shasum -a 256 "$OUT_DIR/$NAME" | awk '{print $1}')"
SIZE="$(wc -c < "$OUT_DIR/$NAME" | tr -d ' ')"
cat > "$OUT_DIR/manifest.json" <<EOF
{
  "name": "$NAME",
  "helperVersion": "$VERSION",
  "protocolVersion": 1,
  "goos": "$GOOS",
  "goarch": "$GOARCH",
  "goVersion": "$("$GO_BIN" env GOVERSION)",
  "tailscale": "$TS_VERSION",
  "gitCommit": "$COMMIT",
  "sha256": "$HASH",
  "size": $SIZE
}
EOF
echo "$HASH  $NAME" > "$OUT_DIR/$NAME.sha256"
echo "wrote $OUT_DIR/$NAME ($SIZE bytes sha256=$HASH)"
