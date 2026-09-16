package protocol

import (
	"bytes"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestDecodeEncodeRoundTrip(t *testing.T) {
	in := &Message{
		ProtocolVersion: 1,
		SessionNonce:    "nonce-1",
		RequestID:       "1",
		Command:         CmdStart,
		Target:          "127.0.0.1:9600",
		ListenPort:      9600,
		StateDir:        "/tmp/state",
	}
	line, err := EncodeLine(in)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.HasSuffix(line, []byte("\n")) {
		t.Fatal("missing newline")
	}
	out, err := DecodeLine(bytes.TrimRight(line, "\n"))
	if err != nil {
		t.Fatal(err)
	}
	if out.Command != CmdStart || out.Target != in.Target || out.ListenPort != 9600 {
		t.Fatalf("round trip mismatch: %+v", out)
	}
}

func TestDecodeRejectsUnknownFields(t *testing.T) {
	_, err := DecodeLine([]byte(`{"protocolVersion":1,"socks":true}`))
	if err == nil {
		t.Fatal("expected unknown field error")
	}
}

func TestDecodeRejectsNonJSON(t *testing.T) {
	_, err := DecodeLine([]byte("To start this tsnet server go to https://login.tailscale.com/a/secret"))
	if err == nil {
		t.Fatal("expected non-json error")
	}
}

func TestDecodeRejectsTooLong(t *testing.T) {
	line := bytes.Repeat([]byte("a"), MaxLineBytes+1)
	_, err := DecodeLine(line)
	if err != ErrLineTooLong {
		t.Fatalf("got %v", err)
	}
}

func TestValidateTarget(t *testing.T) {
	ok := []string{"127.0.0.1:9600", "127.0.0.1:1", "127.0.0.1:65535"}
	for _, s := range ok {
		if err := ValidateTarget(s); err != nil {
			t.Fatalf("%s: %v", s, err)
		}
	}
	bad := []string{"", "10.0.0.1:9600", "localhost:9600", "127.0.0.1", "127.0.0.1:0", "127.0.0.1:99999", "[::1]:9600", "127.0.0.1:9600/foo"}
	for _, s := range bad {
		if err := ValidateTarget(s); err == nil {
			t.Fatalf("expected error for %s", s)
		}
	}
}

func TestValidateCommand(t *testing.T) {
	code, _ := ValidateCommand(&Message{ProtocolVersion: 2, Command: CmdStatus, RequestID: "1"})
	if code != ErrProtocolVersionUnsupported {
		t.Fatalf("got %s", code)
	}
	code, _ = ValidateCommand(&Message{ProtocolVersion: 1, Command: "funnel", RequestID: "1"})
	if code != ErrUnknownCommand {
		t.Fatalf("got %s", code)
	}
	code, _ = ValidateCommand(&Message{ProtocolVersion: 1, Command: CmdStart, RequestID: "1", Target: "10.0.0.1:80", ListenPort: 9600, StateDir: "x"})
	if code != ErrInvalidTarget {
		t.Fatalf("got %s", code)
	}
	code, _ = ValidateCommand(&Message{ProtocolVersion: 1, Command: CmdStart, RequestID: "1", Target: "127.0.0.1:9600", ListenPort: 9600, StateDir: "/tmp/x"})
	if code != "" {
		t.Fatalf("got %s", code)
	}
}

func TestGoldenVectors(t *testing.T) {
	dir := filepath.Join("testdata", "golden")
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	for _, e := range entries {
		if e.IsDir() || !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		raw, err := os.ReadFile(filepath.Join(dir, e.Name()))
		if err != nil {
			t.Fatal(err)
		}
		name := e.Name()
		t.Run(name, func(t *testing.T) {
			msg, err := DecodeLine(bytes.TrimSpace(raw))
			wantFail := strings.Contains(name, "invalid")
			if wantFail {
				if err == nil {
					if code, _ := ValidateCommand(msg); code == "" {
						t.Fatal("expected invalid golden to fail")
					}
				}
				return
			}
			if err != nil {
				t.Fatal(err)
			}
			if msg.Command != "" {
				if code, detail := ValidateCommand(msg); code != "" {
					t.Fatalf("validate: %s %s", code, detail)
				}
			}
		})
	}
}
