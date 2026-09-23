#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PIN_COMMIT="80771313ac4127973677c993889fe215abcf1fbd"
SRC="${LIBTAILSCALE_SRC:-$ROOT/src}"
OUT="$ROOT/out"
TARGET="${1:-ios}"
PATCH="$ROOT/product-userlog-discard.patch"
GO_BINARY="${LIBTAILSCALE_GO:-$(command -v go || true)}"
GO_VERSION="go version go1.26.3 darwin/arm64"
ARCHIVE="$OUT/libtailscale_ios.a"
BACKUP="$OUT/libtailscale_ios.pre-userlog-discard.a"
WORK_ROOT=""
WORK_SRC=""

cleanup() {
  if [[ -n "$WORK_ROOT" ]]; then
    rm -rf "$WORK_ROOT"
  fi
}

trap cleanup EXIT

write_link_config() {
  cat > "$ROOT/Link.xcconfig" <<EOF
MONKEYCRAFT_LIBTAILSCALE_IOS_ARCHIVE = \$(PROJECT_DIR)/third_party/libtailscale/out/libtailscale_ios.a
SWIFT_ACTIVE_COMPILATION_CONDITIONS = \$(inherited) MONKEYCRAFT_HAS_LIBTAILSCALE
HEADER_SEARCH_PATHS = \$(inherited) \$(PROJECT_DIR)/third_party/libtailscale/out
LIBRARY_SEARCH_PATHS = \$(inherited) \$(PROJECT_DIR)/third_party/libtailscale/out
OTHER_LDFLAGS[sdk=iphoneos*] = \$(inherited) -force_load \$(MONKEYCRAFT_LIBTAILSCALE_IOS_ARCHIVE) -lresolv
OTHER_LDFLAGS[sdk=iphonesimulator*] = \$(inherited) -force_load \$(PROJECT_DIR)/third_party/libtailscale/out/libtailscale_ios_sim.a -lresolv
EOF
}

if [[ "$TARGET" == link-config ]]; then
  write_link_config
  exit 0
fi

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required tool: $1" >&2
    exit 1
  }
}

need git
need xcodebuild
need lipo
need ditto
need python3
need grep
test -n "$GO_BINARY" && test -x "$GO_BINARY" || {
  echo "missing Go 1.26.3; set LIBTAILSCALE_GO to its bin/go path" >&2
  exit 1
}
test "$("$GO_BINARY" version)" = "$GO_VERSION" || {
  echo "unexpected Go version: $("$GO_BINARY" version)" >&2
  exit 1
}
test -f "$PATCH" || { echo "missing product safety patch: $PATCH" >&2; exit 1; }

if [[ -d "$SRC/.git" ]]; then
  test -z "$(git -C "$SRC" status --porcelain)" || {
    echo "pinned source is not clean; refusing to overwrite it" >&2
    exit 1
  }
else
  git clone --depth 1 https://github.com/tailscale/libtailscale.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$PIN_COMMIT"
git -C "$SRC" checkout --detach "$PIN_COMMIT"
test -z "$(git -C "$SRC" status --porcelain)" || { echo "pinned source is not clean after checkout" >&2; exit 1; }

mkdir -p "$OUT"

prepare_source() {
  local temp_root
  temp_root="${TMPDIR:-/tmp}"
  temp_root="${temp_root%/}"
  WORK_ROOT="$(mktemp -d "$temp_root/monkeycraft-libtailscale-product.XXXXXX")"
  WORK_SRC="$WORK_ROOT/src"
  ditto "$SRC" "$WORK_SRC"
  git -C "$WORK_SRC" apply --check "$PATCH"
  git -C "$WORK_SRC" apply "$PATCH"
  test -z "$(git -C "$WORK_SRC" status --porcelain | grep -v '^ M tailscale.go$')" || {
    echo "unexpected product source changes" >&2
    exit 1
  }
  test "$(grep -Fc 'UserLogf: logger.Discard' "$WORK_SRC/tailscale.go")" = 1 || {
    echo "product safety patch did not set UserLogf to discard" >&2
    exit 1
  }
  (
    cd "$WORK_SRC"
    "$GO_BINARY" mod verify
    "$GO_BINARY" list -m -json all > "$OUT/DEPENDENCIES.json"
  )
  cp "$WORK_SRC/LICENSE" "$OUT/LICENSE.libtailscale"
  "$GO_BINARY" version > "$OUT/go-version.txt"
}

record_manifest() {
  python3 - "$OUT" "$PIN_COMMIT" "$PATCH" "$GO_VERSION" "$WORK_SRC" <<'PY'
import hashlib, json, os, sys, datetime
out, commit, patch, go_version, source = sys.argv[1:]
def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()
manifest = {
  "builtAt": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "libtailscaleCommit": commit,
  "goVersion": go_version,
  "userLogf": "discard",
  "productPatchSHA256": digest(patch),
  "source": {
    "goModSHA256": digest(os.path.join(source, "go.mod")),
    "goSumSHA256": digest(os.path.join(source, "go.sum")),
    "licenseSHA256": digest(os.path.join(source, "LICENSE")),
  },
  "dependencies": {
    "manifestSHA256": digest(os.path.join(out, "DEPENDENCIES.json")),
  },
  "artifacts": {},
}
for name in os.listdir(out):
    path = os.path.join(out, name)
    if os.path.isfile(path) and name.endswith((".a", ".h")):
        manifest["artifacts"][name] = {"sha256": digest(path), "bytes": os.path.getsize(path)}
with open(os.path.join(out, "MANIFEST.json"), "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
PY
}

case "$TARGET" in
  ios)
    prepare_source
    if [[ -f "$ARCHIVE" && ! -f "$BACKUP" ]]; then
      cp "$ARCHIVE" "$BACKUP"
    fi
    (cd "$WORK_SRC" && make clean c-archive-ios)
    cp "$WORK_SRC/libtailscale_ios.a" "$ARCHIVE"
    cp "$WORK_SRC/tailscale.h" "$OUT/tailscale.h"
    shasum -a 256 "$ARCHIVE" | awk '{print $1}' > "$OUT/libtailscale_ios.a.sha256"
    record_manifest
    echo "built device archive $ARCHIVE"
    echo "use this archive for App Store / device. do not lipo simulator slices into it."
    ;;
  ios-sim)
    prepare_source
    (cd "$WORK_SRC" && make clean c-archive-ios-sim)
    cp "$WORK_SRC/libtailscale_ios_sim.a" "$OUT/libtailscale_ios_sim.a"
    cp "$WORK_SRC/tailscale.h" "$OUT/tailscale.h"
    shasum -a 256 "$OUT/libtailscale_ios_sim.a" | awk '{print $1}' > "$OUT/libtailscale_ios_sim.a.sha256"
    record_manifest
    echo "built simulator archive $OUT/libtailscale_ios_sim.a"
    echo "simulator only; never include this slice in an App Store archive."
    ;;
  ios-fat)
    echo "ios-fat produces TailscaleKit.xcframework with device+simulator."
    echo "That bundle is for local Xcode runs only. App Store archives must use the device framework/archive."
    (cd "$SRC/swift" && make ios-fat)
    rm -rf "$OUT/TailscaleKit.xcframework"
    cp -R "$SRC/swift/build/Build/Products/Release-iphonefat/TailscaleKit.xcframework" "$OUT/TailscaleKit.xcframework"
    ;;
  *)
    echo "usage: $0 [ios|ios-sim|ios-fat|link-config]" >&2
    exit 2
    ;;
esac

write_link_config
