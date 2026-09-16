package redact

import (
	"net/url"
	"regexp"
	"strings"
)

var (
	authKeyRe = regexp.MustCompile(`(?i)tskey-[A-Za-z0-9_-]+`)
	hexKeyRe  = regexp.MustCompile(`\b[0-9a-fA-F]{32,}\b`)
	urlRe     = regexp.MustCompile(`https?://[^\s"']+`)
)

func String(s string) string {
	s = urlRe.ReplaceAllStringFunc(s, redactURL)
	s = authKeyRe.ReplaceAllString(s, "tskey-[redacted]")
	s = hexKeyRe.ReplaceAllString(s, "[redacted-hex]")
	return s
}

func AuthURLHost(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return "[invalid-auth-url]"
	}
	return u.Scheme + "://" + u.Host
}

func redactURL(raw string) string {
	u, err := url.Parse(raw)
	if err != nil || u.Host == "" {
		return "[redacted-url]"
	}
	host := strings.ToLower(u.Host)
	if strings.Contains(host, "tailscale.com") || strings.Contains(host, "ts.net") {
		return u.Scheme + "://" + u.Host + "/[redacted]"
	}
	return u.Scheme + "://" + u.Host + "/[redacted]"
}

func ContainsSecret(s string) bool {
	ls := strings.ToLower(s)
	if strings.Contains(ls, "tskey-") && !strings.Contains(ls, "tskey-[redacted]") {
		return true
	}
	if strings.Contains(ls, "login.tailscale.com/a/") {
		rest := ls[strings.Index(ls, "login.tailscale.com/a/")+len("login.tailscale.com/a/"):]
		if len(rest) > 0 && rest[0] != '[' {
			return true
		}
	}
	return false
}
