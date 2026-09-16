package redact

import (
	"strings"
	"testing"
)

func TestRedactAuthURL(t *testing.T) {
	in := "open https://login.tailscale.com/a/supersecret token"
	out := String(in)
	if strings.Contains(out, "supersecret") {
		t.Fatalf("leaked: %s", out)
	}
	if strings.Contains(out, "/a/") {
		t.Fatalf("path leaked: %s", out)
	}
	if !strings.Contains(out, "login.tailscale.com") {
		t.Fatalf("host should remain: %s", out)
	}
}

func TestRedactAuthKey(t *testing.T) {
	out := String("using tskey-auth-abcDEF123")
	if strings.Contains(out, "abcDEF123") {
		t.Fatalf("leaked: %s", out)
	}
}

func TestAuthURLHost(t *testing.T) {
	if got := AuthURLHost("https://login.tailscale.com/a/secret"); got != "https://login.tailscale.com" {
		t.Fatalf("got %s", got)
	}
}

func TestContainsSecret(t *testing.T) {
	if !ContainsSecret("tskey-auth-xxx") {
		t.Fatal("expected secret")
	}
	if ContainsSecret("helper started") {
		t.Fatal("false positive")
	}
}
