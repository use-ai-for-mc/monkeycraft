# monkeycraft-tailscale-helper

Standalone userspace Tailscale helper for MonkeyCraft. JSON Lines v1 on stdin/stdout.
This directory is a P0/P1 spike: it is not yet bundled into the four Minecraft mod trees.

## Protocol

stdin = commands, stdout = protocol only, stderr = redacted diagnostics.

Commands: `start`, `status`, `stop`, `logout`, `shutdown`  
Events: `ready`, `stateChanged`, `authRequired`, `listening`, `error`, `stopped`

See `internal/protocol` and `internal/protocol/testdata/golden`.

## Build

```bash
# host
./scripts/build.sh

# tests (no personal tailnet)
go test ./...
go test -race ./internal/protocol ./internal/redact ./internal/lockfile ./internal/forward ./internal/engine ./internal/backend
./scripts/run-java-harness.sh dist/darwin-arm64/monkeycraft-tailscale-helper
```

Pinned: Go 1.25+, `tailscale.com v1.102.3` (BSD-3-Clause). Upgrade only via a dedicated PR.
