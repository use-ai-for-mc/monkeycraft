package wsframe

import (
	"bytes"
	"io"
	"sync"
	"testing"
	"time"
)

type streamDuplex struct {
	r *io.PipeReader
	w *io.PipeWriter
}

func (d streamDuplex) Read(p []byte) (int, error)  { return d.r.Read(p) }
func (d streamDuplex) Write(p []byte) (int, error) { return d.w.Write(p) }
func (d streamDuplex) Close() error {
	_ = d.w.Close()
	_ = d.r.Close()
	return nil
}

func (d streamDuplex) CloseWrite() error { return d.w.Close() }

type pipePair struct {
	c streamDuplex
	s streamDuplex
}

func newPipe() pipePair {
	ar, aw := io.Pipe()
	br, bw := io.Pipe()
	return pipePair{
		c: streamDuplex{r: ar, w: bw},
		s: streamDuplex{r: br, w: aw},
	}
}

func TestFragmentationAndContinuation(t *testing.T) {
	p := newPipe()
	defer p.c.Close()
	defer p.s.Close()
	client := NewConn(p.c, RoleClient, DefaultLimits())
	server := NewConn(p.s, RoleServer, DefaultLimits())

	payload := bytes.Repeat([]byte("frag-"), 20)
	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		if err := client.WriteFragmented(OpcodeBinary, payload, 7); err != nil {
			t.Errorf("write: %v", err)
		}
	}()
	msg, err := server.ReadMessage()
	if err != nil {
		t.Fatal(err)
	}
	if msg.Opcode != OpcodeBinary || !bytes.Equal(msg.Payload, payload) {
		t.Fatalf("got op=%s n=%d", msg.Opcode, len(msg.Payload))
	}
	wg.Wait()
}

func TestPingPong(t *testing.T) {
	p := newPipe()
	defer p.c.Close()
	defer p.s.Close()
	client := NewConn(p.c, RoleClient, DefaultLimits())
	server := NewConn(p.s, RoleServer, DefaultLimits())

	errc := make(chan error, 1)
	go func() {
		_, err := server.ReadMessage()
		errc <- err
	}()
	go func() {
		_, _ = client.ReadMessage()
	}()
	if err := client.WritePing([]byte("ping")); err != nil {
		t.Fatal(err)
	}
	if err := client.WriteMessage(OpcodeText, []byte("ok")); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-errc:
		if err != nil {
			t.Fatalf("server: %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout")
	}
}

func TestCloseHandshake(t *testing.T) {
	p := newPipe()
	defer p.c.Close()
	defer p.s.Close()
	client := NewConn(p.c, RoleClient, DefaultLimits())
	server := NewConn(p.s, RoleServer, DefaultLimits())

	errc := make(chan error, 2)
	go func() {
		_, err := server.ReadMessage()
		errc <- err
	}()
	go func() {
		_, err := client.ReadMessage()
		errc <- err
	}()
	if err := client.WriteClose(CloseNormalClosure, "done"); err != nil {
		t.Fatal(err)
	}
	for i := 0; i < 2; i++ {
		select {
		case err := <-errc:
			if err != ErrClosed {
				t.Fatalf("got %v", err)
			}
		case <-time.After(time.Second):
			t.Fatal("timeout")
		}
	}
}

func TestInvalidUTF8Text(t *testing.T) {
	p := newPipe()
	defer p.c.Close()
	defer p.s.Close()
	client := NewConn(p.c, RoleClient, DefaultLimits())
	server := NewConn(p.s, RoleServer, DefaultLimits())
	errc := make(chan error, 1)
	go func() {
		_, err := server.ReadMessage()
		errc <- err
	}()
	if err := client.WriteMessage(OpcodeText, []byte{0xff, 0xfe}); err != nil {
		t.Fatal(err)
	}
	select {
	case err := <-errc:
		if err != ErrInvalidUTF8 {
			t.Fatalf("got %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout")
	}
}

func TestHalfCloseStillReads(t *testing.T) {
	p := newPipe()
	defer p.c.Close()
	defer p.s.Close()
	client := NewConn(p.c, RoleClient, DefaultLimits())
	server := NewConn(p.s, RoleServer, DefaultLimits())
	go func() {
		_ = client.WriteMessage(OpcodeBinary, []byte("one"))
		_ = p.c.CloseWrite()
	}()
	msg, err := server.ReadMessage()
	if err != nil {
		t.Fatal(err)
	}
	if string(msg.Payload) != "one" {
		t.Fatalf("got %q", msg.Payload)
	}
}

func TestUnexpectedContinuation(t *testing.T) {
	p := newPipe()
	defer p.c.Close()
	defer p.s.Close()
	client := NewConn(p.c, RoleClient, DefaultLimits())
	server := NewConn(p.s, RoleServer, DefaultLimits())
	errc := make(chan error, 1)
	go func() {
		_, err := server.ReadMessage()
		errc <- err
	}()
	_ = client.writeFrame(Frame{Fin: true, Opcode: OpcodeContinuation, Payload: []byte("x")})
	select {
	case err := <-errc:
		if err != ErrContinuation {
			t.Fatalf("got %v", err)
		}
	case <-time.After(time.Second):
		t.Fatal("timeout")
	}
}
