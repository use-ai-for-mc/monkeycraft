#!/usr/bin/env python3
"""Apply the narrow MonkeyCraft TCP/NodeID patch to upstream wasm_js.go."""

from __future__ import annotations

import pathlib
import re
import sys

HEADER = """// MonkeyCraft patch applied by scripts/patch-wasm-js.py
// Upstream: tailscale.com v1.102.3 cmd/tsconnect/wasm/wasm_js.go
// Adds: StableID/NodeID on NetMap, dialTcp/connRead/connWrite/connClose,
// redacted notify logs, no logtail upload. Does not add SOCKS/UDP/Funnel.
"""

BRIDGE = r'''
func (i *jsIPN) nextConnID() string {
	i.mu.Lock()
	defer i.mu.Unlock()
	if i.conns == nil {
		i.conns = map[string]net.Conn{}
	}
	i.next++
	return fmt.Sprintf("c%d", i.next)
}

func (i *jsIPN) putConn(id string, c net.Conn) {
	i.mu.Lock()
	defer i.mu.Unlock()
	if i.conns == nil {
		i.conns = map[string]net.Conn{}
	}
	i.conns[id] = c
}

func (i *jsIPN) takeConn(id string) (net.Conn, bool) {
	i.mu.Lock()
	defer i.mu.Unlock()
	c, ok := i.conns[id]
	return c, ok
}

func (i *jsIPN) dropConn(id string) {
	i.mu.Lock()
	defer i.mu.Unlock()
	if c, ok := i.conns[id]; ok {
		_ = c.Close()
		delete(i.conns, id)
	}
}

func (i *jsIPN) closeAllConns() {
	i.mu.Lock()
	defer i.mu.Unlock()
	for id, c := range i.conns {
		_ = c.Close()
		delete(i.conns, id)
	}
}

func (i *jsIPN) dialTcp(host string, port int, timeoutMs int) js.Value {
	return makePromise(func() (any, error) {
		if host == "" || port < 1 || port > 65535 {
			return nil, fmt.Errorf("invalid dial target")
		}
		if timeoutMs <= 0 {
			timeoutMs = 15000
		}
		if timeoutMs > 60000 {
			timeoutMs = 60000
		}
		ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMs)*time.Millisecond)
		defer cancel()
		addr := net.JoinHostPort(host, strconv.Itoa(port))
		c, err := i.dialer.UserDial(ctx, "tcp", addr)
		if err != nil {
			return nil, err
		}
		id := i.nextConnID()
		i.putConn(id, c)
		return map[string]any{"connId": id}, nil
	})
}

func (i *jsIPN) connWrite(connID string, data []byte) js.Value {
	return makePromise(func() (any, error) {
		c, ok := i.takeConn(connID)
		if !ok {
			return nil, fmt.Errorf("unknown conn")
		}
		n, err := c.Write(data)
		if err != nil {
			return nil, err
		}
		return map[string]any{"n": n}, nil
	})
}

func (i *jsIPN) connRead(connID string, max int) js.Value {
	return makePromise(func() (any, error) {
		c, ok := i.takeConn(connID)
		if !ok {
			return nil, fmt.Errorf("unknown conn")
		}
		if max <= 0 || max > 65536 {
			max = 65536
		}
		buf := make([]byte, max)
		n, err := c.Read(buf)
		if n > 0 {
			out := js.Global().Get("Uint8Array").New(n)
			js.CopyBytesToJS(out, buf[:n])
			res := js.Global().Get("Object").New()
			res.Set("n", n)
			res.Set("eof", err == io.EOF)
			res.Set("data", out)
			if err != nil && err != io.EOF {
				return res, err
			}
			return res, nil
		}
		if err == io.EOF {
			return map[string]any{"n": 0, "eof": true}, nil
		}
		return nil, err
	})
}

func (i *jsIPN) connClose(connID string) js.Value {
	return makePromise(func() (any, error) {
		i.dropConn(connID)
		return map[string]any{"ok": true}, nil
	})
}

func jsBytes(v js.Value) []byte {
	if v.IsUndefined() || v.IsNull() {
		return nil
	}
	n := v.Get("byteLength").Int()
	buf := make([]byte, n)
	js.CopyBytesToGo(buf, v)
	return buf
}
'''


def patch(src: str) -> str:
    if "MonkeyCraft patch applied" in src:
        return src

    src = src.replace(
        '\t"strings"\n\t"syscall/js"\n\t"time"',
        '\t"io"\n\t"strconv"\n\t"strings"\n\t"sync"\n\t"syscall/js"\n\t"time"',
    )

    src = src.replace(
        """	lpc := getOrCreateLogPolicyConfig(store)
	c := logtail.Config{
		Collection: lpc.Collection,
		PrivateID:  lpc.PrivateID,

		// Compressed requests set HTTP headers that are not supported by the
		// no-cors fetching mode:
		CompressLogs: false,

		HTTPC: &http.Client{Transport: &noCORSTransport{http.DefaultTransport}},
	}
	logtail := logtail.NewLogger(c, log.Printf)
	logf := logtail.Logf
""",
        """	lpc := getOrCreateLogPolicyConfig(store)
	logf := log.Printf
""",
    )

    src = src.replace(
        """		"fetch": js.FuncOf(func(this js.Value, args []js.Value) any {
			if len(args) != 1 {
				log.Printf("Usage: fetch(url)")
				return nil
			}

			url := args[0].String()
			return jsIPN.fetch(url)
		}),
	}
""",
        """		"fetch": js.FuncOf(func(this js.Value, args []js.Value) any {
			if len(args) != 1 {
				log.Printf("Usage: fetch(url)")
				return nil
			}

			url := args[0].String()
			return jsIPN.fetch(url)
		}),
		"dialTcp": js.FuncOf(func(this js.Value, args []js.Value) any {
			if len(args) < 2 {
				log.Printf("Usage: dialTcp(host, port, timeoutMs?)")
				return nil
			}
			timeoutMs := 15000
			if len(args) >= 3 && args[2].Type() == js.TypeNumber {
				timeoutMs = args[2].Int()
			}
			return jsIPN.dialTcp(args[0].String(), args[1].Int(), timeoutMs)
		}),
		"connWrite": js.FuncOf(func(this js.Value, args []js.Value) any {
			if len(args) != 2 {
				log.Printf("Usage: connWrite(connId, bytes)")
				return nil
			}
			return jsIPN.connWrite(args[0].String(), jsBytes(args[1]))
		}),
		"connRead": js.FuncOf(func(this js.Value, args []js.Value) any {
			if len(args) < 1 {
				log.Printf("Usage: connRead(connId, max?)")
				return nil
			}
			max := 65536
			if len(args) >= 2 && args[1].Type() == js.TypeNumber {
				max = args[1].Int()
			}
			return jsIPN.connRead(args[0].String(), max)
		}),
		"connClose": js.FuncOf(func(this js.Value, args []js.Value) any {
			if len(args) != 1 {
				log.Printf("Usage: connClose(connId)")
				return nil
			}
			return jsIPN.connClose(args[0].String())
		}),
	}
""",
    )

    src = src.replace(
        """type jsIPN struct {
	dialer     *tsdial.Dialer
	srv        *ipnserver.Server
	lb         *ipnlocal.LocalBackend
	controlURL string
	authKey    string
	hostname   string
}
""",
        """type jsIPN struct {
	dialer     *tsdial.Dialer
	srv        *ipnserver.Server
	lb         *ipnlocal.LocalBackend
	controlURL string
	authKey    string
	hostname   string
	mu         sync.Mutex
	conns      map[string]net.Conn
	next       int
}
""",
    )

    src = src.replace(
        '\t\tlog.Printf("NOTIFY: %+v", n)\n',
        '\t\tlog.Printf("NOTIFY: state=%v selfChange=%v browseURL=%v")\n',
    )
    # The above replacement is wrong because I dropped the format args.
    src = src.replace(
        '\t\tlog.Printf("NOTIFY: state=%v selfChange=%v browseURL=%v")\n',
        '\t\tlog.Printf("NOTIFY: state-set=%v selfChange=%v browseURL=%v", n.State != nil, n.SelfChange != nil, n.BrowseToURL != nil)\n',
    )

    src = src.replace(
        """						jsNetMapNode: jsNetMapNode{
							Name:       nm.SelfName(),
							Addresses:  mapSliceView(nm.GetAddresses(), func(a netip.Prefix) string { return a.Addr().String() }),
							NodeKey:    nm.NodeKey.String(),
							MachineKey: nm.MachineKey.String(),
						},
""",
        """						jsNetMapNode: jsNetMapNode{
							Name:       nm.SelfName(),
							Addresses:  mapSliceView(nm.GetAddresses(), func(a netip.Prefix) string { return a.Addr().String() }),
							NodeKey:    nm.NodeKey.String(),
							MachineKey: nm.MachineKey.String(),
							NodeID:     fmt.Sprintf("%d", int64(nm.SelfNode.ID())),
							StableID:   string(nm.SelfNode.StableID()),
						},
""",
    )

    src = src.replace(
        """							jsNetMapNode: jsNetMapNode{
								Name:       name,
								Addresses:  addrs,
								MachineKey: p.Machine().String(),
								NodeKey:    p.Key().String(),
							},
""",
        """							jsNetMapNode: jsNetMapNode{
								Name:       name,
								Addresses:  addrs,
								MachineKey: p.Machine().String(),
								NodeKey:    p.Key().String(),
								NodeID:     fmt.Sprintf("%d", int64(p.ID())),
								StableID:   string(p.StableID()),
							},
""",
    )

    src = src.replace(
        """type jsNetMapNode struct {
	Name       string   `json:"name"`
	Addresses  []string `json:"addresses"`
	MachineKey string   `json:"machineKey"`
	NodeKey    string   `json:"nodeKey"`
}
""",
        """type jsNetMapNode struct {
	Name       string   `json:"name"`
	Addresses  []string `json:"addresses"`
	MachineKey string   `json:"machineKey"`
	NodeKey    string   `json:"nodeKey"`
	NodeID     string   `json:"nodeId,omitempty"`
	StableID   string   `json:"stableId,omitempty"`
}
""",
    )

    src = src.replace(
        """func (i *jsIPN) logout() {
	if i.lb.State() == ipn.NoState {
		log.Printf("Backend not running")
	}
	go func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		i.lb.Logout(ctx, ipnauth.Self)
	}()
}
""",
        """func (i *jsIPN) logout() {
	if i.lb.State() == ipn.NoState {
		log.Printf("Backend not running")
	}
	go func() {
		i.closeAllConns()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		i.lb.Logout(ctx, ipnauth.Self)
	}()
}
""",
    )

    src = src.replace(
        'lb, err := ipnlocal.NewLocalBackend(logf, logid, sys, controlclient.LoginEphemeral)',
        '''loginFlags := controlclient.LoginEphemeral
	if ephemeral := jsConfig.Get("ephemeral"); ephemeral.Type() == js.TypeBoolean && !ephemeral.Bool() {
		loginFlags = 0
	}
	lb, err := ipnlocal.NewLocalBackend(logf, logid, sys, loginFlags)''',
    )
    src = src.replace('jsIPN.logout()\n\t\t\treturn nil', 'return jsIPN.logout()')
    src = re.sub(
        r'func \(i \*jsIPN\) logout\(\) \{.*?\n\}',
        '''func (i *jsIPN) logout() js.Value {
	return makePromise(func() (any, error) {
		i.closeAllConns()
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		return nil, i.lb.Logout(ctx, ipnauth.Self)
	})
}''', src, flags=re.S,
    )

    if "func (i *jsIPN) dialTcp" not in src:
        src = src.rstrip() + "\n" + BRIDGE + "\n"

    unused = []
    if "logtail." not in src and '"tailscale.com/logtail"' in src:
        unused.append("logtail")
    # Keep logtail import if logpolicy still needs CollectionNode from logtail
    if "logtail.CollectionNode" in src:
        pass
    elif '"tailscale.com/logtail"' in src:
        src = src.replace('\t"tailscale.com/logtail"\n', "")

    return HEADER + src


def main() -> int:
    if len(sys.argv) != 3:
        print("usage: patch-wasm-js.py IN.go OUT.go", file=sys.stderr)
        return 2
    inp = pathlib.Path(sys.argv[1])
    out = pathlib.Path(sys.argv[2])
    src = inp.read_text()
    patched = patch(src)
    if "dialTcp" not in patched or "StableID" not in patched:
        print("patch failed: missing dialTcp or StableID", file=sys.stderr)
        return 1
    out.write_text(patched)
    print(f"patched {inp} -> {out} ({len(patched)} bytes)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
