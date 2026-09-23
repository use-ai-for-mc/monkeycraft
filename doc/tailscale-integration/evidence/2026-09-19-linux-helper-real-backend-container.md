# 2026-09-19 — Linux helper production-backend container smoke

## Environment and isolation

This used the existing local `php:8.3-cli` arm64 image only as a root filesystem. Docker
Linux/aarch64 translated the statically linked, read-only-mounted `linux/amd64` helper. The
container ran with `--pull=never`, `--network=none`, `--read-only`, `--cap-drop=ALL`,
`no-new-privileges`, 256 MiB memory, one CPU, and an isolated `/state` tmpfs. It received no
user state, account material, credentials, or writable host mount.

## Result

The helper ran its production backend, without `--fake`, and exited `0`. Its JSON Lines v1
output contained `ready`, `starting`, and then `needsLogin`; the delayed `status` request also
reported `needsLogin`. A subsequent `stop` request emitted `stopped`, then stdin was closed for
the parent-EOF path. The named `--rm` container was absent after exit. No timeout or forced
cleanup was needed.

Stderr confirms that tsnet initialized its state at `/state/tailscaled.state`, started with a
generated hostname, and entered `NeedsLogin`. Network isolation prevented any login or tailnet
connection. No auth URL, identity, IP address, node ID, listener, or target connection appeared
in the output.

## Boundary

This establishes translated Docker Linux/aarch64 execution of the packaged amd64 helper through
the production tsnet initialization and offline needs-login lifecycle. It does not establish
native x86 behavior, authentication, tailnet interoperability, target forwarding, listener
reachability, or Windows support. Raw result, stdout, and stderr are retained in
`outputs/roadmap-2026-09-19-version-soak/linux-helper-real-backend-*`.
