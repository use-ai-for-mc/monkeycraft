package wsframe

import (
	"bufio"
	"crypto/rand"
	"crypto/sha1"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"net"
	"net/http"
	"net/url"
	"strings"
)

const wsMagic = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"

var (
	ErrHandshake = errors.New("wsframe: handshake failed")
)

func AcceptKey(clientKey string) string {
	h := sha1.Sum([]byte(clientKey + wsMagic))
	return base64.StdEncoding.EncodeToString(h[:])
}

func GenerateClientKey() (string, error) {
	var b [16]byte
	if _, err := rand.Read(b[:]); err != nil {
		return "", err
	}
	return base64.StdEncoding.EncodeToString(b[:]), nil
}

func ClientHandshake(c net.Conn, u *url.URL, extra http.Header) error {
	key, err := GenerateClientKey()
	if err != nil {
		return err
	}
	host := u.Host
	path := u.RequestURI()
	if path == "" {
		path = "/"
	}
	var b strings.Builder
	fmt.Fprintf(&b, "GET %s HTTP/1.1\r\n", path)
	fmt.Fprintf(&b, "Host: %s\r\n", host)
	b.WriteString("Upgrade: websocket\r\n")
	b.WriteString("Connection: Upgrade\r\n")
	fmt.Fprintf(&b, "Sec-WebSocket-Key: %s\r\n", key)
	b.WriteString("Sec-WebSocket-Version: 13\r\n")
	for k, vs := range extra {
		for _, v := range vs {
			fmt.Fprintf(&b, "%s: %s\r\n", k, v)
		}
	}
	b.WriteString("\r\n")
	if _, err := io.WriteString(c, b.String()); err != nil {
		return err
	}
	br := bufio.NewReader(c)
	resp, err := http.ReadResponse(br, nil)
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode != 101 {
		return fmt.Errorf("%w: status %d", ErrHandshake, resp.StatusCode)
	}
	if !strings.EqualFold(resp.Header.Get("Upgrade"), "websocket") {
		return fmt.Errorf("%w: upgrade", ErrHandshake)
	}
	if AcceptKey(key) != resp.Header.Get("Sec-WebSocket-Accept") {
		return fmt.Errorf("%w: accept key", ErrHandshake)
	}
	if br.Buffered() > 0 {
		return fmt.Errorf("%w: unexpected buffered data after handshake", ErrHandshake)
	}
	return nil
}

func ServerHandshake(c net.Conn) error {
	br := bufio.NewReader(c)
	req, err := http.ReadRequest(br)
	if err != nil {
		return err
	}
	key := req.Header.Get("Sec-WebSocket-Key")
	if key == "" || !strings.EqualFold(req.Header.Get("Upgrade"), "websocket") {
		return ErrHandshake
	}
	accept := AcceptKey(key)
	resp := "HTTP/1.1 101 Switching Protocols\r\n" +
		"Upgrade: websocket\r\n" +
		"Connection: Upgrade\r\n" +
		"Sec-WebSocket-Accept: " + accept + "\r\n\r\n"
	_, err = io.WriteString(c, resp)
	return err
}
