package forward

import (
	"context"
	"errors"
	"io"
	"net"
	"sync"
	"sync/atomic"
	"time"
)

const (
	DefaultMaxConns    = 8
	DefaultIdleTimeout = 30 * time.Minute
	copyBufSize        = 32 * 1024
)

type Config struct {
	Target      string
	MaxConns    int
	IdleTimeout time.Duration
	DialTimeout time.Duration
	Dial        func(ctx context.Context, network, address string) (net.Conn, error)
}

type Proxy struct {
	cfg     Config
	ln      net.Listener
	mu      sync.Mutex
	conns   map[net.Conn]struct{}
	active  atomic.Int32
	closed  atomic.Bool
	wg      sync.WaitGroup
	ctx     context.Context
	cancel  context.CancelFunc
}

func New(ln net.Listener, cfg Config) *Proxy {
	if cfg.MaxConns <= 0 {
		cfg.MaxConns = DefaultMaxConns
	}
	if cfg.IdleTimeout <= 0 {
		cfg.IdleTimeout = DefaultIdleTimeout
	}
	if cfg.DialTimeout <= 0 {
		cfg.DialTimeout = 5 * time.Second
	}
	if cfg.Dial == nil {
		d := net.Dialer{Timeout: cfg.DialTimeout}
		cfg.Dial = d.DialContext
	}
	ctx, cancel := context.WithCancel(context.Background())
	return &Proxy{
		cfg:    cfg,
		ln:     ln,
		conns:  make(map[net.Conn]struct{}),
		ctx:    ctx,
		cancel: cancel,
	}
}

func (p *Proxy) Serve() error {
	for {
		c, err := p.ln.Accept()
		if err != nil {
			if p.closed.Load() || errors.Is(err, net.ErrClosed) {
				return nil
			}
			return err
		}
		if int(p.active.Load()) >= p.cfg.MaxConns {
			_ = c.Close()
			continue
		}
		p.wg.Add(1)
		go func() {
			defer p.wg.Done()
			p.handle(c)
		}()
	}
}

func (p *Proxy) Active() int {
	return int(p.active.Load())
}

func (p *Proxy) Close() error {
	if !p.closed.CompareAndSwap(false, true) {
		return nil
	}
	p.cancel()
	err := p.ln.Close()
	p.mu.Lock()
	for c := range p.conns {
		_ = c.Close()
	}
	p.mu.Unlock()
	p.wg.Wait()
	return err
}

func (p *Proxy) handle(src net.Conn) {
	p.track(src, true)
	defer p.track(src, false)
	defer src.Close()

	ctx, cancel := context.WithTimeout(p.ctx, p.cfg.DialTimeout)
	dst, err := p.cfg.Dial(ctx, "tcp", p.cfg.Target)
	cancel()
	if err != nil {
		return
	}
	p.track(dst, true)
	defer p.track(dst, false)
	defer dst.Close()

	srcIdle := newIdleConn(src, p.cfg.IdleTimeout)
	dstIdle := newIdleConn(dst, p.cfg.IdleTimeout)

	var wg sync.WaitGroup
	wg.Add(2)
	go func() {
		defer wg.Done()
		_, _ = copyHalf(dstIdle, srcIdle)
		closeWrite(dst)
	}()
	go func() {
		defer wg.Done()
		_, _ = copyHalf(srcIdle, dstIdle)
		closeWrite(src)
	}()
	wg.Wait()
}

func copyHalf(dst io.Writer, src io.Reader) (int64, error) {
	buf := make([]byte, copyBufSize)
	return io.CopyBuffer(dst, src, buf)
}

func closeWrite(c net.Conn) {
	type closer interface{ CloseWrite() error }
	if cw, ok := c.(closer); ok {
		_ = cw.CloseWrite()
		return
	}
	if ic, ok := c.(*idleConn); ok {
		if cw, ok := ic.Conn.(closer); ok {
			_ = cw.CloseWrite()
			return
		}
	}
}

func (p *Proxy) track(c net.Conn, add bool) {
	p.mu.Lock()
	defer p.mu.Unlock()
	if add {
		p.conns[c] = struct{}{}
		p.active.Add(1)
		return
	}
	if _, ok := p.conns[c]; ok {
		delete(p.conns, c)
		p.active.Add(-1)
	}
}

type idleConn struct {
	net.Conn
	idle time.Duration
}

func newIdleConn(c net.Conn, idle time.Duration) *idleConn {
	ic := &idleConn{Conn: c, idle: idle}
	_ = ic.Conn.SetDeadline(time.Now().Add(idle))
	return ic
}

func (c *idleConn) Read(b []byte) (int, error) {
	n, err := c.Conn.Read(b)
	if n > 0 {
		_ = c.Conn.SetDeadline(time.Now().Add(c.idle))
	}
	return n, err
}

func (c *idleConn) Write(b []byte) (int, error) {
	n, err := c.Conn.Write(b)
	if n > 0 {
		_ = c.Conn.SetDeadline(time.Now().Add(c.idle))
	}
	return n, err
}

func (c *idleConn) CloseWrite() error {
	type closer interface{ CloseWrite() error }
	if cw, ok := c.Conn.(closer); ok {
		return cw.CloseWrite()
	}
	return nil
}
