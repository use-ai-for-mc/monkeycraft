#!/usr/bin/env bash

resolve_go_toolchain() {
  local root="$1"
  local required candidate version selected_version
  local required_major required_minor required_patch
  local selected_major selected_minor selected_patch
  local -a candidates=()
  required="$(awk '$1 == "go" { print $2; exit }' "$root/go.mod")"
  if [[ -z "$required" ]]; then
    echo "cannot determine required Go version from $root/go.mod" >&2
    return 1
  fi
  GOTOOLCHAIN=auto
  export GOTOOLCHAIN
  IFS=. read -r required_major required_minor required_patch <<< "$required"
  if [[ -z "$required_major" || -z "$required_minor" || -z "$required_patch" ]]; then
    echo "invalid Go version $required in $root/go.mod" >&2
    return 1
  fi

  if [[ -n "${GO_BIN:-}" ]]; then
    candidates+=("$GO_BIN")
  else
    if command -v go >/dev/null 2>&1; then
      candidates+=("$(command -v go)")
    fi
    candidates+=(/opt/homebrew/bin/go /usr/local/bin/go /usr/local/go/bin/go)
  fi

  for candidate in "${candidates[@]}"; do
    if [[ ! -x "$candidate" ]]; then
      continue
    fi
    version="$("$candidate" version 2>/dev/null || true)"
    if [[ ! "$version" =~ go([0-9]+)\.([0-9]+)(\.([0-9]+))? ]]; then
      continue
    fi
    if ! selected_version="$(cd "$root" && GOTOOLCHAIN=auto "$candidate" env GOVERSION 2>/dev/null)"; then
      continue
    fi
    if [[ "$selected_version" =~ go([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
      selected_major="${BASH_REMATCH[1]}"
      selected_minor="${BASH_REMATCH[2]}"
      selected_patch="${BASH_REMATCH[3]}"
    else
      continue
    fi
    if (( selected_major > required_major ||
          (selected_major == required_major && selected_minor > required_minor) ||
          (selected_major == required_major && selected_minor == required_minor && selected_patch >= required_patch) )); then
      GO_BIN="$candidate"
      GO_TOOLCHAIN_VERSION="$selected_version"
      export GO_BIN GO_TOOLCHAIN_VERSION
      return 0
    fi
  done

  echo "Go $required or newer is required by $root/go.mod. Set GO_BIN to a Go 1.26+ executable; checked: ${candidates[*]}" >&2
  return 1
}
