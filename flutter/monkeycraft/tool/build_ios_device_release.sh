#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
project_dir="$(cd "$script_dir/.." && pwd)"
flutter_bin="${FLUTTER_BIN:-flutter}"

if ! command -v "$flutter_bin" >/dev/null 2>&1; then
  echo "Flutter executable not found: $flutter_bin" >&2
  exit 1
fi

cd "$project_dir"
"$flutter_bin" clean
"$flutter_bin" pub get
"$flutter_bin" build ios --release "$@"
python3 tool/verify_ios_app.py build/ios/iphoneos/Runner.app
