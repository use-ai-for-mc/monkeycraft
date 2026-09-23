package convert

import (
	"bytes"
	"net"
	"testing"
)

func TestTranslateFlags(t *testing.T) {
	got := TranslateFlags(iffUp | iffBroadcast | iffMulticast | iffRunning)
	if got&net.FlagUp == 0 || got&net.FlagBroadcast == 0 || got&net.FlagMulticast == 0 || got&net.FlagRunning == 0 {
		t.Fatalf("missing flags: %v", got)
	}
	if got&net.FlagLoopback != 0 || got&net.FlagPointToPoint != 0 {
		t.Fatalf("unexpected flags: %v", got)
	}
	if TranslateFlags(iffUp|iffLoopback)&net.FlagLoopback == 0 {
		t.Fatal("loopback not set")
	}
	if TranslateFlags(iffPointToPoint)&net.FlagPointToPoint == 0 {
		t.Fatal("point-to-point not set")
	}
}

func TestCountLeadingOnes(t *testing.T) {
	cases := []struct {
		mask []byte
		want int
	}{
		{[]byte{0xff, 0xff, 0xff, 0x00}, 24},
		{[]byte{0xff, 0xff, 0xff, 0xff}, 32},
		{[]byte{0xff, 0xff, 0x00, 0x00}, 16},
		{[]byte{0xff, 0x00, 0x00, 0x00}, 8},
		{[]byte{0x00, 0x00, 0x00, 0x00}, 0},
		{[]byte{0xff, 0xff, 0xff, 0x80}, 25},
		{bytes.Repeat([]byte{0xff}, 16), 128},
	}
	for _, c := range cases {
		if got := CountLeadingOnes(c.mask); got != c.want {
			t.Fatalf("mask %v: got %d want %d", c.mask, got, c.want)
		}
	}
}

func TestIPNetFrom(t *testing.T) {
	n := IPNetFrom([]byte{192, 168, 1, 10}, 24, 32)
	if n.IP.String() != "192.168.1.10" {
		t.Fatalf("ip %s", n.IP)
	}
	ones, bits := n.Mask.Size()
	if ones != 24 || bits != 32 {
		t.Fatalf("mask %d/%d", ones, bits)
	}
}
