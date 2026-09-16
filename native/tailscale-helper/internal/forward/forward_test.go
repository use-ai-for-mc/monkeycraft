package forward

import (
	"io"
	"net"
	"sync"
	"testing"
	"time"
)

func startEcho(t *testing.T) (addr string, closeFn func()) {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	var wg sync.WaitGroup
	done := make(chan struct{})
	wg.Add(1)
	go func() {
		defer wg.Done()
		for {
			c, err := ln.Accept()
			if err != nil {
				select {
				case <-done:
					return
				default:
					return
				}
			}
			wg.Add(1)
			go func(c net.Conn) {
				defer wg.Done()
				defer c.Close()
				_, _ = io.Copy(c, c)
			}(c)
		}
	}()
	return ln.Addr().String(), func() {
		close(done)
		_ = ln.Close()
		wg.Wait()
	}
}

func TestBidirectionalAndHalfClose(t *testing.T) {
	target, stop := startEcho(t)
	defer stop()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	p := New(ln, Config{Target: target, IdleTimeout: time.Minute})
	go func() { _ = p.Serve() }()
	defer p.Close()

	c, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	if _, err := c.Write([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	buf := make([]byte, 4)
	if _, err := io.ReadFull(c, buf); err != nil {
		t.Fatal(err)
	}
	if string(buf) != "ping" {
		t.Fatalf("got %q", buf)
	}
	if cw, ok := c.(*net.TCPConn); ok {
		_ = cw.CloseWrite()
	}
	deadline := time.Now().Add(2 * time.Second)
	_ = c.SetReadDeadline(deadline)
	_, err = c.Read(make([]byte, 1))
	if err == nil {
		t.Fatal("expected EOF after half close")
	}
}

func TestMaxConns(t *testing.T) {
	block := make(chan struct{})
	lnEcho, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	go func() {
		for {
			c, err := lnEcho.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				<-block
			}(c)
		}
	}()
	defer lnEcho.Close()

	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	p := New(ln, Config{Target: lnEcho.Addr().String(), MaxConns: 2, IdleTimeout: time.Minute})
	go func() { _ = p.Serve() }()
	defer p.Close()

	c1, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c1.Close()
	c2, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c2.Close()
	time.Sleep(50 * time.Millisecond)
	c3, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c3.Close()
	_ = c3.SetReadDeadline(time.Now().Add(500 * time.Millisecond))
	n, err := c3.Read(make([]byte, 1))
	if n != 0 && err == nil {
		t.Fatal("expected third connection to be closed")
	}
	close(block)
}

func TestSlowConsumerDoesNotPanic(t *testing.T) {
	lnEcho, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer lnEcho.Close()
	go func() {
		c, err := lnEcho.Accept()
		if err != nil {
			return
		}
		defer c.Close()
		_, _ = c.Write(make([]byte, 256*1024))
	}()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	p := New(ln, Config{Target: lnEcho.Addr().String(), IdleTimeout: 2 * time.Second})
	go func() { _ = p.Serve() }()
	defer p.Close()
	c, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer c.Close()
	time.Sleep(100 * time.Millisecond)
	_, _ = io.CopyN(io.Discard, c, 1024)
}
