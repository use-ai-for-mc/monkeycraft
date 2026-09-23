package convert

import "net"

const (
	iffUp           = 1 << 0
	iffBroadcast    = 1 << 1
	iffLoopback     = 1 << 3
	iffPointToPoint = 1 << 4
	iffRunning      = 1 << 6
	iffMulticast    = 1 << 12
)

func TranslateFlags(f uint32) net.Flags {
	var out net.Flags
	if f&iffUp != 0 {
		out |= net.FlagUp
	}
	if f&iffBroadcast != 0 {
		out |= net.FlagBroadcast
	}
	if f&iffLoopback != 0 {
		out |= net.FlagLoopback
	}
	if f&iffPointToPoint != 0 {
		out |= net.FlagPointToPoint
	}
	if f&iffMulticast != 0 {
		out |= net.FlagMulticast
	}
	if f&iffRunning != 0 {
		out |= net.FlagRunning
	}
	return out
}

func CountLeadingOnes(mask []byte) int {
	ones := 0
	for _, b := range mask {
		if b == 0xff {
			ones += 8
			continue
		}
		for b&0x80 != 0 {
			ones++
			b <<= 1
		}
		break
	}
	return ones
}

func IPNetFrom(ip []byte, prefix, bits int) *net.IPNet {
	cp := make(net.IP, len(ip))
	copy(cp, ip)
	return &net.IPNet{IP: cp, Mask: net.CIDRMask(prefix, bits)}
}
