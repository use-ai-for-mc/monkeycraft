# monkeycraft-tailscale-helper

Standalone userspace Tailscale helper for MonkeyCraft. JSON Lines v1 on stdin/stdout.
It is bundled in the Minecraft 26.2 mod tree. Porting to 26.1, 1.21.11, and 1.19 remains pending.

## Protocol

stdin = commands, stdout = protocol only, stderr = redacted diagnostics.

Commands: `start`, `status`, `stop`, `logout`, `shutdown`  
Events: `ready`, `stateChanged`, `authRequired`, `listening`, `error`, `stopped`

See `internal/protocol` and `internal/protocol/testdata/golden`.

## Build

```bash
# host; resolves a compatible Go toolchain automatically
./scripts/build.sh

# tests (no personal tailnet)
go test ./...
go test -race ./internal/protocol ./internal/redact ./internal/lockfile ./internal/forward ./internal/engine ./internal/backend
./scripts/run-java-harness.sh dist/darwin-arm64/monkeycraft-tailscale-helper
```

The module requires Go 1.26.6. Set `GO_BIN=/path/to/go` to select a specific executable; otherwise
the scripts use `go` from PATH or supported Homebrew locations and require its automatic toolchain
selection to resolve Go 1.26.6. Pinned: `tailscale.com v1.102.3` (BSD-3-Clause). Upgrade only via a dedicated PR.
