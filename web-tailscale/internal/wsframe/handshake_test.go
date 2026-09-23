package wsframe

import (
	"net"
	"net/url"
	"testing"
)

func TestHandshakeEcho(t *testing.T) {
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
		if err := ServerHandshake(c); err != nil {
			errc <- err
			return
		}
		srv := NewConn(c, RoleServer, DefaultLimits())
		msg, err := srv.ReadMessage()
		if err != nil {
			errc <- err
			return
		}
		errc <- srv.WriteMessage(msg.Opcode, append([]byte("echo:"), msg.Payload...))
	}()

	raw, err := net.Dial("tcp", ln.Addr().String())
	if err != nil {
		t.Fatal(err)
	}
	defer raw.Close()
	u, _ := url.Parse("ws://127.0.0.1/echo")
	if err := ClientHandshake(raw, u, nil); err != nil {
		t.Fatal(err)
	}
	cli := NewConn(raw, RoleClient, DefaultLimits())
	if err := cli.WriteMessage(OpcodeText, []byte("hi")); err != nil {
		t.Fatal(err)
	}
	msg, err := cli.ReadMessage()
	if err != nil {
		t.Fatal(err)
	}
	if string(msg.Payload) != "echo:hi" {
		t.Fatalf("got %q", msg.Payload)
	}
	if err := <-errc; err != nil {
		t.Fatal(err)
	}
}

func TestAcceptKeyRFC(t *testing.T) {
	got := AcceptKey("dGhlIHNhbXBsZSBub25jZQ==")
	if got != "s3pPLMBiTxaQ9kYGzzhZRbK+xOo=" {
		t.Fatalf("got %s", got)
	}
}
