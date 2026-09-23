package redact

import (
	"strings"
	"testing"
)

func TestRedactsAuthURLAndKeys(t *testing.T) {
	in := "browse https://login.tailscale.com/a/abcdef?k=1 tskey-auth-SECRET nodekey:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
	out := String(in)
	if strings.Contains(out, "abcdef") || strings.Contains(out, "SECRET") || strings.Contains(out, "0123456789") {
		t.Fatalf("leaked: %s", out)
	}
	if !strings.Contains(out, "[redacted]") {
		t.Fatalf("expected redaction: %s", out)
	}
}

func TestTruncatesError(t *testing.T) {
	err := &strErr{strings.Repeat("x", 500)}
	if len(ErrorMessage(err)) > 200 {
		t.Fatal("not truncated")
	}
}

type strErr struct{ s string }

func (e *strErr) Error() string { return e.s }
