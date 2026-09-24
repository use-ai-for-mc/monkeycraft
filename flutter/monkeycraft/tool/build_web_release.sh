#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
repo_dir="$(cd "$project_dir/../.." && pwd)"
verify_release="$project_dir/tool/verify_web_release.py"
pages_base="${1:-${MONKEYCRAFT_PAGES_BASE:-/monkeycraft/}}"
flutter_bin="${FLUTTER_BIN:-flutter}"
pages_output_arg="${2:-build/pages}"
web_tailscale="${MONKEYCRAFT_WEB_TAILSCALE:-}"
if [[ -z "$web_tailscale" ]]; then
  if [[ "$pages_base" == "/" ]]; then web_tailscale=0; else web_tailscale=1; fi
fi

case "$pages_base" in
  /|/*/) ;;
  *)
    echo "Pages base must start and end with / (for example /monkeycraft/)" >&2
    exit 2
    ;;
esac

flutter_bin_path="$(command -v "$flutter_bin")"
while [[ -L "$flutter_bin_path" ]]; do
  flutter_bin_dir="$(cd -P "$(dirname "$flutter_bin_path")" && pwd)"
  flutter_bin_link="$(readlink "$flutter_bin_path")"
  if [[ "$flutter_bin_link" == /* ]]; then
    flutter_bin_path="$flutter_bin_link"
  else
    flutter_bin_path="$flutter_bin_dir/$flutter_bin_link"
  fi
done
flutter_bin_path="$(cd -P "$(dirname "$flutter_bin_path")" && pwd)/$(basename "$flutter_bin_path")"
flutter_root="$(cd "$(dirname "$flutter_bin_path")/.." && pwd)"
flutter_version_json="$flutter_root/bin/cache/flutter.version.json"

if [[ "$pages_output_arg" == /* ]]; then
  pages_output="$pages_output_arg"
else
  pages_output="$project_dir/$pages_output_arg"
fi
pages_output="$(python3 -c 'from pathlib import Path; import sys; print(Path(sys.argv[1]).resolve())' "$pages_output")"
canonical_output="$project_dir/build/web"
case "$pages_output" in
  "$canonical_output"/*)
    echo "Web release output must not be nested inside build/web" >&2
    exit 2
    ;;
  "$project_dir"/build/*) ;;
  *)
    echo "Web output must be inside $project_dir/build" >&2
    exit 2
    ;;
esac

if [[ ! -f "$flutter_version_json" ]]; then
  echo "Flutter version metadata was not found at $flutter_version_json" >&2
  exit 2
fi

cd "$project_dir"
rm -rf "$canonical_output"
"$flutter_bin_path" build web \
  --release \
  --base-href "$pages_base" \
  --no-web-resources-cdn \
  --dart-define=MONKEYCRAFT_WEB_TAILSCALE="$([[ "$web_tailscale" == "1" ]] && echo true || echo false)"

rm -rf "$canonical_output/tailscale"
if [[ "$web_tailscale" == "1" ]]; then
  wasm_output="$repo_dir/web-tailscale/.build/pages-dist"
  MONKEYCRAFT_WASM_OUTPUT="$wasm_output" bash "$repo_dir/web-tailscale/scripts/build-wasm.sh"
  mkdir -p "$canonical_output/tailscale"
  for asset in worker.js rpc.js fake-backend.js state-store.js; do
    cp "$repo_dir/web-tailscale/js/$asset" "$canonical_output/tailscale/"
  done
  for asset in main.wasm wasm_exec.js VERSION.json; do
    cp "$wasm_output/$asset" "$canonical_output/tailscale/"
  done
  cp "$repo_dir/web-tailscale/third_party/tailscale/LICENSE" "$canonical_output/tailscale/LICENSE"
fi
python3 "$verify_release" "$canonical_output" "$pages_base"

if [[ "$pages_output" != "$canonical_output" ]]; then
  output_parent="$(dirname "$pages_output")"
  mkdir -p "$output_parent"
  output_stage="$(mktemp -d "$output_parent/.monkeycraft-web-release.XXXXXX")"
  output_backup=""
  output_installed=0
  cleanup_release_stage() {
    local status=$?
    if [[ "$output_installed" == "1" && ( -e "$pages_output" || -L "$pages_output" ) ]]; then
      rm -rf "$pages_output"
    fi
    if [[ -n "$output_backup" && ( -e "$output_backup/previous" || -L "$output_backup/previous" ) ]]; then
      mv "$output_backup/previous" "$pages_output"
    fi
    [[ -n "${output_stage:-}" && -d "$output_stage" ]] && rm -rf "$output_stage"
    [[ -n "$output_backup" && -d "$output_backup" ]] && rm -rf "$output_backup"
    trap - EXIT
    exit "$status"
  }
  trap cleanup_release_stage EXIT
  cp -R "$canonical_output/." "$output_stage/"
  python3 "$verify_release" "$output_stage" "$pages_base"

  if [[ -e "$pages_output" || -L "$pages_output" ]]; then
    output_backup="$(mktemp -d "$output_parent/.monkeycraft-web-backup.XXXXXX")"
    mv "$pages_output" "$output_backup/previous"
  fi
  if ! mv "$output_stage" "$pages_output"; then
    echo "Unable to install Flutter Web release; restoring previous output" >&2
    exit 1
  fi
  output_stage=""
  output_installed=1
fi

python3 "$verify_release" "$pages_output" "$pages_base"

if [[ "${MONKEYCRAFT_PAGES_PROVENANCE:-1}" == "1" ]]; then
  export MONKEYCRAFT_PAGES_BASE="$pages_base"
  export MONKEYCRAFT_PAGES_FLAVOR="flutter-web"
  export MONKEYCRAFT_FLUTTER_VERSION_JSON="$flutter_version_json"
  node "$repo_dir/web/tools/write-pages-provenance.mjs" "$pages_output"
fi

if [[ "$pages_output" != "$canonical_output" ]]; then
  rm -rf "$output_backup"
  output_backup=""
  output_installed=0
  trap - EXIT
fi
