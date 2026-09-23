package rpcschema

import (
	"strings"
	"testing"
)

func TestParseReq(t *testing.T) {
	raw := []byte(`{"protocolVersion":1,"kind":"req","id":"1","method":"dialTcp","payload":{"host":"100.64.0.1","port":9600}}`)
	e, err := Parse(raw)
	if err != nil {
		t.Fatal(err)
	}
	if e.Method != "dialTcp" {
		t.Fatalf("%s", e.Method)
	}
}

func TestRejectUnknownMethod(t *testing.T) {
	raw := []byte(`{"protocolVersion":1,"kind":"req","id":"1","method":"socks"}`)
	if _, err := Parse(raw); err != ErrBadMethod {
		t.Fatalf("got %v", err)
	}
}

func TestRejectVersion(t *testing.T) {
	raw := []byte(`{"protocolVersion":2,"kind":"req","id":"1","method":"hello"}`)
	if _, err := Parse(raw); err != ErrBadVersion {
		t.Fatalf("got %v", err)
	}
}

func TestRejectMissingID(t *testing.T) {
	raw := []byte(`{"protocolVersion":1,"kind":"req","method":"hello"}`)
	if _, err := Parse(raw); err != ErrBadID {
		t.Fatalf("got %v", err)
	}
}

func TestTooLarge(t *testing.T) {
	raw := []byte(`{"protocolVersion":1,"kind":"evt","eventId":1,"payload":"` + strings.Repeat("a", MaxJSONBytes) + `"}`)
	if _, err := Parse(raw); err != ErrTooLarge {
		t.Fatalf("got %v", err)
	}
}

func TestDialValidation(t *testing.T) {
	if err := ValidateDial(DialTcpPayload{Host: "100.64.0.1", Port: 9600}); err != nil {
		t.Fatal(err)
	}
	if err := ValidateDial(DialTcpPayload{Host: "", Port: 9600}); err != ErrBadDial {
		t.Fatalf("got %v", err)
	}
	if err := ValidateDial(DialTcpPayload{Host: "h", Port: 0}); err != ErrBadDial {
		t.Fatalf("got %v", err)
	}
}

func TestErrorCodeUnknown(t *testing.T) {
	raw := []byte(`{"protocolVersion":1,"kind":"res","id":"1","ok":false,"error":{"code":"HACK","message":"x"}}`)
	if _, err := Parse(raw); err != ErrBadError {
		t.Fatalf("got %v", err)
	}
}
