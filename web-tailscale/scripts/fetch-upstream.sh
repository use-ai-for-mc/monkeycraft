#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
COMMIT="$(python3 -c 'import json; print(json.load(open("'"$ROOT/LOCK.json"'"))["tailscale"]["commit"])')"
TAG="$(python3 -c 'import json; print(json.load(open("'"$ROOT/LOCK.json"'"))["tailscale"]["tag"])')"
URL="https://github.com/tailscale/tailscale/archive/${COMMIT}.tar.gz"
DEST="$ROOT/.upstream"
TAR="$DEST/tailscale-${COMMIT}.tar.gz"
SRC="$DEST/src"
mkdir -p "$DEST"
if [[ ! -f "$TAR" ]]; then
  echo "fetching $URL"
  curl -fsSL "$URL" -o "$TAR"
fi
SHA="$(shasum -a 256 "$TAR" | awk '{print $1}')"
echo "$SHA  $TAR" > "$DEST/tarball.sha256"
rm -rf "$SRC"
mkdir -p "$SRC"
tar -xzf "$TAR" -C "$SRC" --strip-components=1
echo "extracted $TAG ($COMMIT) to $SRC"
echo "tarball_sha256=$SHA"
echo "$SHA" > "$DEST/tarball.sha256.txt"
if [[ -f "$SRC/LICENSE" ]]; then
  mkdir -p "$ROOT/third_party/tailscale"
  cp "$SRC/LICENSE" "$ROOT/third_party/tailscale/LICENSE"
fi
