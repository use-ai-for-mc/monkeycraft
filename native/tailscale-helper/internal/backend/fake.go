package backend

import (
	"context"
	"errors"
	"net"
	"sync"
)

type Fake struct {
	mu        sync.Mutex
	started   bool
	closed    bool
	cfg       StartConfig
	status    Status
	watchers  []chan Event
	listenErr error
	startErr  error
	logoutErr error
	listener  net.Listener
	listenFn  func(ctx context.Context, port uint16) (net.Listener, error)
}

func NewFake() *Fake {
	return &Fake{
		status: Status{State: StateStopped},
	}
}

func (f *Fake) SetStartError(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.startErr = err
}

func (f *Fake) SetListenError(err error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.listenErr = err
}

func (f *Fake) SetListenFn(fn func(ctx context.Context, port uint16) (net.Listener, error)) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.listenFn = fn
}

func (f *Fake) Start(_ context.Context, cfg StartConfig) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.startErr != nil {
		return f.startErr
	}
	if f.started {
		return errors.New("already started")
	}
	f.started = true
	f.cfg = cfg
	f.status = Status{State: StateStarting}
	f.emitLocked(Event{State: StateStarting, Status: f.status})
	return nil
}

func (f *Fake) Emit(ev Event) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if ev.Status.State == "" {
		ev.Status.State = ev.State
	}
	if ev.State != "" {
		f.status.State = ev.State
	}
	if ev.AuthURL != "" {
		f.status.AuthURL = ev.AuthURL
	}
	if ev.Status.TailnetIP != "" {
		f.status.TailnetIP = ev.Status.TailnetIP
	}
	if ev.Status.NodeID != "" {
		f.status.NodeID = ev.Status.NodeID
	}
	ev.Status = f.status
	f.emitLocked(ev)
}

func (f *Fake) emitLocked(ev Event) {
	if f.closed {
		return
	}
	for _, w := range f.watchers {
		select {
		case w <- ev:
		default:
		}
	}
}

func (f *Fake) Watch(ctx context.Context) (<-chan Event, error) {
	ch := make(chan Event, 16)
	f.mu.Lock()
	if f.closed {
		f.mu.Unlock()
		close(ch)
		return ch, nil
	}
	f.watchers = append(f.watchers, ch)
	st := f.status
	f.mu.Unlock()
	select {
	case ch <- Event{State: st.State, AuthURL: st.AuthURL, Status: st}:
	default:
	}
	go func() {
		<-ctx.Done()
		f.removeWatcher(ch)
	}()
	return ch, nil
}

func (f *Fake) removeWatcher(ch chan Event) {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.closed {
		return
	}
	for i, w := range f.watchers {
		if w == ch {
			f.watchers = append(f.watchers[:i], f.watchers[i+1:]...)
			close(ch)
			return
		}
	}
}

func (f *Fake) Listen(ctx context.Context, port uint16) (net.Listener, error) {
	f.mu.Lock()
	err := f.listenErr
	fn := f.listenFn
	f.mu.Unlock()
	if err != nil {
		return nil, err
	}
	if fn != nil {
		ln, err := fn(ctx, port)
		if err != nil {
			return nil, err
		}
		f.mu.Lock()
		f.listener = ln
		f.mu.Unlock()
		return ln, nil
	}
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		return nil, err
	}
	f.mu.Lock()
	f.listener = ln
	f.mu.Unlock()
	return ln, nil
}

func (f *Fake) Status(context.Context) (Status, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.status, nil
}

func (f *Fake) Logout(context.Context) error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.logoutErr != nil {
		return f.logoutErr
	}
	f.status = Status{State: StateNeedsLogin}
	f.emitLocked(Event{State: StateNeedsLogin, Status: f.status})
	return nil
}

func (f *Fake) Close() error {
	f.mu.Lock()
	defer f.mu.Unlock()
	if f.closed {
		return nil
	}
	f.closed = true
	if f.listener != nil {
		_ = f.listener.Close()
	}
	for _, w := range f.watchers {
		close(w)
	}
	f.watchers = nil
	return nil
}

func (f *Fake) Config() StartConfig {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.cfg
}
