package engine

import (
	"bufio"
	"bytes"
	"encoding/json"
	"io"
	"net"
	"strings"
	"testing"
	"time"

	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/backend"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/protocol"
)

type harness struct {
	t    *testing.T
	inW  *io.PipeWriter
	errB *bytes.Buffer
	eng  *Engine
	fake *backend.Fake
	done chan struct{}
	evs  chan protocol.Message
}

func startHarness(t *testing.T) *harness {
	t.Helper()
	inR, inW := io.Pipe()
	outR, outW := io.Pipe()
	fake := backend.NewFake()
	errB := &bytes.Buffer{}
	eng := New(inR, outW, errB, func() backend.Backend { return fake })
	h := &harness{
		t:    t,
		inW:  inW,
		errB: errB,
		eng:  eng,
		fake: fake,
		done: make(chan struct{}),
		evs:  make(chan protocol.Message, 64),
	}
	go func() {
		eng.Run()
		_ = outW.Close()
		close(h.done)
	}()
	go func() {
		s := bufio.NewScanner(outR)
		for s.Scan() {
			msg, err := protocol.DecodeLine(s.Bytes())
			if err != nil {
				continue
			}
			h.evs <- *msg
		}
	}()
	t.Cleanup(func() {
		_ = inW.Close()
		select {
		case <-h.done:
		case <-time.After(4 * time.Second):
		}
	})
	return h
}

func (h *harness) send(obj map[string]any) {
	h.t.Helper()
	b, err := json.Marshal(obj)
	if err != nil {
		h.t.Fatal(err)
	}
	if _, err := h.inW.Write(append(b, '\n')); err != nil {
		h.t.Fatal(err)
	}
}

func (h *harness) waitEvent(name string) protocol.Message {
	h.t.Helper()
	deadline := time.After(3 * time.Second)
	for {
		select {
		case msg := <-h.evs:
			if msg.Event == name {
				return msg
			}
		case <-deadline:
			h.t.Fatalf("timeout waiting for %s stderr=%s", name, h.errB.String())
		}
	}
}

func TestHandshakeReadyAndStart(t *testing.T) {
	h := startHarness(t)
	dir := t.TempDir()
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "abc",
		"requestId":       "1",
		"command":         "start",
		"target":          "127.0.0.1:9600",
		"listenPort":      9600,
		"stateDir":        dir,
	})
	ready := h.waitEvent(protocol.EventReady)
	if ready.SessionNonce != "abc" || ready.ProtocolVersion != 1 || ready.HelperVersion == "" {
		t.Fatalf("ready %+v", ready)
	}
	_ = h.waitEvent(protocol.EventStateChanged)
	h.fake.Emit(backend.Event{
		State:   backend.StateNeedsLogin,
		AuthURL: "https://login.tailscale.com/a/not-logged",
	})
	auth := h.waitEvent(protocol.EventAuthRequired)
	if auth.AuthURL == "" {
		t.Fatal("missing authUrl from structured event")
	}
	h.fake.Emit(backend.Event{
		State: backend.StateRunning,
		Status: backend.Status{
			State:     backend.StateRunning,
			TailnetIP: "100.64.1.2",
			NodeID:    "n123",
		},
	})
	_ = h.waitEvent(protocol.EventListening)
}

func TestMalformedJSONAndNonceMismatch(t *testing.T) {
	h := startHarness(t)
	if _, err := h.inW.Write([]byte("not-json\n")); err != nil {
		t.Fatal(err)
	}
	errEvt := h.waitEvent(protocol.EventError)
	if errEvt.ErrorCode != protocol.ErrMalformedJSON {
		t.Fatalf("got %s", errEvt.ErrorCode)
	}
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "one",
		"requestId":       "1",
		"command":         "status",
	})
	_ = h.waitEvent(protocol.EventReady)
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "two",
		"requestId":       "2",
		"command":         "status",
	})
	mismatch := h.waitEvent(protocol.EventError)
	if mismatch.ErrorCode != protocol.ErrSessionNonceMismatch {
		t.Fatalf("got %s", mismatch.ErrorCode)
	}
}

func TestInvalidTargetRejected(t *testing.T) {
	h := startHarness(t)
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "n",
		"requestId":       "1",
		"command":         "start",
		"target":          "8.8.8.8:53",
		"listenPort":      9600,
		"stateDir":        t.TempDir(),
	})
	_ = h.waitEvent(protocol.EventReady)
	errEvt := h.waitEvent(protocol.EventError)
	if errEvt.ErrorCode != protocol.ErrInvalidTarget {
		t.Fatalf("got %s", errEvt.ErrorCode)
	}
}

func TestParentEOFCleansUp(t *testing.T) {
	h := startHarness(t)
	dir := t.TempDir()
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "n",
		"requestId":       "1",
		"command":         "start",
		"target":          "127.0.0.1:9600",
		"listenPort":      9600,
		"stateDir":        dir,
	})
	_ = h.waitEvent(protocol.EventReady)
	_ = h.inW.Close()
	select {
	case <-h.done:
	case <-time.After(4 * time.Second):
		t.Fatal("engine did not exit on parent EOF")
	}
}

func TestStateLock(t *testing.T) {
	dir := t.TempDir()
	h1 := startHarness(t)
	h1.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "a",
		"requestId":       "1",
		"command":         "start",
		"target":          "127.0.0.1:9600",
		"listenPort":      9600,
		"stateDir":        dir,
	})
	_ = h1.waitEvent(protocol.EventReady)
	time.Sleep(150 * time.Millisecond)
	h2 := startHarness(t)
	h2.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "b",
		"requestId":       "1",
		"command":         "start",
		"target":          "127.0.0.1:9600",
		"listenPort":      9600,
		"stateDir":        dir,
	})
	_ = h2.waitEvent(protocol.EventReady)
	errEvt := h2.waitEvent(protocol.EventError)
	if errEvt.ErrorCode != protocol.ErrStateLocked {
		t.Fatalf("got %s", errEvt.ErrorCode)
	}
}

func TestForwardThroughFakeListen(t *testing.T) {
	echoLn, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer echoLn.Close()
	go func() {
		c, err := echoLn.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		_, _ = io.Copy(c, c)
	}()
	h := startHarness(t)
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "n",
		"requestId":       "1",
		"command":         "start",
		"target":          echoLn.Addr().String(),
		"listenPort":      9600,
		"stateDir":        t.TempDir(),
	})
	_ = h.waitEvent(protocol.EventReady)
	_ = h.waitEvent(protocol.EventStateChanged)
	h.fake.Emit(backend.Event{
		State: backend.StateRunning,
		Status: backend.Status{
			State:     backend.StateRunning,
			TailnetIP: "100.64.0.1",
			NodeID:    "node",
		},
	})
	listen := h.waitEvent(protocol.EventListening)
	if !listen.Listening {
		t.Fatal("not listening")
	}
}

func TestEventIDsMonotonic(t *testing.T) {
	h := startHarness(t)
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "n",
		"requestId":       "1",
		"command":         "status",
	})
	a := h.waitEvent(protocol.EventReady)
	b := h.waitEvent(protocol.EventStateChanged)
	if b.EventID <= a.EventID {
		t.Fatalf("event ids %d %d", a.EventID, b.EventID)
	}
}

func TestStderrDoesNotContainAuthURL(t *testing.T) {
	h := startHarness(t)
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "n",
		"requestId":       "1",
		"command":         "start",
		"target":          "127.0.0.1:9600",
		"listenPort":      9600,
		"stateDir":        t.TempDir(),
	})
	_ = h.waitEvent(protocol.EventReady)
	_ = h.waitEvent(protocol.EventStateChanged)
	h.fake.Emit(backend.Event{
		State:   backend.StateNeedsLogin,
		AuthURL: "https://login.tailscale.com/a/super-secret-path",
	})
	_ = h.waitEvent(protocol.EventAuthRequired)
	if strings.Contains(h.errB.String(), "super-secret-path") {
		t.Fatalf("stderr leaked auth url: %s", h.errB.String())
	}
}

func TestShutdownStops(t *testing.T) {
	h := startHarness(t)
	h.send(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "n",
		"requestId":       "1",
		"command":         "shutdown",
	})
	_ = h.waitEvent(protocol.EventReady)
	_ = h.waitEvent(protocol.EventStopped)
	select {
	case <-h.done:
	case <-time.After(3 * time.Second):
		t.Fatal("did not exit")
	}
}
