package backend

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net"
	"net/netip"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/redact"
	"tailscale.com/client/local"
	"tailscale.com/ipn"
	"tailscale.com/ipn/ipnstate"
	"tailscale.com/tsnet"
)

type tsnetServer interface {
	Start() error
	LocalClient() (*local.Client, error)
	Listen(network, addr string) (net.Listener, error)
	Close() error
}

type tsnetCtor func(dir, hostname string, logf func(string, ...any)) tsnetServer

type realServer struct {
	s *tsnet.Server
}

func (r *realServer) Start() error { return r.s.Start() }
func (r *realServer) LocalClient() (*local.Client, error) {
	return r.s.LocalClient()
}
func (r *realServer) Listen(network, addr string) (net.Listener, error) {
	return r.s.Listen(network, addr)
}
func (r *realServer) Close() error { return r.s.Close() }

func defaultTsnetCtor(dir, hostname string, logf func(string, ...any)) tsnetServer {
	return &realServer{s: &tsnet.Server{
		Dir:       dir,
		Hostname:  hostname,
		Logf:      func(string, ...any) {},
		UserLogf:  logf,
		Ephemeral: false,
	}}
}

type Tsnet struct {
	ctor tsnetCtor
	logf func(string, ...any)

	mu     sync.Mutex
	srv    tsnetServer
	lc     *local.Client
	cancel context.CancelFunc
}

func NewTsnet() *Tsnet {
	return NewTsnetWith(defaultTsnetCtor, func(format string, args ...any) {
		fmt.Fprintf(os.Stderr, "tsnet: %s\n", redact.String(fmt.Sprintf(format, args...)))
	})
}

func NewTsnetWith(ctor tsnetCtor, logf func(string, ...any)) *Tsnet {
	if ctor == nil {
		ctor = defaultTsnetCtor
	}
	if logf == nil {
		logf = func(string, ...any) {}
	}
	return &Tsnet{ctor: ctor, logf: logf}
}

func init() {
	SetDefaultFactory(func() Backend { return NewTsnet() })
}

func (t *Tsnet) Start(_ context.Context, cfg StartConfig) error {
	if strings.TrimSpace(cfg.StateDir) == "" {
		return errors.New("stateDir required")
	}
	if err := os.MkdirAll(cfg.StateDir, 0o700); err != nil {
		return err
	}
	srv := t.ctor(cfg.StateDir, cfg.Hostname, t.logf)
	if err := srv.Start(); err != nil {
		_ = srv.Close()
		return err
	}
	lc, err := srv.LocalClient()
	if err != nil {
		_ = srv.Close()
		return err
	}
	t.mu.Lock()
	t.srv = srv
	t.lc = lc
	t.mu.Unlock()
	return nil
}

func (t *Tsnet) Watch(ctx context.Context) (<-chan Event, error) {
	t.mu.Lock()
	lc := t.lc
	t.mu.Unlock()
	if lc == nil {
		return nil, errors.New("backend not started")
	}
	watchCtx, cancel := context.WithCancel(ctx)
	t.mu.Lock()
	if t.cancel != nil {
		t.cancel()
	}
	t.cancel = cancel
	t.mu.Unlock()

	watcher, err := lc.WatchIPNBus(watchCtx, ipn.NotifyInitialState|ipn.NotifyInitialStatus)
	if err != nil {
		cancel()
		return nil, fmt.Errorf("WatchIPNBus: %w", err)
	}
	ch := make(chan Event, 16)
	go func() {
		defer close(ch)
		defer watcher.Close()
		loginRequested := false
		requestLogin := func() bool {
			if loginRequested {
				return true
			}
			loginRequested = true
			if err := lc.StartLoginInteractive(watchCtx); err != nil {
				select {
				case ch <- Event{State: StateFailed, Err: fmt.Errorf("StartLoginInteractive: %w", err), Status: Status{State: StateFailed}}:
				case <-watchCtx.Done():
				}
				return false
			}
			return true
		}
		if st, err := lc.StatusWithoutPeers(watchCtx); err == nil && st.BackendState == "NeedsLogin" {
			requestLogin()
		}
		for {
			n, err := watcher.Next()
			if err != nil {
				if watchCtx.Err() != nil || errors.Is(err, io.EOF) || errors.Is(err, context.Canceled) {
					return
				}
				select {
				case ch <- Event{State: StateFailed, Err: err, Status: Status{State: StateFailed}}:
				case <-watchCtx.Done():
				}
				return
			}
			ev := eventFromNotify(n)
			if ev.State == StateNeedsLogin && ev.AuthURL == "" && !loginRequested {
				requestLogin()
			}
			needsStatus := ev.State == "" || (ev.State == StateRunning &&
				(ev.Status.TailnetIP == "" || ev.Status.NodeID == ""))
			if needsStatus && ev.AuthURL == "" && ev.Err == nil {
				if st, err := lc.StatusWithoutPeers(watchCtx); err == nil {
					statusEvent := eventFromIPNStatus(st)
					if ev.State == "" {
						ev = statusEvent
					} else {
						ev.Status = statusEvent.Status
					}
				}
			}
			select {
			case ch <- ev:
			case <-watchCtx.Done():
				return
			}
		}
	}()
	return ch, nil
}

func (t *Tsnet) Listen(_ context.Context, port uint16) (net.Listener, error) {
	t.mu.Lock()
	srv := t.srv
	t.mu.Unlock()
	if srv == nil {
		return nil, errors.New("backend not started")
	}
	return srv.Listen("tcp", fmt.Sprintf(":%d", port))
}

func (t *Tsnet) Status(ctx context.Context) (Status, error) {
	t.mu.Lock()
	lc := t.lc
	t.mu.Unlock()
	if lc == nil {
		return Status{State: StateStopped}, nil
	}
	st, err := lc.StatusWithoutPeers(ctx)
	if err != nil {
		return Status{}, err
	}
	return eventFromIPNStatus(st).Status, nil
}

func (t *Tsnet) Logout(ctx context.Context) error {
	t.mu.Lock()
	lc := t.lc
	t.mu.Unlock()
	if lc == nil {
		return errors.New("backend not started")
	}
	return lc.Logout(ctx)
}

func (t *Tsnet) Close() error {
	t.mu.Lock()
	cancel := t.cancel
	srv := t.srv
	t.cancel = nil
	t.srv = nil
	t.lc = nil
	t.mu.Unlock()
	if cancel != nil {
		cancel()
	}
	if srv != nil {
		done := make(chan struct{})
		go func() {
			_ = srv.Close()
			close(done)
		}()
		select {
		case <-done:
		case <-time.After(5 * time.Second):
		}
	}
	return nil
}

func eventFromNotify(n ipn.Notify) Event {
	ev := Event{}
	if n.BrowseToURL != nil && *n.BrowseToURL != "" {
		ev.AuthURL = *n.BrowseToURL
		ev.Status.AuthURL = *n.BrowseToURL
	}
	if n.ErrMessage != nil && *n.ErrMessage != "" {
		ev.Err = errors.New(*n.ErrMessage)
	}
	if n.State != nil {
		ev.State = mapIPNState(*n.State, ev.AuthURL)
		ev.Status.State = ev.State
	}
	if n.InitialStatus != nil {
		fromStatus := eventFromIPNStatus(n.InitialStatus)
		if ev.AuthURL == "" {
			ev.AuthURL = fromStatus.AuthURL
			ev.Status.AuthURL = fromStatus.AuthURL
		}
		if ev.State == "" {
			ev.State = fromStatus.State
			ev.Status.State = fromStatus.State
		}
		ev.Status.TailnetIP = fromStatus.Status.TailnetIP
		ev.Status.NodeID = fromStatus.Status.NodeID
	}
	if ev.AuthURL != "" && ev.State == "" {
		ev.State = StateNeedsLogin
		ev.Status.State = StateNeedsLogin
	}
	return ev
}

func eventFromIPNStatus(st *ipnstate.Status) Event {
	if st == nil {
		return Event{State: StateStarting, Status: Status{State: StateStarting}}
	}
	auth := st.AuthURL
	state := mapBackendState(st.BackendState, auth)
	id := ""
	if st.Self != nil {
		id = string(st.Self.ID)
	}
	return Event{
		State:   state,
		AuthURL: auth,
		Status: Status{
			State:     state,
			AuthURL:   auth,
			TailnetIP: firstIP(st.TailscaleIPs),
			NodeID:    id,
		},
	}
}

func mapIPNState(s ipn.State, authURL string) State {
	switch s {
	case ipn.NeedsLogin:
		return StateNeedsLogin
	case ipn.NeedsMachineAuth:
		return StateNeedsApproval
	case ipn.Starting:
		return StateStarting
	case ipn.Running:
		return StateRunning
	case ipn.Stopped:
		return StateStopped
	case ipn.NoState:
		if authURL != "" {
			return StateNeedsLogin
		}
		return StateStarting
	default:
		if authURL != "" {
			return StateNeedsLogin
		}
		return StateDegraded
	}
}

func mapBackendState(s, authURL string) State {
	switch s {
	case "NeedsLogin":
		return StateNeedsLogin
	case "NeedsMachineAuth":
		return StateNeedsApproval
	case "Starting":
		return StateStarting
	case "Running":
		return StateRunning
	case "Stopped":
		return StateStopped
	case "NoState":
		if authURL != "" {
			return StateNeedsLogin
		}
		return StateStarting
	default:
		if authURL != "" {
			return StateNeedsLogin
		}
		return StateDegraded
	}
}

func firstIP(ips []netip.Addr) string {
	for _, ip := range ips {
		if ip.Is4() {
			return ip.String()
		}
	}
	if len(ips) > 0 {
		return ips[0].String()
	}
	return ""
}
