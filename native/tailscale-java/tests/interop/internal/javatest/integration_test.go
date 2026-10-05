//go:build integration

package javatest

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http/httptest"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"tailscale-java-lab/internal/labnet"
	"tailscale.com/net/netns"
	"tailscale.com/tailcfg"
	"tailscale.com/tsnet"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/key"
	"tailscale.com/types/logger"
	"testing"
	"time"
)

type status struct {
	State, AuthURL, NodeKey, Error string
	Addresses                      []string
	Traffic                        map[string]int64
}

func TestJavaClient(t *testing.T) {
	java, cp := os.Getenv("RESEARCH_JAVA"), os.Getenv("RESEARCH_JAVA_CP")
	if java == "" || cp == "" {
		t.Skip("Java lab paths not configured")
	}
	for _, k := range []string{"TS_AUTHKEY", "TS_AUTH_KEY", "TS_CLIENT_SECRET", "TS_CLIENT_ID", "TS_ID_TOKEN", "TS_AUDIENCE", "TS_CONTROL_URL"} {
		t.Setenv(k, "")
	}
	t.Setenv("TS_NO_LOGS_NO_SUPPORT", "true")
	netns.SetEnabled(false)
	defer netns.SetEnabled(true)
	dm, cert := labnet.RunDERPAndSTUNWithCertificate(t, logger.Discard, "127.0.0.1")
	ctl := &testcontrol.Server{DERPMap: dm, RequireAuth: true, RequireMachineAuth: true, Logf: logger.Discard}
	ctl.HTTPTestServer = httptest.NewServer(ctl)
	defer ctl.HTTPTestServer.Close()
	dir := t.TempDir()
	certPath := filepath.Join(dir, "derp.cer")
	if e := os.WriteFile(certPath, cert, 0600); e != nil {
		t.Fatal(e)
	}
	echo, e := net.Listen("tcp", "127.0.0.1:0")
	if e != nil {
		t.Fatal(e)
	}
	defer echo.Close()
	go func() {
		for {
			c, e := echo.Accept()
			if e != nil {
				return
			}
			go func() { defer c.Close(); io.Copy(c, c) }()
		}
	}()
	timeout := 100 * time.Second
	if os.Getenv("RESEARCH_STRESS") == "1" {
		timeout = 180 * time.Second
	}
	ctx, cancel := context.WithTimeout(context.Background(), timeout)
	defer cancel()
	mode := os.Getenv("RESEARCH_PATH")
	if mode == "" {
		mode = "direct"
	}
	var cmd *exec.Cmd
	var input io.WriteCloser
	var done chan error
	var events chan status
	spawn := func() {
		cmd = exec.CommandContext(ctx, java, "-cp", cp, "com.monkeycraft.tailscale.ClientLabMain", ctl.HTTPTestServer.URL, filepath.Join(dir, "identity"), strconv.Itoa(echo.Addr().(*net.TCPAddr).Port), certPath, mode)
		var err error
		input, err = cmd.StdinPipe()
		if err != nil {
			t.Fatal(err)
		}
		out, err := cmd.StdoutPipe()
		if err != nil {
			t.Fatal(err)
		}
		cmd.Stderr = os.Stderr
		if err = cmd.Start(); err != nil {
			t.Fatal(err)
		}
		child, completion := cmd, make(chan error, 1)
		done = completion
		go func() { completion <- child.Wait() }()
		stream := make(chan status, 128)
		events = stream
		go func() {
			defer close(stream)
			scan := bufio.NewScanner(out)
			for scan.Scan() {
				var s status
				if err := json.Unmarshal(scan.Bytes(), &s); err == nil {
					stream <- s
				} else {
					fmt.Fprintln(os.Stderr, scan.Text())
				}
			}
		}()
	}
	spawn()
	defer func() {
		input.Close()
		select {
		case <-done:
		case <-time.After(3 * time.Second):
			cmd.Process.Kill()
			<-done
		}
	}()
	sawURL, sawApproval := false, false
	wait := func(want string) status {
		t.Helper()
		for {
			select {
			case s, ok := <-events:
				if !ok {
					t.Fatal("Java client exited")
				}
				t.Logf("java state=%s url=%v error=%s", s.State, s.AuthURL != "", s.Error)
				if s.AuthURL != "" {
					sawURL = true
					// testcontrol clones KeyExpiry on rotation but does not reset it on auth completion.
					// Model the control plane's new expiry after the user authenticates the replacement key.
					var authed key.NodePublic
					if e := authed.UnmarshalText([]byte(s.NodeKey)); e != nil {
						t.Fatal(e)
					}
					if n := ctl.Node(authed); n != nil && !n.KeyExpiry.IsZero() {
						n.KeyExpiry = time.Now().Add(24 * time.Hour)
						ctl.UpdateNode(n)
					}
					if !ctl.CompleteAuth(s.AuthURL) {
						t.Fatal("auth URL rejected")
					}
				}
				if s.State == "needsApproval" {
					sawApproval = true
					var k key.NodePublic
					if e := k.UnmarshalText([]byte(s.NodeKey)); e != nil {
						t.Fatal(e)
					}
					if !ctl.CompleteDeviceApproval(ctl.HTTPTestServer.URL, ctl.HTTPTestServer.URL+"/admin", &k) {
						t.Fatal("approval failed")
					}
				}
				if s.State == want {
					return s
				}
			case <-ctx.Done():
				t.Fatal("timed out waiting for " + want)
			}
		}
	}
	first := wait("running")
	if !sawURL || !sawApproval {
		t.Fatal("missing interactive lifecycle")
	}
	if len(first.Addresses) == 0 {
		t.Fatal("no address")
	}
	ctl.RequireAuth = false
	ctl.RequireMachineAuth = false
	peer := &tsnet.Server{Dir: filepath.Join(dir, "peer"), Hostname: "go-java-peer", ControlURL: ctl.HTTPTestServer.URL, Logf: logger.Discard, UserLogf: logger.Discard}
	defer peer.Close()
	if _, e := peer.Up(ctx); e != nil {
		t.Fatal(e)
	}
	exchange := func(timeout time.Duration) error {
		dial, cancel := context.WithTimeout(ctx, timeout)
		defer cancel()
		c, e := peer.Dial(dial, "tcp", net.JoinHostPort(first.Addresses[0], "9600"))
		if e != nil {
			return e
		}
		defer c.Close()
		c.SetDeadline(time.Now().Add(timeout))
		want := bytes.Repeat([]byte("pure-java-tailnet-loopback-"), 6000)
		errc := make(chan error, 1)
		go func() { _, e := c.Write(want); errc <- e }()
		got := make([]byte, len(want))
		_, e = io.ReadFull(c, got)
		if e != nil {
			return e
		}
		if e = <-errc; e != nil {
			return e
		}
		if !bytes.Equal(want, got) {
			return fmt.Errorf("stream differs")
		}
		return nil
	}
	connected := false
	for i := 0; i < 6; i++ {
		if e = exchange(5 * time.Second); e == nil {
			connected = true
			break
		}
		t.Logf("connection attempt %d: %v", i, e)
	}
	if !connected {
		t.Fatal(e)
	}
	fmt.Fprintln(input, "status")
	traffic := wait("running").Traffic
	if mode == "direct" && traffic["directReceived"] == 0 {
		time.Sleep(time.Second)
		if e = exchange(5 * time.Second); e != nil {
			t.Fatal(e)
		}
		fmt.Fprintln(input, "status")
		traffic = wait("running").Traffic
	}
	if mode == "direct" && traffic["directReceived"] == 0 {
		t.Fatalf("no direct traffic: %v", traffic)
	}
	if mode == "derp" && (traffic["derpReceived"] == 0 || traffic["directReceived"] != 0) {
		t.Fatalf("invalid forced DERP traffic: %v", traffic)
	}
	t.Logf("verified Java path=%s traffic=%v", mode, traffic)
	verifyOfficialDaemon(t, ctx, ctl.HTTPTestServer.URL, first.Addresses[0], 9600)
	if os.Getenv("RESEARCH_STRESS") == "1" {
		verifyStreams(t, ctx, peer, first.Addresses[0])
	}
	if len(first.Addresses) > 1 {
		v4 := first.Addresses[0]
		first.Addresses[0] = first.Addresses[1]
		if e = exchange(8 * time.Second); e != nil {
			t.Fatalf("IPv6 TCP: %v", e)
		}
		first.Addresses[0] = v4
		t.Log("IPv6 TCP through Java userspace stack passed")
	}
	if os.Getenv("RESEARCH_RECOVERY") == "1" && mode == "direct" {
		fmt.Fprintln(input, "udp-down")
		if e = exchange(40 * time.Second); e != nil {
			t.Fatalf("UDP loss did not recover over DERP: %v", e)
		}
		fmt.Fprintln(input, "status")
		lost := wait("running")
		if lost.Traffic["derpReceived"] <= traffic["derpReceived"] {
			t.Fatal("UDP loss did not use DERP")
		}
		fmt.Fprintln(input, "udp-up")
		time.Sleep(6 * time.Second)
		if e = exchange(8 * time.Second); e != nil {
			t.Fatal(e)
		}
		fmt.Fprintln(input, "status")
		restored := wait("running")
		if restored.Traffic["directReceived"] <= lost.Traffic["directReceived"] {
			t.Fatal("UDP restoration did not return to direct")
		}
		t.Log("network change: direct -> UDP loss -> DERP -> UDP restored -> direct passed")
	}
	var nk key.NodePublic
	if e = nk.UnmarshalText([]byte(first.NodeKey)); e != nil {
		t.Fatal(e)
	}
	if e = ctl.AwaitNodeInMapRequest(ctx, nk); e != nil {
		t.Fatal(e)
	}
	fmt.Fprintln(input, "stop")
	wait("stopped")
	fmt.Fprintln(input, "start")
	second := wait("running")
	if second.NodeKey != first.NodeKey || second.Addresses[0] != first.Addresses[0] {
		t.Fatal("identity changed")
	}
	connected = false
	for i := 0; i < 5; i++ {
		if e = exchange(5 * time.Second); e == nil {
			connected = true
			break
		}
	}
	if !connected {
		t.Fatal(e)
	}
	t.Log("stop/restart identity and connection restore passed")
	fmt.Fprintln(input, "close")
	select {
	case e = <-done:
		if e != nil {
			t.Fatal(e)
		}
	case <-time.After(5 * time.Second):
		t.Fatal("cold restart: old Java process still running")
	}
	input.Close()
	spawn()
	cold := wait("running")
	if cold.NodeKey != first.NodeKey || cold.Addresses[0] != first.Addresses[0] {
		t.Fatal("cold restart did not restore persisted identity")
	}
	connected = false
	for i := 0; i < 5; i++ {
		if e = exchange(5 * time.Second); e == nil {
			connected = true
			break
		}
	}
	if !connected {
		t.Fatal(e)
	}
	t.Log("new JVM restored identity from disk and TCP forwarding")
	ctl.RequireAuth = true
	node := ctl.Node(nk)
	node.KeyExpiry = time.Now().Add(-time.Minute)
	ctl.UpdateNode(node)
	oldURL := sawURL
	sawURL = false
	refreshed := wait("running")
	first.Addresses = refreshed.Addresses
	if !sawURL || refreshed.NodeKey == first.NodeKey {
		t.Fatalf("expiry failed fresh auth=%v initial=%v", sawURL, oldURL)
	}
	t.Log("expired key rotated and interactive reauthentication passed")
	if e = nk.UnmarshalText([]byte(refreshed.NodeKey)); e != nil {
		t.Fatal(e)
	}
	if !ctl.AddRawMapResponse(nk, &tailcfg.MapResponse{PacketFilters: map[string][]tailcfg.FilterRule{"*": nil}}) {
		t.Fatal("deny update failed")
	}
	time.Sleep(300 * time.Millisecond)
	if e = exchange(time.Second); e == nil {
		t.Fatal("denied TCP accepted")
	}
	if !ctl.AddRawMapResponse(nk, &tailcfg.MapResponse{PacketFilter: tailcfg.FilterAllowAll}) {
		t.Fatal("allow update failed")
	}
	if e = exchange(5 * time.Second); e != nil {
		t.Fatal(e)
	}
	t.Log("policy deny and restore passed")
	fmt.Fprintln(input, "logout")
	last := wait("needsLogin")
	if last.AuthURL != "" {
		t.Fatal("logout automatically started login")
	}
	fmt.Fprintln(input, "close")
	select {
	case e = <-done:
		if e != nil {
			t.Fatal(e)
		}
		done <- nil
	case <-time.After(5 * time.Second):
		t.Fatal("Java process did not close")
	}
	t.Log("JAVA_CLIENT_E2E_OK interactive approval TCP loopback policy restart expiry logout close")
}
