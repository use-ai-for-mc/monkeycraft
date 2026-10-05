//go:build integration

package javatest

import (
	"bytes"
	"context"
	"golang.org/x/net/proxy"
	"io"
	"net"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"sync"
	"tailscale.com/client/local"
	"tailscale.com/ipn"
	"testing"
	"time"
)

// Runs a separate upstream daemon with a private socket, private state and no TUN.
func verifyOfficialDaemon(t *testing.T, ctx context.Context, controlURL, ip string, port uint16) {
	t.Helper()
	binary := os.Getenv("RESEARCH_OFFICIAL")
	if binary == "" {
		return
	}
	dir, e := os.MkdirTemp(os.Getenv("TMPDIR"), "td-")
	if e != nil {
		t.Fatal(e)
	}
	t.Cleanup(func() { os.RemoveAll(dir) })
	socket := filepath.Join(dir, "s")
	socks := net.JoinHostPort("127.0.0.1", strconv.Itoa(int(unusedHermeticPort(t))))
	cmd := exec.CommandContext(ctx, binary, "--tun=userspace-networking", "--socket="+socket, "--statedir="+dir, "--state="+filepath.Join(dir, "state"), "--socks5-server="+socks, "--port=0", "--no-logs-no-support")
	var diag hermeticLogBuffer
	cmd.Stdout = &diag
	cmd.Stderr = &diag
	if e = cmd.Start(); e != nil {
		t.Fatal(e)
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	t.Cleanup(func() {
		cmd.Process.Signal(os.Interrupt)
		select {
		case <-done:
		case <-time.After(3 * time.Second):
			cmd.Process.Kill()
			<-done
		}
	})
	lc := &local.Client{Socket: socket, UseSocketOnly: true, OmitAuth: true, Dial: func(ctx context.Context, _, _ string) (net.Conn, error) {
		return (&net.Dialer{}).DialContext(ctx, "unix", socket)
	}}
	ready := false
	for i := 0; i < 100; i++ {
		if _, e = lc.Status(ctx); e == nil {
			ready = true
			break
		}
		time.Sleep(50 * time.Millisecond)
	}
	if !ready {
		t.Fatalf("isolated official daemon startup: %v %s", e, diag.String())
	}
	prefs := ipn.NewPrefs()
	prefs.ControlURL = controlURL
	prefs.WantRunning = true
	prefs.Hostname = "research-official"
	if e = lc.Start(ctx, ipn.Options{UpdatePrefs: prefs}); e != nil {
		t.Fatal(e)
	}
	login := false
	ready = false
	for i := 0; i < 200; i++ {
		st, e := lc.Status(ctx)
		if e == nil {
			if st.BackendState == "Running" {
				ready = true
				break
			}
			if st.BackendState == "NeedsLogin" && !login {
				if e = lc.StartLoginInteractive(ctx); e != nil {
					t.Fatal(e)
				}
				login = true
			}
		}
		time.Sleep(50 * time.Millisecond)
	}
	if !ready {
		t.Fatalf("isolated official daemon never running: %s", diag.String())
	}
	dial, e := proxy.SOCKS5("tcp", socks, nil, &net.Dialer{Timeout: 5 * time.Second})
	if e != nil {
		t.Fatal(e)
	}
	c, e := dial.(proxy.ContextDialer).DialContext(ctx, "tcp", net.JoinHostPort(ip, strconv.Itoa(int(port))))
	if e != nil {
		t.Fatalf("official daemon dial: %v %s", e, diag.String())
	}
	defer c.Close()
	c.SetDeadline(time.Now().Add(5 * time.Second))
	data := bytes.Repeat([]byte("official-daemon"), 4096)
	go c.Write(data)
	got := make([]byte, len(data))
	if _, e = io.ReadFull(c, got); e != nil {
		t.Fatal(e)
	}
	if !bytes.Equal(got, data) {
		t.Fatal("official stream mismatch")
	}
	t.Logf("upstream tailscaled userspace SOCKS peer -> Java -> loopback passed: %d bytes", len(data))
}

type hermeticLogBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (b *hermeticLogBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.Write(p)
}
func (b *hermeticLogBuffer) String() string { b.mu.Lock(); defer b.mu.Unlock(); return b.b.String() }
func unusedHermeticPort(t *testing.T) uint16 {
	t.Helper()
	l, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	defer l.Close()
	return uint16(l.Addr().(*net.TCPAddr).Port)
}
