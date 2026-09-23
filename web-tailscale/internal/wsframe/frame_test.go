package wsframe

import (
	"bytes"
	"encoding/hex"
	"io"
	"strings"
	"testing"
)

func TestWriteReadRoundTrip(t *testing.T) {
	payload := []byte("hello monkeycraft")
	var buf bytes.Buffer
	f := Frame{Fin: true, Opcode: OpcodeBinary, Masked: true, MaskKey: [4]byte{1, 2, 3, 4}, Payload: payload}
	if err := WriteFrame(&buf, f); err != nil {
		t.Fatal(err)
	}
	got, err := ReadFrame(&buf, DefaultLimits(), true)
	if err != nil {
		t.Fatal(err)
	}
	if !got.Fin || got.Opcode != OpcodeBinary {
		t.Fatalf("hdr %+v", got)
	}
	if !bytes.Equal(got.Payload, payload) {
		t.Fatalf("payload %q", got.Payload)
	}
}

func TestClientMaskingApplied(t *testing.T) {
	var buf bytes.Buffer
	f := Frame{Fin: true, Opcode: OpcodeText, Masked: true, MaskKey: [4]byte{0xaa, 0xbb, 0xcc, 0xdd}, Payload: []byte("ab")}
	if err := WriteFrame(&buf, f); err != nil {
		t.Fatal(err)
	}
	raw := buf.Bytes()
	if raw[1]&0x80 == 0 {
		t.Fatal("mask bit not set")
	}
	if raw[6] == 'a' {
		t.Fatal("payload was not masked on the wire")
	}
}

func TestUnmaskedClientRejected(t *testing.T) {
	var buf bytes.Buffer
	_ = WriteFrame(&buf, Frame{Fin: true, Opcode: OpcodeText, Payload: []byte("x")})
	_, err := ReadFrame(&buf, DefaultLimits(), true)
	if err != ErrUnmaskedClient {
		t.Fatalf("got %v", err)
	}
}

func TestMaskedServerRejected(t *testing.T) {
	var buf bytes.Buffer
	_ = WriteFrame(&buf, Frame{Fin: true, Opcode: OpcodeText, Masked: true, MaskKey: [4]byte{1, 2, 3, 4}, Payload: []byte("x")})
	_, err := ReadFrame(&buf, DefaultLimits(), false)
	if err != ErrMaskedServerFrame {
		t.Fatalf("got %v", err)
	}
}

func TestReservedBits(t *testing.T) {
	raw, _ := hex.DecodeString("c18100")
	_, err := ReadFrame(bytes.NewReader(raw), DefaultLimits(), false)
	if err != ErrReservedBits {
		t.Fatalf("got %v", err)
	}
}

func TestBadOpcode(t *testing.T) {
	raw := []byte{0x83, 0x00}
	_, err := ReadFrame(bytes.NewReader(raw), DefaultLimits(), false)
	if err != ErrBadOpcode {
		t.Fatalf("got %v", err)
	}
}

func TestControlFragmentRejected(t *testing.T) {
	err := WriteFrame(io.Discard, Frame{Fin: false, Opcode: OpcodePing, Payload: []byte("x")})
	if err != ErrControlFragment {
		t.Fatalf("got %v", err)
	}
}

func TestControlTooLong(t *testing.T) {
	err := WriteFrame(io.Discard, Frame{Fin: true, Opcode: OpcodePing, Payload: bytes.Repeat([]byte("a"), 126)})
	if err != ErrControlTooLong {
		t.Fatalf("got %v", err)
	}
}

func TestLengthLimit(t *testing.T) {
	var buf bytes.Buffer
	payload := bytes.Repeat([]byte("z"), 200)
	_ = WriteFrame(&buf, Frame{Fin: true, Opcode: OpcodeBinary, Payload: payload})
	_, err := ReadFrame(&buf, Limits{MaxFrameBytes: 50, MaxMessageBytes: 50}, false)
	if err != ErrMessageTooBig {
		t.Fatalf("got %v", err)
	}
}

func TestNonMinimalLength(t *testing.T) {
	raw := []byte{0x82, 126, 0x00, 0x01, 0x00}
	_, err := ReadFrame(bytes.NewReader(raw), DefaultLimits(), false)
	if err == nil || !strings.Contains(err.Error(), "non-minimal") {
		t.Fatalf("got %v", err)
	}
}

func TestClosePayload(t *testing.T) {
	p := EncodeClosePayload(CloseNormalClosure, "bye")
	code, reason, err := ParseClosePayload(p)
	if err != nil || code != CloseNormalClosure || reason != "bye" {
		t.Fatalf("%d %q %v", code, reason, err)
	}
	if _, _, err := ParseClosePayload([]byte{0x03}); err != ErrProtocol {
		t.Fatalf("got %v", err)
	}
	if _, _, err := ParseClosePayload([]byte{0x03, 0xec}); err != ErrBadCloseCode {
		t.Fatalf("got %v", err)
	}
}

func TestRFC6455HelloUnmasked(t *testing.T) {
	raw, _ := hex.DecodeString("810548656c6c6f")
	f, err := ReadFrame(bytes.NewReader(raw), DefaultLimits(), false)
	if err != nil {
		t.Fatal(err)
	}
	if string(f.Payload) != "Hello" || f.Opcode != OpcodeText {
		t.Fatalf("%+v", f)
	}
}
