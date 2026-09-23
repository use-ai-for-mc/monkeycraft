//go:build integration

package engine

import (
	"bufio"
	"bytes"
	"context"
	"encoding/json"
	"io"
	"net"
	"net/http/httptest"
	"path/filepath"
	"strconv"
	"sync"
	"testing"
	"time"

	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/backend"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/protocol"
	"tailscale.com/net/netns"
	"tailscale.com/tailcfg"
	"tailscale.com/tsnet"
	"tailscale.com/tstest/integration"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/logger"
)

type hermeticLogBuffer struct {
	mu sync.Mutex
	b  bytes.Buffer
}

func (b *hermeticLogBuffer) Write(p []byte) (int, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.Write(p)
}

func (b *hermeticLogBuffer) String() string {
	b.mu.Lock()
	defer b.mu.Unlock()
	return b.b.String()
}

type hermeticEngineHarness struct {
	t    *testing.T
	inW  *io.PipeWriter
	errB *hermeticLogBuffer
	done chan struct{}
	evs  chan protocol.Message
}

func newHermeticEngineHarness(t *testing.T, factory backend.Factory) *hermeticEngineHarness {
	t.Helper()
	inR, inW := io.Pipe()
	outR, outW := io.Pipe()
	errB := &hermeticLogBuffer{}
	h := &hermeticEngineHarness{
		t:    t,
		inW:  inW,
		errB: errB,
		done: make(chan struct{}),
		evs:  make(chan protocol.Message, 32),
	}
	eng := New(inR, outW, errB, factory)
	go func() {
		eng.Run()
		_ = outW.Close()
		close(h.done)
	}()
	go func() {
		s := bufio.NewScanner(outR)
		for s.Scan() {
			msg, err := protocol.DecodeLine(s.Bytes())
			if err == nil {
				h.evs <- *msg
			}
		}
	}()
	t.Cleanup(func() {
		_ = inW.Close()
		select {
		case <-h.done:
		case <-time.After(4 * time.Second):
			t.Error("helper did not exit")
		}
	})
	return h
}

func (h *hermeticEngineHarness) send(m protocol.Message) {
	h.t.Helper()
	b, err := json.Marshal(m)
	if err != nil {
		h.t.Fatal(err)
	}
	if _, err := h.inW.Write(append(b, '\n')); err != nil {
		h.t.Fatal(err)
	}
}

func (h *hermeticEngineHarness) waitFor(match func(protocol.Message) bool) protocol.Message {
	h.t.Helper()
	deadline := time.After(25 * time.Second)
	for {
		select {
		case msg := <-h.evs:
			if match(msg) {
				return msg
			}
		case <-deadline:
			h.t.Fatalf("timeout waiting for helper event: %s", h.errB.String())
		}
	}
}

func startHermeticControl(t *testing.T) string {
	t.Helper()
	netns.SetEnabled(false)
	t.Cleanup(func() { netns.SetEnabled(true) })
	derpMap := integration.RunDERPAndSTUN(t, logger.Discard, "127.0.0.1")
	control := &testcontrol.Server{
		DERPMap: derpMap,
		DNSConfig: &tailcfg.DNSConfig{
			Proxied: true,
		},
		MagicDNSDomain: "tail-scale.ts.net",
		Logf:           logger.Discard,
	}
	control.HTTPTestServer = httptest.NewUnstartedServer(control)
	control.HTTPTestServer.Start()
	t.Cleanup(control.HTTPTestServer.Close)
	return control.HTTPTestServer.URL
}

func startHermeticEcho(t *testing.T) string {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			conn, err := ln.Accept()
			if err != nil {
				return
			}
			go func() {
				defer conn.Close()
				_, _ = io.Copy(conn, conn)
			}()
		}
	}()
	t.Cleanup(func() {
		_ = ln.Close()
		wg.Wait()
	})
	return ln.Addr().String()
}

func unusedHermeticPort(t *testing.T) uint16 {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	return uint16(ln.Addr().(*net.TCPAddr).Port)
}

func hermeticClient(t *testing.T, controlURL string) *tsnet.Server {
	t.Helper()
	client := &tsnet.Server{
		Dir:        filepath.Join(t.TempDir(), "client"),
		Hostname:   "helper-hermetic-client",
		ControlURL: controlURL,
		Logf:       logger.Discard,
		UserLogf:   logger.Discard,
	}
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Second)
	defer cancel()
	if _, err := client.Up(ctx); err != nil {
		_ = client.Close()
		t.Fatal(err)
	}
	t.Cleanup(func() { _ = client.Close() })
	return client
}

func exchangeHermeticBytes(t *testing.T, client *tsnet.Server, ip string, port uint16, want []byte) {
	t.Helper()
	ctx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
	defer cancel()
	conn, err := client.Dial(ctx, "tcp", net.JoinHostPort(ip, strconv.Itoa(int(port))))
	if err != nil {
		t.Fatal(err)
	}
	defer conn.Close()
	if _, err := conn.Write(want); err != nil {
		t.Fatal(err)
	}
	got := make([]byte, len(want))
	if _, err := io.ReadFull(conn, got); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(got, want) {
		t.Fatalf("got %q want %q", got, want)
	}
}

func clearHermeticTsnetEnv(t *testing.T) {
	t.Helper()
	for _, name := range []string{"TS_AUTHKEY", "TS_AUTH_KEY", "TS_CONTROL_URL", "TS_CLIENT_SECRET", "TS_CLIENT_ID", "TS_ID_TOKEN", "TS_AUDIENCE"} {
		t.Setenv(name, "")
	}
}

func runHermeticTailnetHelperForwardRestart(t *testing.T, controlURL string, factory backend.Factory) {
	t.Helper()
	target := startHermeticEcho(t)
	port := unusedHermeticPort(t)
	stateDir := filepath.Join(t.TempDir(), "helper-state")
	h := newHermeticEngineHarness(t, factory)
	client := hermeticClient(t, controlURL)

	start := func(requestID string) protocol.Message {
		h.send(protocol.Message{
			ProtocolVersion: 1,
			SessionNonce:    "hermetic-session",
			RequestID:       requestID,
			Command:         protocol.CmdStart,
			Target:          target,
			ListenPort:      port,
			StateDir:        stateDir,
			Hostname:        "helper-hermetic-node",
		})
		return h.waitFor(func(msg protocol.Message) bool {
			return msg.Event == protocol.EventListening && msg.State == protocol.StateRunning
		})
	}

	first := start("start-1")
	if first.TailnetIP == "" || first.NodeID == "" || !first.Listening {
		t.Fatalf("first listening event incomplete: %+v", first)
	}
	exchangeHermeticBytes(t, client, first.TailnetIP, port, []byte("first-roundtrip"))

	h.send(protocol.Message{ProtocolVersion: 1, SessionNonce: "hermetic-session", RequestID: "stop-1", Command: protocol.CmdStop})
	h.waitFor(func(msg protocol.Message) bool {
		return msg.Event == protocol.EventStopped && msg.RequestID == "stop-1" && msg.State == protocol.StateStopped
	})

	second := start("start-2")
	if second.NodeID != first.NodeID || second.TailnetIP != first.TailnetIP {
		t.Fatalf("identity changed after restart: first=%+v second=%+v", first, second)
	}
	exchangeHermeticBytes(t, client, second.TailnetIP, port, []byte("second-roundtrip"))

	h.send(protocol.Message{ProtocolVersion: 1, SessionNonce: "hermetic-session", RequestID: "shutdown-1", Command: protocol.CmdShutdown})
	h.waitFor(func(msg protocol.Message) bool {
		return msg.Event == protocol.EventStopped && msg.RequestID == "shutdown-1" && msg.State == protocol.StateStopped
	})
	select {
	case <-h.done:
	case <-time.After(5 * time.Second):
		t.Fatal("helper did not finish after shutdown")
	}
}

func TestHermeticTailnetHelperForwardRestart(t *testing.T) {
	clearHermeticTsnetEnv(t)
	controlURL := startHermeticControl(t)
	t.Setenv("TS_CONTROL_URL", controlURL)
	runHermeticTailnetHelperForwardRestart(t, controlURL, func() backend.Backend {
		return backend.NewTsnet()
	})
}
