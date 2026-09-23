package redact

import (
	"net/url"
	"regexp"
	"strings"
)

var (
	authKeyRE = regexp.MustCompile(`(?i)tskey-[a-z0-9_-]+`)
	hexKeyRE  = regexp.MustCompile(`\b[0-9a-fA-F]{64}\b`)
	nodeKeyRE = regexp.MustCompile(`(?i)\bnodekey:[0-9a-f]+`)
	machKeyRE = regexp.MustCompile(`(?i)\bmachinekey:[0-9a-f]+`)
)

func String(s string) string {
	s = stripAuthURL(s)
	s = authKeyRE.ReplaceAllString(s, "tskey-[redacted]")
	s = nodeKeyRE.ReplaceAllString(s, "nodekey:[redacted]")
	s = machKeyRE.ReplaceAllString(s, "machinekey:[redacted]")
	s = hexKeyRE.ReplaceAllString(s, "[redacted-key]")
	return s
}

func stripAuthURL(s string) string {
	if !strings.Contains(s, "http") {
		return s
	}
	return regexp.MustCompile(`https?://[^\s]+`).ReplaceAllStringFunc(s, func(raw string) string {
		u, err := url.Parse(raw)
		if err != nil {
			return "[redacted-url]"
		}
		host := u.Host
		if strings.Contains(strings.ToLower(host), "tailscale") ||
			strings.Contains(u.Path, "login") ||
			strings.Contains(u.Path, "auth") ||
			u.RawQuery != "" {
			return u.Scheme + "://" + host + "/[redacted]"
		}
		return raw
	})
}

func ErrorMessage(err error) string {
	if err == nil {
		return ""
	}
	msg := String(err.Error())
	if len(msg) > 200 {
		return msg[:200]
	}
	return msg
}
