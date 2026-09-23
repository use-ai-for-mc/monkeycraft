package tcpbridge

import (
	"bytes"
	"context"
	"io"
	"net"
	"sync"
	"testing"
	"time"

	"monkeycraft.dev/web-tailscale/internal/rpcschema"
	"monkeycraft.dev/web-tailscale/internal/wsframe"
)

func startEcho(t *testing.T) (addr string, closeFn func()) {
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
			c, err := ln.Accept()
			if err != nil {
				return
			}
			go func(c net.Conn) {
				defer c.Close()
				_, _ = io.Copy(c, c)
			}(c)
		}
	}()
	return ln.Addr().String(), func() {
		ln.Close()
		wg.Wait()
	}
}

func TestEchoRoundTrip(t *testing.T) {
	addr, stop := startEcho(t)
	defer stop()
	a, err := net.ResolveTCPAddr("tcp", addr)
	if err != nil {
		t.Fatal(err)
	}
	lnPort := a.Port

	b := New(func(ctx context.Context, network, address string) (net.Conn, error) {
		d := net.Dialer{}
		return d.DialContext(ctx, network, addr)
	})
	h, err := b.Dial(context.Background(), rpcschema.DialTcpPayload{Host: "100.64.0.1", Port: lnPort})
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close(h.ID)
	msg := bytes.Repeat([]byte("x"), 8192)
	go func() { _, _ = h.Write(msg) }()
	buf := make([]byte, len(msg))
	if _, err := io.ReadFull(h, buf); err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(buf, msg) {
		t.Fatal("mismatch")
	}
}

func TestConnLimit(t *testing.T) {
	addr, stop := startEcho(t)
	defer stop()
	b := New(func(ctx context.Context, network, address string) (net.Conn, error) {
		d := net.Dialer{}
		return d.DialContext(ctx, network, addr)
	})
	h1, err := b.Dial(context.Background(), rpcschema.DialTcpPayload{Host: "100.64.0.1", Port: 9600})
	if err != nil {
		t.Fatal(err)
	}
	defer b.Close(h1.ID)
	if _, err := b.Dial(context.Background(), rpcschema.DialTcpPayload{Host: "100.64.0.1", Port: 9600}); err != ErrConnLimit {
		t.Fatalf("got %v", err)
	}
}

func TestRejectLoopbackLiteralWhenNotViaTestDial(t *testing.T) {
	b := New(nil)
	if _, err := b.Dial(context.Background(), rpcschema.DialTcpPayload{Host: "127.0.0.1", Port: 9}); err != ErrInvalidTarget {
		t.Fatalf("got %v", err)
	}
}

func TestRejectBadHost(t *testing.T) {
	b := New(nil)
	if _, err := b.Dial(context.Background(), rpcschema.DialTcpPayload{Host: "host;rm -rf", Port: 9}); err != ErrInvalidTarget {
		t.Fatalf("got %v", err)
	}
}

func TestWebSocketOverEchoTCP(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	errc := make(chan error, 1)
	go func() {
		c, err := ln.Accept()
		if err != nil {
			errc <- err
			return
		}
		defer c.Close()
		srv := wsframe.NewConn(c, wsframe.RoleServer, wsframe.DefaultLimits())
		msg, err := srv.ReadMessage()
		if err != nil {
			errc <- err
			return
		}
		if err := srv.WriteMessage(msg.Opcode, msg.Payload); err != nil {
			errc <- err
			return
		}
		errc <- nil
	}()

	d := net.Dialer{Timeout: time.Second}
	raw, err := d.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer raw.Close()
	cli := wsframe.NewConn(raw, wsframe.RoleClient, wsframe.DefaultLimits())
	big := bytes.Repeat([]byte("h264-frame-"), 4000)
	if err := cli.WriteFragmented(wsframe.OpcodeBinary, big, 1024); err != nil {
		t.Fatal(err)
	}
	msg, err := cli.ReadMessage()
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(msg.Payload, big) {
		t.Fatalf("n=%d", len(msg.Payload))
	}
	if err := <-errc; err != nil {
		t.Fatal(err)
	}
}

func TestCancelDial(t *testing.T) {
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	defer ln.Close()
	b := New(func(ctx context.Context, network, address string) (net.Conn, error) {
		<-ctx.Done()
		return nil, ctx.Err()
	})
	ctx, cancel := context.WithTimeout(context.Background(), 20*time.Millisecond)
	defer cancel()
	_, err = b.Dial(ctx, rpcschema.DialTcpPayload{Host: "100.64.0.1", Port: 9600, TimeoutMs: 50})
	if err == nil {
		t.Fatal("expected timeout")
	}
}
