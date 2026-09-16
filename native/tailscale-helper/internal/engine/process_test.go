package engine_test

import (
	"bufio"
	"encoding/json"
	"io"
	"os"
	"os/exec"
	"path/filepath"
	"runtime"
	"testing"
	"time"
)

func TestHelperProcessProtocol(t *testing.T) {
	if testing.Short() {
		t.Skip("skipping process integration in short mode")
	}
	bin := buildHelper(t)
	cmd := exec.Command(bin, "-fake")
	stdin, err := cmd.StdinPipe()
	if err != nil {
		t.Fatal(err)
	}
	stdout, err := cmd.StdoutPipe()
	if err != nil {
		t.Fatal(err)
	}
	stderr, err := cmd.StderrPipe()
	if err != nil {
		t.Fatal(err)
	}
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	defer func() {
		_ = stdin.Close()
		_ = cmd.Process.Kill()
		_, _ = cmd.Process.Wait()
	}()
	go func() { _, _ = io.Copy(io.Discard, stderr) }()

	write := func(m map[string]any) {
		t.Helper()
		b, err := json.Marshal(m)
		if err != nil {
			t.Fatal(err)
		}
		if _, err := stdin.Write(append(b, '\n')); err != nil {
			t.Fatal(err)
		}
	}
	scan := bufio.NewScanner(stdout)
	read := func() map[string]any {
		t.Helper()
		ch := make(chan map[string]any, 1)
		go func() {
			if !scan.Scan() {
				ch <- nil
				return
			}
			var m map[string]any
			if err := json.Unmarshal(scan.Bytes(), &m); err != nil {
				ch <- map[string]any{"decodeError": err.Error(), "raw": scan.Text()}
				return
			}
			ch <- m
		}()
		select {
		case m := <-ch:
			if m == nil {
				t.Fatal("eof")
			}
			return m
		case <-time.After(3 * time.Second):
			t.Fatal("timeout")
		}
		return nil
	}

	write(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "proc",
		"requestId":       "1",
		"command":         "status",
	})
	ready := read()
	if ready["event"] != "ready" {
		t.Fatalf("first event %+v", ready)
	}
	if ready["protocolVersion"].(float64) != 1 {
		t.Fatalf("protocol %+v", ready)
	}
	write(map[string]any{
		"protocolVersion": 1,
		"sessionNonce":    "proc",
		"requestId":       "2",
		"command":         "shutdown",
	})
	deadline := time.Now().Add(3 * time.Second)
	for time.Now().Before(deadline) {
		m := read()
		if m["event"] == "stopped" {
			break
		}
	}
	done := make(chan error, 1)
	go func() { done <- cmd.Wait() }()
	select {
	case err := <-done:
		if err != nil {
			t.Fatalf("wait: %v", err)
		}
	case <-time.After(3 * time.Second):
		t.Fatal("helper did not exit after shutdown")
	}
}

func TestHelperVersionFlag(t *testing.T) {
	if testing.Short() {
		t.Skip()
	}
	bin := buildHelper(t)
	out, err := exec.Command(bin, "-version").CombinedOutput()
	if err != nil {
		t.Fatal(err)
	}
	if len(out) == 0 {
		t.Fatal("empty version")
	}
}

func buildHelper(t *testing.T) string {
	t.Helper()
	dir := t.TempDir()
	name := "monkeycraft-tailscale-helper"
	if runtime.GOOS == "windows" {
		name += ".exe"
	}
	out := filepath.Join(dir, name)
	cmd := exec.Command("go", "build", "-o", out, "./cmd/monkeycraft-tailscale-helper")
	cmd.Dir = moduleRoot(t)
	cmd.Env = append(os.Environ(), "CGO_ENABLED=0")
	b, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("build helper: %v\n%s", err, b)
	}
	return out
}

func moduleRoot(t *testing.T) string {
	t.Helper()
	_, file, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("caller")
	}
	return filepath.Clean(filepath.Join(filepath.Dir(file), "../.."))
}
