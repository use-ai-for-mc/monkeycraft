#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
if [[ ! -f "$ROOT/../out/arm64-v8a/libtailscale_monkeycraft.so" ]]; then
  echo "run ../build.sh first" >&2
  exit 1
fi
if [[ -z "${JAVA_HOME:-}" ]] || ! "$JAVA_HOME/bin/java" -version 2>&1 | grep -q '"1[17]\.\|"21\.'; then
  if [[ -d "/opt/homebrew/Cellar/openjdk@21/21.0.11/libexec/openjdk.jdk/Contents/Home" ]]; then
    export JAVA_HOME="/opt/homebrew/Cellar/openjdk@21/21.0.11/libexec/openjdk.jdk/Contents/Home"
  elif command -v /usr/libexec/java_home >/dev/null; then
    export JAVA_HOME="$(/usr/libexec/java_home -v 21)"
  fi
fi
echo "JAVA_HOME=$JAVA_HOME"
cd "$ROOT"
exec ./gradlew :app:assembleDebug "$@"
