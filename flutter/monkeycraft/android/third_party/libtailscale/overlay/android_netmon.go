//go:build android

package main

import (
	"context"
	"fmt"
	"net"
	"os"
	"time"
	"unsafe"

	"tailscale.com/envknob"
	"tailscale.com/net/netmon"
)

/*
#include <errno.h>
#include <ifaddrs.h>
#include <net/if.h>
#include <netinet/in.h>
#include <sys/socket.h>
*/
import "C"

func init() {
	envknob.SetNoLogsNoSupport()
	netmon.RegisterInterfaceGetter(androidSafeInterfaces)
}

//export MonkeycraftAndroidInit
func MonkeycraftAndroidInit(dataDir *C.char) C.int {
	envknob.SetNoLogsNoSupport()
	if err := os.Setenv("TS_LOGS_DIR", C.GoString(dataDir)); err != nil {
		return -1
	}
	return 0
}

//export MonkeycraftDialTimeout
func MonkeycraftDialTimeout(sd C.int, network, addr *C.char, timeoutMillis C.int, connOut *C.int) C.int {
	s := getServer(sd)
	if s == nil {
		return C.EBADF
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Duration(timeoutMillis)*time.Millisecond)
	defer cancel()
	netConn, err := s.s.Dial(ctx, C.GoString(network), C.GoString(addr))
	if err != nil {
		return s.recErr(err)
	}
	s.started = true
	if err := newConn(s, netConn, connOut); err != nil {
		netConn.Close()
		return s.recErr(err)
	}
	return 0
}

func androidSafeInterfaces() ([]netmon.Interface, error) {
	return getifaddrsInterfaces()
}

type ifaceInfo struct {
	name  string
	flags net.Flags
	addrs []net.Addr
}

func getifaddrsInterfaces() ([]netmon.Interface, error) {
	var head *C.struct_ifaddrs
	if rc, e := C.getifaddrs(&head); rc != 0 {
		return nil, fmt.Errorf("getifaddrs: %w", e)
	}
	defer C.freeifaddrs(head)

	byName := map[string]*ifaceInfo{}
	for ifa := head; ifa != nil; ifa = ifa.ifa_next {
		name := C.GoString(ifa.ifa_name)
		info := byName[name]
		if info == nil {
			info = &ifaceInfo{
				name:  name,
				flags: overlayTranslateFlags(uint32(ifa.ifa_flags)),
			}
			byName[name] = info
		}
		if addr := sockaddrToAddr(ifa.ifa_addr, ifa.ifa_netmask); addr != nil {
			info.addrs = append(info.addrs, addr)
		}
	}

	out := make([]netmon.Interface, 0, len(byName))
	for _, info := range byName {
		ni := &net.Interface{
			Name:  info.name,
			Flags: info.flags,
		}
		out = append(out, netmon.Interface{
			Interface: ni,
			AltAddrs:  info.addrs,
		})
	}
	return out, nil
}

func sockaddrToAddr(sa, nm *C.struct_sockaddr) net.Addr {
	if sa == nil {
		return nil
	}
	switch sa.sa_family {
	case C.AF_INET:
		sin := (*C.struct_sockaddr_in)(unsafe.Pointer(sa))
		ip := (*[4]byte)(unsafe.Pointer(&sin.sin_addr))[:]
		prefix := 32
		if nm != nil && nm.sa_family == C.AF_INET {
			mask := (*C.struct_sockaddr_in)(unsafe.Pointer(nm))
			prefix = overlayCountLeadingOnes((*[4]byte)(unsafe.Pointer(&mask.sin_addr))[:])
		}
		return overlayIPNetFrom(ip, prefix, 32)
	case C.AF_INET6:
		sin := (*C.struct_sockaddr_in6)(unsafe.Pointer(sa))
		ip := (*[16]byte)(unsafe.Pointer(&sin.sin6_addr))[:]
		prefix := 128
		if nm != nil && nm.sa_family == C.AF_INET6 {
			mask := (*C.struct_sockaddr_in6)(unsafe.Pointer(nm))
			prefix = overlayCountLeadingOnes((*[16]byte)(unsafe.Pointer(&mask.sin6_addr))[:])
		}
		return overlayIPNetFrom(ip, prefix, 128)
	}
	return nil
}

func overlayTranslateFlags(f uint32) net.Flags {
	var out net.Flags
	if f&C.IFF_UP != 0 {
		out |= net.FlagUp
	}
	if f&C.IFF_BROADCAST != 0 {
		out |= net.FlagBroadcast
	}
	if f&C.IFF_LOOPBACK != 0 {
		out |= net.FlagLoopback
	}
	if f&C.IFF_POINTOPOINT != 0 {
		out |= net.FlagPointToPoint
	}
	if f&C.IFF_MULTICAST != 0 {
		out |= net.FlagMulticast
	}
	if f&C.IFF_RUNNING != 0 {
		out |= net.FlagRunning
	}
	return out
}

func overlayCountLeadingOnes(mask []byte) int {
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

func overlayIPNetFrom(ip []byte, prefix, bits int) *net.IPNet {
	cp := make(net.IP, len(ip))
	copy(cp, ip)
	return &net.IPNet{IP: cp, Mask: net.CIDRMask(prefix, bits)}
}
