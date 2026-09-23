package engine

import (
	"bufio"
	"context"
	"errors"
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/backend"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/forward"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/lockfile"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/protocol"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/redact"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/version"
)

const (
	shutdownWait = 3 * time.Second
	maxConns     = 8
)

type Engine struct {
	in      io.Reader
	out     io.Writer
	err     io.Writer
	newBack backend.Factory

	mu           sync.Mutex
	nonce        string
	eventID      uint64
	state        string
	started      bool
	shuttingDown bool
	back         backend.Backend
	lock         *lockfile.File
	proxy        *forward.Proxy
	listenPort   uint16
	target       string
	status       backend.Status
	cancelWatch  context.CancelFunc
	watchDone    chan struct{}
}

func New(in io.Reader, out, errw io.Writer, factory backend.Factory) *Engine {
	if factory == nil {
		factory = func() backend.Backend { return backend.NewFake() }
	}
	return &Engine{
		in:      in,
		out:     out,
		err:     errw,
		newBack: factory,
		state:   protocol.StateStopped,
	}
}

func (e *Engine) Run() int {
	scanner := bufio.NewScanner(e.in)
	buf := make([]byte, 0, 64*1024)
	scanner.Buffer(buf, protocol.MaxLineBytes+1)
	handshook := false
	for scanner.Scan() {
		line := append([]byte(nil), scanner.Bytes()...)
		if !handshook {
			if !e.handshake(line) {
				continue
			}
			handshook = true
			e.emitEvent(&protocol.Message{
				Event:         protocol.EventReady,
				State:         protocol.StateStopped,
				HelperVersion: version.Version,
				Tailscale:     version.Tailscale,
			})
			msg, err := protocol.DecodeLine(line)
			if err == nil && msg.Command != "" {
				e.handleLine(line)
			}
		} else {
			e.handleLine(line)
		}
		e.mu.Lock()
		done := e.shuttingDown
		e.mu.Unlock()
		if done {
			break
		}
	}
	if err := scanner.Err(); err != nil {
		if errors.Is(err, bufio.ErrTooLong) {
			e.emitError("", protocol.ErrMessageTooLong, "line exceeded max length", true)
		} else if !errors.Is(err, io.EOF) {
			e.diag("stdin read error: %s", redact.String(err.Error()))
		}
	}
	e.cleanup(protocol.ErrParentEOF)
	return 0
}

func (e *Engine) handleLine(line []byte) {
	msg, err := protocol.DecodeLine(line)
	if err != nil {
		code := protocol.ErrMalformedJSON
		if errors.Is(err, protocol.ErrLineTooLong) {
			code = protocol.ErrMessageTooLong
		}
		e.emitError("", code, err.Error(), true)
		return
	}
	if msg.Command == "" {
		e.emitError(msg.RequestID, protocol.ErrUnknownCommand, "event on stdin ignored", true)
		return
	}
	if msg.SessionNonce == "" {
		e.emitError(msg.RequestID, protocol.ErrMissingSessionNonce, "sessionNonce required", false)
		return
	}
	e.mu.Lock()
	if e.nonce == "" {
		e.nonce = msg.SessionNonce
	}
	nonce := e.nonce
	e.mu.Unlock()
	if msg.SessionNonce != nonce {
		e.emitError(msg.RequestID, protocol.ErrSessionNonceMismatch, "sessionNonce mismatch", false)
		return
	}
	if code, detail := protocol.ValidateCommand(msg); code != "" {
		e.emitError(msg.RequestID, code, detail, true)
		return
	}
	switch msg.Command {
	case protocol.CmdStart:
		e.cmdStart(msg)
	case protocol.CmdStatus:
		e.cmdStatus(msg)
	case protocol.CmdStop:
		e.cmdStop(msg)
	case protocol.CmdLogout:
		e.cmdLogout(msg)
	case protocol.CmdShutdown:
		e.cmdShutdown(msg)
	}
}

func (e *Engine) cmdStart(msg *protocol.Message) {
	e.mu.Lock()
	if e.started {
		e.mu.Unlock()
		e.emitError(msg.RequestID, protocol.ErrAlreadyStarted, "already started", true)
		return
	}
	e.started = true
	e.target = msg.Target
	e.listenPort = msg.ListenPort
	e.state = protocol.StateStarting
	e.mu.Unlock()

	stateDir := filepath.Clean(msg.StateDir)
	lock, err := lockfile.Acquire(stateDir)
	if err != nil {
		e.failStart(msg.RequestID, protocol.ErrStateLocked, err)
		return
	}
	back := e.newBack()
	ctx, cancel := context.WithCancel(context.Background())
	if err := back.Start(ctx, backend.StartConfig{
		StateDir: stateDir,
		Hostname: hostname(msg.Hostname),
	}); err != nil {
		cancel()
		_ = lock.Close()
		e.failStart(msg.RequestID, protocol.ErrBackendFailed, err)
		return
	}
	watchCh, err := back.Watch(ctx)
	if err != nil {
		cancel()
		_ = back.Close()
		_ = lock.Close()
		e.failStart(msg.RequestID, protocol.ErrBackendFailed, err)
		return
	}
	e.mu.Lock()
	e.lock = lock
	e.back = back
	e.cancelWatch = cancel
	e.watchDone = make(chan struct{})
	e.mu.Unlock()

	e.emitEvent(&protocol.Message{
		RequestID: msg.RequestID,
		Event:     protocol.EventStateChanged,
		State:     protocol.StateStarting,
	})
	go e.watchLoop(watchCh)
}

func (e *Engine) failStart(requestID, code string, err error) {
	e.mu.Lock()
	e.started = false
	e.state = protocol.StateFailed
	e.mu.Unlock()
	e.emitError(requestID, code, err.Error(), true)
	e.emitEvent(&protocol.Message{Event: protocol.EventStateChanged, State: protocol.StateFailed, ErrorCode: code})
}

func (e *Engine) watchLoop(ch <-chan backend.Event) {
	defer close(e.watchDone)
	for ev := range ch {
		e.applyBackendEvent(ev)
	}
}

func (e *Engine) applyBackendEvent(ev backend.Event) {
	e.mu.Lock()
	if e.shuttingDown {
		e.mu.Unlock()
		return
	}
	st := string(ev.Status.State)
	if st == "" {
		st = string(ev.State)
	}
	prev := e.state
	e.status = ev.Status
	needListen := false
	switch st {
	case protocol.StateNeedsLogin:
		e.state = protocol.StateNeedsLogin
	case protocol.StateNeedsApproval:
		e.state = protocol.StateNeedsApproval
	case protocol.StateRunning:
		e.state = protocol.StateRunning
		needListen = e.proxy == nil
	case protocol.StateDegraded:
		e.state = protocol.StateDegraded
	case protocol.StateFailed:
		e.state = protocol.StateFailed
	case protocol.StateStarting:
		e.state = protocol.StateStarting
	}
	authURL := ev.AuthURL
	if authURL == "" {
		authURL = ev.Status.AuthURL
	}
	port := e.listenPort
	back := e.back
	target := e.target
	e.mu.Unlock()

	if st != prev && st != "" {
		e.emitEvent(&protocol.Message{
			Event:     protocol.EventStateChanged,
			State:     e.currentState(),
			TailnetIP: ev.Status.TailnetIP,
			NodeID:    ev.Status.NodeID,
			Port:      port,
		})
	}
	if authURL != "" && st == protocol.StateNeedsLogin {
		e.emitEvent(&protocol.Message{
			Event:   protocol.EventAuthRequired,
			State:   protocol.StateNeedsLogin,
			AuthURL: authURL,
		})
	}
	if needListen && back != nil {
		e.startListener(back, port, target)
	}
}

func (e *Engine) startListener(back backend.Backend, port uint16, target string) {
	e.mu.Lock()
	if e.proxy != nil || e.shuttingDown {
		e.mu.Unlock()
		return
	}
	e.mu.Unlock()
	ln, err := back.Listen(context.Background(), port)
	if err != nil {
		e.emitError("", protocol.ErrListenFailed, err.Error(), true)
		e.setState(protocol.StateFailed)
		return
	}
	p := forward.New(ln, forward.Config{Target: target, MaxConns: maxConns})
	e.mu.Lock()
	if e.proxy != nil || e.shuttingDown {
		e.mu.Unlock()
		_ = ln.Close()
		return
	}
	e.proxy = p
	e.mu.Unlock()
	go func() {
		_ = p.Serve()
	}()
	e.emitEvent(&protocol.Message{
		Event:     protocol.EventListening,
		State:     protocol.StateRunning,
		Port:      port,
		Listening: true,
		TailnetIP: e.currentStatus().TailnetIP,
		NodeID:    e.currentStatus().NodeID,
	})
}

func (e *Engine) cmdStatus(msg *protocol.Message) {
	e.mu.Lock()
	st := e.state
	status := e.status
	port := e.listenPort
	listening := e.proxy != nil
	conns := 0
	if e.proxy != nil {
		conns = e.proxy.Active()
	}
	e.mu.Unlock()
	e.emitEvent(&protocol.Message{
		RequestID:   msg.RequestID,
		Event:       protocol.EventStateChanged,
		State:       st,
		TailnetIP:   status.TailnetIP,
		NodeID:      status.NodeID,
		Port:        port,
		Listening:   listening,
		Connections: conns,
	})
}

func (e *Engine) cmdStop(msg *protocol.Message) {
	e.stopProxyAndBackend(false)
	e.emitEvent(&protocol.Message{
		RequestID: msg.RequestID,
		Event:     protocol.EventStopped,
		State:     protocol.StateStopped,
	})
}

func (e *Engine) cmdLogout(msg *protocol.Message) {
	e.mu.Lock()
	back := e.back
	e.mu.Unlock()
	if back == nil {
		e.emitError(msg.RequestID, protocol.ErrNotStarted, "not started", true)
		return
	}
	if err := back.Logout(context.Background()); err != nil {
		e.emitError(msg.RequestID, protocol.ErrBackendFailed, err.Error(), true)
		return
	}
	e.stopProxyOnly()
	e.setState(protocol.StateNeedsLogin)
	e.emitEvent(&protocol.Message{
		RequestID: msg.RequestID,
		Event:     protocol.EventStateChanged,
		State:     protocol.StateNeedsLogin,
	})
}

func (e *Engine) cmdShutdown(msg *protocol.Message) {
	e.mu.Lock()
	e.shuttingDown = true
	e.mu.Unlock()
	e.cleanup(protocol.ErrShutdown)
	e.emitEvent(&protocol.Message{
		RequestID: msg.RequestID,
		Event:     protocol.EventStopped,
		State:     protocol.StateStopped,
	})
}

func (e *Engine) stopProxyOnly() {
	e.mu.Lock()
	p := e.proxy
	e.proxy = nil
	e.mu.Unlock()
	if p != nil {
		_ = p.Close()
	}
}

func (e *Engine) stopProxyAndBackend(keepLock bool) {
	e.mu.Lock()
	e.state = protocol.StateStopping
	p := e.proxy
	e.proxy = nil
	cancel := e.cancelWatch
	back := e.back
	lock := e.lock
	watchDone := e.watchDone
	e.back = nil
	e.cancelWatch = nil
	if !keepLock {
		e.lock = nil
	}
	e.started = false
	e.mu.Unlock()
	if p != nil {
		_ = p.Close()
	}
	if cancel != nil {
		cancel()
	}
	if watchDone != nil {
		select {
		case <-watchDone:
		case <-time.After(shutdownWait):
		}
	}
	if back != nil {
		_ = back.Close()
	}
	if !keepLock && lock != nil {
		_ = lock.Close()
	}
	e.mu.Lock()
	e.state = protocol.StateStopped
	e.mu.Unlock()
}

func (e *Engine) cleanup(code string) {
	e.stopProxyAndBackend(false)
	_ = code
}

func (e *Engine) emitError(requestID, code, detail string, recoverable bool) {
	e.diag("error %s: %s", code, redact.String(detail))
	e.emitEvent(&protocol.Message{
		RequestID:   requestID,
		Event:       protocol.EventError,
		ErrorCode:   code,
		Error:       redact.String(detail),
		Recoverable: recoverable,
		State:       e.currentState(),
	})
}

func (e *Engine) emitEvent(m *protocol.Message) {
	e.mu.Lock()
	e.eventID++
	m.EventID = e.eventID
	m.SessionNonce = e.nonce
	m.ProtocolVersion = version.Protocol
	if m.HelperVersion == "" {
		m.HelperVersion = version.Version
	}
	out := e.out
	e.mu.Unlock()
	line, err := protocol.EncodeLine(m)
	if err != nil {
		e.diag("encode failed: %s", err.Error())
		return
	}
	e.mu.Lock()
	defer e.mu.Unlock()
	_, _ = out.Write(line)
}

func (e *Engine) diag(format string, args ...any) {
	msg := redact.String(fmt.Sprintf(format, args...))
	e.mu.Lock()
	defer e.mu.Unlock()
	_, _ = fmt.Fprintf(e.err, "helper: %s\n", msg)
}

func (e *Engine) currentState() string {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.state
}

func (e *Engine) currentStatus() backend.Status {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.status
}

func (e *Engine) setState(st string) {
	e.mu.Lock()
	e.state = st
	e.mu.Unlock()
	e.emitEvent(&protocol.Message{Event: protocol.EventStateChanged, State: st})
}

func hostname(h string) string {
	if h != "" {
		return h
	}
	host, err := os.Hostname()
	if err != nil || host == "" {
		return "monkeycraft"
	}
	return "monkeycraft-" + host
}

func (e *Engine) handshake(line []byte) bool {
	msg, err := protocol.DecodeLine(line)
	if err != nil {
		code := protocol.ErrMalformedJSON
		if errors.Is(err, protocol.ErrLineTooLong) {
			code = protocol.ErrMessageTooLong
		}
		e.emitError("", code, err.Error(), true)
		return false
	}
	if msg.ProtocolVersion != version.Protocol {
		e.emitError(msg.RequestID, protocol.ErrProtocolVersionUnsupported,
			fmt.Sprintf("got %d want %d", msg.ProtocolVersion, version.Protocol), false)
		return false
	}
	if msg.SessionNonce == "" {
		e.emitError(msg.RequestID, protocol.ErrMissingSessionNonce, "sessionNonce required", false)
		return false
	}
	e.mu.Lock()
	e.nonce = msg.SessionNonce
	e.mu.Unlock()
	return true
}
