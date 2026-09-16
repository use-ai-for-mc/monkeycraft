#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:?helper binary}"
SRC="$ROOT/harness/java/src"
OUT="$ROOT/harness/java/out"
mkdir -p "$OUT"

run_with_java_home() {
  local home="$1"
  local label="$2"
  echo "-- Java $label ($home)"
  JAVA_HOME="$home" PATH="$home/bin:$PATH" javac --release "${label}" -d "$OUT" "$SRC/HelperIpc.java" "$SRC/HelperIpcTest.java"
  JAVA_HOME="$home" PATH="$home/bin:$PATH" java -cp "$OUT" HelperIpcTest "$BIN"
}

run_with_java_home "/opt/homebrew/Cellar/openjdk@17/17.0.19/libexec/openjdk.jdk/Contents/Home" 17
run_with_java_home "/opt/homebrew/Cellar/openjdk@21/21.0.11/libexec/openjdk.jdk/Contents/Home" 21
run_with_java_home "/opt/homebrew/Cellar/openjdk/25.0.2/libexec/openjdk.jdk/Contents/Home" 25
