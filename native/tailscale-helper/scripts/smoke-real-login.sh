#!/usr/bin/env bash
# Interactive-capable smoke: start real tsnet helper, wait for structured authRequired.
# Prints auth URL to the TTY only; does not write it to files.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$ROOT/dist/darwin-arm64/monkeycraft-tailscale-helper}"
STATE="${2:-$(mktemp -d /tmp/mc-ts-smoke-XXXX)}"
PORT="${3:-19600}"
echo "using stateDir=$STATE listenPort=$PORT (auth URL will not be written to files)" >&2
python3 - "$BIN" "$STATE" "$PORT" <<'PY'
import json, os, subprocess, sys, time, threading, queue
bin, state, port = sys.argv[1], sys.argv[2], int(sys.argv[3])
proc = subprocess.Popen(
    [bin],
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    bufsize=1,
)
q = queue.Queue()
def drain(stream, kind):
    for line in stream:
        q.put((kind, line.rstrip("\n")))
threading.Thread(target=drain, args=(proc.stdout, "out"), daemon=True).start()
threading.Thread(target=drain, args=(proc.stderr, "err"), daemon=True).start()
cmd = {
    "protocolVersion": 1,
    "sessionNonce": "smoke",
    "requestId": "1",
    "command": "start",
    "target": "127.0.0.1:9600",
    "listenPort": port,
    "stateDir": state,
}
proc.stdin.write(json.dumps(cmd) + "\n")
proc.stdin.flush()
got_auth = False
deadline = time.time() + 45
while time.time() < deadline:
    try:
        kind, line = q.get(timeout=1)
    except queue.Empty:
        if proc.poll() is not None:
            print("helper exited", proc.returncode, file=sys.stderr)
            break
        continue
    if kind == "err":
        low = line.lower()
        if "tskey-" in low and "tskey-[redacted]" not in low:
            print("stderr leaked auth key", file=sys.stderr)
            proc.kill()
            sys.exit(2)
        if "login.tailscale.com/a/" in low:
            after = low.split("login.tailscale.com/a/", 1)[1]
            if after and not after.startswith("["):
                print("stderr leaked auth url path", file=sys.stderr)
                proc.kill()
                sys.exit(2)
        continue
    try:
        msg = json.loads(line)
    except json.JSONDecodeError:
        print("stdout pollution (non-json)", file=sys.stderr)
        proc.kill()
        sys.exit(3)
    ev = msg.get("event")
    print(f"event={ev} state={msg.get('state')} errorCode={msg.get('errorCode')}", file=sys.stderr)
    if ev == "authRequired":
        url = msg.get("authUrl") or ""
        if not url.startswith("https://"):
            print("authRequired without https URL", file=sys.stderr)
            proc.kill()
            sys.exit(4)
        print("AUTH_URL_RECEIVED host=" + url.split("/")[2], file=sys.stderr)
        print(url)
        got_auth = True
        break
    if ev == "listening":
        print("already logged in; listening", file=sys.stderr)
        got_auth = True
        break
    if ev == "error" and msg.get("errorCode") not in (None, ""):
        print("error", msg.get("errorCode"), file=sys.stderr)
        break
proc.stdin.write(json.dumps({
    "protocolVersion": 1, "sessionNonce": "smoke", "requestId": "9", "command": "shutdown"
}) + "\n")
proc.stdin.close()
try:
    proc.wait(timeout=5)
except subprocess.TimeoutExpired:
    proc.kill()
sys.exit(0 if got_auth else 1)
PY
