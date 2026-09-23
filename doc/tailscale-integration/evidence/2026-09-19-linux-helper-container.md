# 2026-09-19 — Linux helper isolated-container probe

## Result

Docker Desktop's Linux daemon is `aarch64` and its only locally available base images are
`linux/arm64`. The first planning pass therefore did not create a container. A second, bounded
pass used the existing `php:8.3-cli` image only as a root filesystem and executed the read-only,
statically linked `linux/amd64` helper directly. Docker's configured translation path ran it:
`--version` returned helper `0.1.0-p1`, protocol `1`, Tailscale `v1.102.3`, and commit
`838bfd5`.

The protocol pass used the helper's documented JSON Lines v1 interface with its in-process
`--fake` backend. It produced `ready`, `stateChanged` for `start`, a `status` response, and
`stopped` for `stop`; closing stdin then exercised the parent-EOF cleanup path. The container
exited `0`, wrote no stderr, and `--rm` left no matching container. No login, credentials,
tailnet connection, user state, or local target was used.

Both passes used `--pull=never`, `--network=none`, `--read-only`, `--cap-drop=ALL`,
`no-new-privileges`, 256 MiB memory, one CPU, a `/state` tmpfs, and a read-only helper bind
mount. They did not enter or change the existing unrelated container.

## Artifact checks

The source helper and the current 26.2 JAR entry have the same SHA-256:

`b207a597adc93f5fc77d4d66e2cf222751041a016656a856b632f823a41d8937`

Its manifest declares protocol v1, helper `0.1.0-p1`, Go `1.26.6`, Tailscale `v1.102.3`, and
`linux/amd64`.

## Boundary

This establishes only translated execution of the Linux amd64 helper on Docker Linux/aarch64
with a fake offline backend. It is not native x86 hardware evidence, tailnet interoperability,
real Tailscale backend behavior, or Windows support. The bounded command output is retained in
`outputs/roadmap-2026-09-19-version-soak/linux-helper-probe.txt`,
`linux-helper-container-version-result.txt`, and
`linux-helper-container-protocol-result.txt`.
