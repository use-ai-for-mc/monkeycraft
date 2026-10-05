//go:build integration

package javatest

import (
	"bytes"
	"context"
	"fmt"
	"io"
	"net"
	"testing"
	"time"

	"tailscale.com/tsnet"
)

func verifyStreams(t *testing.T, ctx context.Context, peer *tsnet.Server, ip string) {
	t.Helper()
	const workers, size = 4, 2 * 1024 * 1024
	results := make(chan error, workers)
	for worker := 0; worker < workers; worker++ {
		go func(worker int) {
			results <- func() error {
				c, err := peer.Dial(ctx, "tcp", net.JoinHostPort(ip, "9600"))
				if err != nil {
					return err
				}
				defer c.Close()
				c.SetDeadline(time.Now().Add(40 * time.Second))
				half, ok := c.(interface{ CloseWrite() error })
				if !ok {
					return fmt.Errorf("test peer cannot half-close")
				}
				want := make([]byte, size)
				for i := range want {
					want[i] = byte(i*73 + worker*19 + (i >> 8))
				}
				written := make(chan error, 1)
				go func() {
					_, err := io.Copy(c, bytes.NewReader(want))
					if err == nil {
						err = half.CloseWrite()
					}
					written <- err
				}()
				time.Sleep(500 * time.Millisecond)
				got := make([]byte, len(want))
				for offset := 0; offset < len(got); {
					end := min(offset+4096, len(got))
					n, err := io.ReadFull(c, got[offset:end])
					offset += n
					if err != nil {
						return fmt.Errorf("stream %d stopped at %d/%d: %w", worker, offset, len(got), err)
					}
					time.Sleep(time.Millisecond)
				}
				if err := <-written; err != nil {
					return fmt.Errorf("stream %d write: %w", worker, err)
				}
				if !bytes.Equal(got, want) {
					return fmt.Errorf("stream %d corrupted", worker)
				}
				var extra [1]byte
				if n, err := c.Read(extra[:]); n != 0 || err != io.EOF {
					return fmt.Errorf("stream %d missing clean EOF: %d %v", worker, n, err)
				}
				return nil
			}()
		}(worker)
	}
	for worker := 0; worker < workers; worker++ {
		if err := <-results; err != nil {
			t.Error(err)
		}
	}
	if t.Failed() {
		t.FailNow()
	}
	t.Logf("STREAMS_OK %d concurrent streams x %d bytes, delayed/slow readers, half-close and EOF", workers, size)
}
