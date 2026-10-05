package main

import (
	"bufio"
	"bytes"
	"context"
	"fmt"
	"github.com/tailscale/wireguard-go/conn"
	"github.com/tailscale/wireguard-go/device"
	"tailscale-java-lab/internal/wgnetstack"
	"io"
	"net/netip"
	"os"
	"os/exec"
	"strconv"
	"strings"
	"tailscale.com/types/key"
	"time"
)

func must(e error) {
	if e != nil {
		panic(e)
	}
}
func main() {
	ctx, cancel := context.WithTimeout(context.Background(), 25*time.Second)
	defer cancel()
	secret := key.NewNode()
	tun, network, e := netstack.CreateNetTUN([]netip.Addr{netip.MustParseAddr("100.64.0.1")}, nil, 1280)
	must(e)
	dev := device.NewDevice(tun, conn.NewDefaultBind(), device.NewLogger(device.LogLevelError, "go-peer: "))
	defer dev.Close()
	must(dev.IpcSet("private_key=" + secret.UntypedHexString() + "\nlisten_port=0\n"))
	must(dev.Up())
	cfg, e := dev.IpcGet()
	must(e)
	port := ""
	for _, line := range strings.Split(cfg, "\n") {
		if strings.HasPrefix(line, "listen_port=") {
			port = strings.TrimPrefix(line, "listen_port=")
		}
	}
	args := []string{"-cp", os.Args[2], "com.monkeycraft.tailscale.WireGuardProbe", secret.Public().UntypedHexString(), port}
	if len(os.Args) > 3 {
		args = append(args, "initiate")
	}
	cmd := exec.CommandContext(ctx, os.Args[1], args...)
	out, e := cmd.StdoutPipe()
	must(e)
	cmd.Stderr = os.Stderr
	must(cmd.Start())
	defer func() { cmd.Process.Kill(); cmd.Wait() }()
	scanner := bufio.NewScanner(out)
	if !scanner.Scan() {
		panic("no Java endpoint")
	}
	parts := strings.Fields(scanner.Text())
	if len(parts) != 2 {
		panic("bad Java endpoint")
	}
	_, e = strconv.Atoi(parts[1])
	must(e)
	must(dev.IpcSet("public_key=" + parts[0] + "\nallowed_ip=100.64.0.2/32\nendpoint=127.0.0.1:" + parts[1] + "\n"))
	c, e := network.DialContextTCPAddrPort(ctx, netip.MustParseAddrPort("100.64.0.2:9600"))
	must(e)
	defer c.Close()
	c.SetDeadline(time.Now().Add(20 * time.Second))
	want := bytes.Repeat([]byte("java-wireguard-tcp-"), 16384)
	errc := make(chan error, 1)
	go func() { _, e := c.Write(want); errc <- e }()
	got := make([]byte, len(want))
	_, e = io.ReadFull(c, got)
	must(e)
	must(<-errc)
	if !bytes.Equal(got, want) {
		panic("mismatch")
	}
	fmt.Printf("JAVA_WIREGUARD_TCP_OK bytes=%d java_initiator=%v\n", len(got), len(os.Args) > 3)
}
