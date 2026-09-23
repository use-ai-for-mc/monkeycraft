package tcpbridge

import (
	"context"
	"errors"
	"io"
	"net"
	"net/netip"
	"strconv"
	"sync"
	"time"

	"monkeycraft.dev/web-tailscale/internal/rpcschema"
)

const (
	MaxConns       = 1
	MaxWriteQueue  = 32
	MaxReadChunk   = 64 << 10
	DefaultTimeout = 15 * time.Second
)

var (
	ErrConnLimit     = errors.New("tcpbridge: connection limit")
	ErrInvalidTarget = errors.New("tcpbridge: invalid target")
	ErrNotFound      = errors.New("tcpbridge: conn not found")
	ErrQueueFull     = errors.New("tcpbridge: write queue full")
)

type DialFunc func(ctx context.Context, network, address string) (net.Conn, error)

type ConnHandle struct {
	ID   string
	conn net.Conn

	mu     sync.Mutex
	closed bool
}

type Bridge struct {
	dial DialFunc
	mu   sync.Mutex
	next int
	live map[string]*ConnHandle
}

func New(dial DialFunc) *Bridge {
	if dial == nil {
		dial = (&net.Dialer{}).DialContext
	}
	return &Bridge{dial: dial, live: map[string]*ConnHandle{}}
}

func (b *Bridge) Dial(ctx context.Context, p rpcschema.DialTcpPayload) (*ConnHandle, error) {
	if err := rpcschema.ValidateDial(p); err != nil {
		return nil, ErrInvalidTarget
	}
	if err := validateHost(p.Host); err != nil {
		return nil, err
	}
	timeout := DefaultTimeout
	if p.TimeoutMs > 0 {
		timeout = time.Duration(p.TimeoutMs) * time.Millisecond
	}
	ctx, cancel := context.WithTimeout(ctx, timeout)
	defer cancel()

	b.mu.Lock()
	if len(b.live) >= MaxConns {
		b.mu.Unlock()
		return nil, ErrConnLimit
	}
	b.mu.Unlock()

	addr := net.JoinHostPort(p.Host, strconv.Itoa(p.Port))
	c, err := b.dial(ctx, "tcp", addr)
	if err != nil {
		return nil, err
	}
	b.mu.Lock()
	defer b.mu.Unlock()
	if len(b.live) >= MaxConns {
		_ = c.Close()
		return nil, ErrConnLimit
	}
	b.next++
	id := "c" + strconv.Itoa(b.next)
	h := &ConnHandle{ID: id, conn: c}
	b.live[id] = h
	return h, nil
}

func validateHost(host string) error {
	if host == "" {
		return ErrInvalidTarget
	}
	if ip, err := netip.ParseAddr(host); err == nil {
		if ip.IsLoopback() || ip.IsMulticast() || ip.IsUnspecified() {
			return ErrInvalidTarget
		}
		return nil
	}
	for _, c := range host {
		if (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9') || c == '-' || c == '.' {
			continue
		}
		return ErrInvalidTarget
	}
	return nil
}

func (b *Bridge) Get(id string) (*ConnHandle, error) {
	b.mu.Lock()
	defer b.mu.Unlock()
	h, ok := b.live[id]
	if !ok {
		return nil, ErrNotFound
	}
	return h, nil
}

func (b *Bridge) Close(id string) error {
	b.mu.Lock()
	h, ok := b.live[id]
	if ok {
		delete(b.live, id)
	}
	b.mu.Unlock()
	if !ok {
		return ErrNotFound
	}
	return h.Close()
}

func (b *Bridge) CloseAll() {
	b.mu.Lock()
	live := b.live
	b.live = map[string]*ConnHandle{}
	b.mu.Unlock()
	for _, h := range live {
		_ = h.Close()
	}
}

func (h *ConnHandle) Read(p []byte) (int, error) {
	if len(p) > MaxReadChunk {
		p = p[:MaxReadChunk]
	}
	return h.conn.Read(p)
}

func (h *ConnHandle) Write(p []byte) (int, error) {
	return h.conn.Write(p)
}

func (h *ConnHandle) Close() error {
	h.mu.Lock()
	defer h.mu.Unlock()
	if h.closed {
		return nil
	}
	h.closed = true
	return h.conn.Close()
}

func (h *ConnHandle) CloseWrite() error {
	type closer interface {
		CloseWrite() error
	}
	if cw, ok := h.conn.(closer); ok {
		return cw.CloseWrite()
	}
	return h.Close()
}

func CopyN(dst io.Writer, src io.Reader, n int64) (int64, error) {
	return io.CopyN(dst, src, n)
}
