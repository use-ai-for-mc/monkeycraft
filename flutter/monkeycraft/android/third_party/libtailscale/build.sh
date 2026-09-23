#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
PIN_COMMIT="80771313ac4127973677c993889fe215abcf1fbd"
SRC="${LIBTAILSCALE_SRC:-$ROOT/src}"
OUTPUT_ROOT="$ROOT/out"
OUT=""
WORK_ROOT=""
PATCH="$ROOT/product-userlog-discard.patch"
OVERLAY="$ROOT/overlay/android_netmon.go"
ANDROID_API="${ANDROID_API:-24}"
NDK_VERSION="${NDK_VERSION:-28.2.13676358}"
SONAME="libtailscale_monkeycraft.so"
GO_BIN="${GO_BIN:-}"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required tool: $1" >&2
    exit 1
  }
}

cleanup() {
  if [[ -n "$WORK_ROOT" ]]; then
    rm -rf "$WORK_ROOT"
  fi
}
trap cleanup EXIT

need git
need python3
need shasum
need tar

if [[ -z "$GO_BIN" ]]; then
  for candidate in "$(command -v go 2>/dev/null || true)" /opt/homebrew/bin/go /usr/local/bin/go; do
    [[ -x "$candidate" ]] || continue
    version="$($candidate env GOVERSION 2>/dev/null || true)"
    version="${version#go}"
    major="${version%%.*}"
    remainder="${version#*.}"
    minor="${remainder%%.*}"
    if [[ "$major" =~ ^[0-9]+$ && "$minor" =~ ^[0-9]+$ ]] && (( major > 1 || (major == 1 && minor >= 25) )); then
      GO_BIN="$candidate"
      break
    fi
  done
fi

if [[ ! -x "$GO_BIN" ]]; then
  echo "Go 1.25 or newer is required; set GO_BIN to the go executable" >&2
  exit 1
fi

if [[ -z "${ANDROID_NDK_HOME:-}" ]]; then
  if [[ -d "${ANDROID_HOME:-}/ndk/${NDK_VERSION}" ]]; then
    ANDROID_NDK_HOME="${ANDROID_HOME}/ndk/${NDK_VERSION}"
  elif [[ -d "$HOME/Library/Android/sdk/ndk/${NDK_VERSION}" ]]; then
    ANDROID_NDK_HOME="$HOME/Library/Android/sdk/ndk/${NDK_VERSION}"
  else
    echo "set ANDROID_NDK_HOME or install NDK ${NDK_VERSION}" >&2
    exit 1
  fi
fi

HOST_TAG=""
for candidate in darwin-x86_64 darwin-arm64 linux-x86_64 linux-aarch64; do
  if [[ -d "$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$candidate" ]]; then
    HOST_TAG="$candidate"
    break
  fi
done
if [[ -z "$HOST_TAG" ]]; then
  echo "NDK llvm toolchain not found under $ANDROID_NDK_HOME/toolchains/llvm/prebuilt" >&2
  exit 1
fi
LLVM="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/$HOST_TAG"
CLANG_BIN="$LLVM/bin"

if [[ ! -d "$SRC/.git" ]]; then
  git clone --depth 1 https://github.com/tailscale/libtailscale.git "$SRC"
fi
git -C "$SRC" fetch --depth 1 origin "$PIN_COMMIT"
WORK_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/monkeycraft-android-native.XXXXXX")"
BUILD_SRC="$WORK_ROOT/src"
OUT="$WORK_ROOT/out"
mkdir -p "$BUILD_SRC" "$OUT"
git -C "$SRC" archive "$PIN_COMMIT" | tar -x -C "$BUILD_SRC"
git -C "$BUILD_SRC" apply --check "$PATCH"
git -C "$BUILD_SRC" apply "$PATCH"
cp "$OVERLAY" "$BUILD_SRC/android_netmon.go"

REQUIRED_SYMS=(
  MonkeycraftAndroidInit
  MonkeycraftDialTimeout
  tailscale_new
  tailscale_start
  tailscale_up
  tailscale_close
  tailscale_set_dir
  tailscale_set_hostname
  tailscale_set_control_url
  tailscale_set_ephemeral
  tailscale_set_logfd
  tailscale_errmsg
  tailscale_status_json
  tailscale_loopback
  tailscale_dial
  tailscale_listen
  tailscale_accept
  tailscale_getips
  tailscale_getremoteaddr
  tailscale_enable_funnel_to_localhost_plaintext_http1
)

build_abi() {
  local abi="$1"
  local goarch="$2"
  local triple="$3"
  local extra_env="$4"
  local outdir="$OUT/$abi"
  mkdir -p "$outdir"
  local cc="$CLANG_BIN/${triple}${ANDROID_API}-clang"
  if [[ ! -x "$cc" ]]; then
    echo "missing NDK clang: $cc" >&2
    exit 1
  fi
  echo "building $abi GOARCH=$goarch CC=$(basename "$cc")"
  (
    cd "$BUILD_SRC"
    export CGO_ENABLED=1
    export GOOS=android
    export GOARCH="$goarch"
    export CC="$cc"
    if [[ -n "$extra_env" ]]; then
      eval "export $extra_env"
    fi
    "$GO_BIN" build -mod=mod -trimpath -buildmode=c-shared -ldflags "-s -w" -o "$outdir/$SONAME" .
  )
  if [[ -x "$CLANG_BIN/llvm-strip" ]]; then
    "$CLANG_BIN/llvm-strip" --strip-unneeded "$outdir/$SONAME" || true
  fi
  cp "$BUILD_SRC/tailscale.h" "$outdir/tailscale.h"
  local missing=0
  local nm_bin="nm"
  if [[ -x "$CLANG_BIN/llvm-nm" ]]; then
    nm_bin="$CLANG_BIN/llvm-nm"
  fi
  local nm_out
  nm_out="$("$nm_bin" -D --defined-only "$outdir/$SONAME" 2>/dev/null || "$nm_bin" -g "$outdir/$SONAME")"
  for sym in "${REQUIRED_SYMS[@]}"; do
    if ! grep -E "[[:space:]]T[[:space:]]+${sym}$" <<<"$nm_out" >/dev/null && ! grep -E "[[:space:]]${sym}$" <<<"$nm_out" >/dev/null; then
      echo "missing symbol $sym in $abi" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    exit 1
  fi
  shasum -a 256 "$outdir/$SONAME" | awk '{print $1}' > "$outdir/$SONAME.sha256"
  echo "built $outdir/$SONAME ($(wc -c < "$outdir/$SONAME" | tr -d ' ') bytes)"
}

build_abi "arm64-v8a" "arm64" "aarch64-linux-android" ""
build_abi "armeabi-v7a" "arm" "armv7a-linux-androideabi" "GOARM=7"

python3 - "$OUT" "$PIN_COMMIT" "$OVERLAY" "$ANDROID_NDK_HOME" "$NDK_VERSION" "$ANDROID_API" "$GO_BIN" "$PATCH" <<'PY'
import hashlib, json, os, subprocess, sys, datetime
out, commit, overlay, ndk, ndk_ver, api, go_bin, patch = sys.argv[1:9]
def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()
go_ver = subprocess.check_output([go_bin, "env", "GOVERSION"], text=True).strip()
manifest = {
  "builtAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
  "libtailscaleCommit": commit,
  "tailscaleGoModule": "tailscale.com v1.94.1",
  "goVersion": go_ver,
  "ndkHome": ndk,
  "ndkVersion": ndk_ver,
  "androidApi": int(api),
  "overlay": {
    "path": "overlay/android_netmon.go",
    "sha256": sha256(overlay),
    "bytes": os.path.getsize(overlay),
  },
  "productPatch": {"path": "product-userlog-discard.patch", "sha256": sha256(patch)},
  "artifacts": {},
}
for abi in ("arm64-v8a", "armeabi-v7a"):
    so = os.path.join(out, abi, "libtailscale_monkeycraft.so")
    hdr = os.path.join(out, abi, "tailscale.h")
    entry = {
      "so": {
        "sha256": sha256(so),
        "bytes": os.path.getsize(so),
      },
    }
    if os.path.isfile(hdr):
        entry["header"] = {"sha256": sha256(hdr), "bytes": os.path.getsize(hdr)}
    manifest["artifacts"][abi] = entry
with open(os.path.join(out, "MANIFEST.json"), "w") as f:
    json.dump(manifest, f, indent=2)
    f.write("\n")
print("wrote", os.path.join(out, "MANIFEST.json"))
PY

mkdir -p "$OUTPUT_ROOT"
for abi in arm64-v8a armeabi-v7a; do
  mkdir -p "$OUTPUT_ROOT/$abi"
  for artifact in "$SONAME" "$SONAME.sha256" tailscale.h; do
    cp "$OUT/$abi/$artifact" "$OUTPUT_ROOT/$abi/$artifact.new"
    mv "$OUTPUT_ROOT/$abi/$artifact.new" "$OUTPUT_ROOT/$abi/$artifact"
  done
done
cp "$OUT/MANIFEST.json" "$OUTPUT_ROOT/MANIFEST.json.new"
mv "$OUTPUT_ROOT/MANIFEST.json.new" "$OUTPUT_ROOT/MANIFEST.json"
printf 'Installed verified native libraries in %s\n' "$OUTPUT_ROOT"
