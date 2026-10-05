// Copyright (c) Tailscale Inc & contributors
// SPDX-License-Identifier: BSD-3-Clause
// Extracted unchanged from v1.102.3 tstest/integration/integration.go to avoid
// that package's unconditional tailscaled feature imports in reduced test builds.
//go:build integration

package labnet

import (
	"crypto/tls"
	"net"
	"net/http"
	"net/http/httptest"
	"tailscale.com/derp/derpserver"
	"tailscale.com/net/stun/stuntest"
	"tailscale.com/tailcfg"
	"tailscale.com/types/key"
	"tailscale.com/types/logger"
	"tailscale.com/types/nettype"
	"testing"
)

// RunDERPAndSTUN runs a local DERP and STUN server for tests, returning the derpMap
// that clients should use. This creates resources that must be cleaned up with the
// returned cleanup function.
func RunDERPAndSTUN(t testing.TB, logf logger.Logf, ipAddress string) *tailcfg.DERPMap {
	m, _ := RunDERPAndSTUNWithCertificate(t, logf, ipAddress)
	return m
}
func RunDERPAndSTUNWithCertificate(t testing.TB, logf logger.Logf, ipAddress string) (derpMap *tailcfg.DERPMap, certificate []byte) {
	t.Helper()

	d := derpserver.New(key.NewNode(), logf)

	ln, err := net.Listen("tcp", net.JoinHostPort(ipAddress, "0"))
	if err != nil {
		t.Fatal(err)
	}

	// Wrap with WebSocket support so browser-WASM (cmd/tsconnect) clients,
	// which can only reach DERP via WebSocket, can use this same server.
	handler := derpserver.AddWebSocketSupport(d, derpserver.Handler(d))
	httpsrv := httptest.NewUnstartedServer(handler)
	httpsrv.Listener.Close()
	httpsrv.Listener = ln
	httpsrv.Config.ErrorLog = logger.StdLogger(logf)
	httpsrv.Config.TLSNextProto = make(map[string]func(*http.Server, *tls.Conn, http.Handler))
	httpsrv.StartTLS()

	stunAddr, stunCleanup := stuntest.ServeWithPacketListener(t, nettype.Std{})

	m := &tailcfg.DERPMap{
		Regions: map[int]*tailcfg.DERPRegion{
			1: {
				RegionID:   1,
				RegionCode: "test",
				Nodes: []*tailcfg.DERPNode{
					{
						Name:             "t1",
						RegionID:         1,
						HostName:         ipAddress,
						IPv4:             ipAddress,
						IPv6:             "none",
						STUNPort:         stunAddr.Port,
						DERPPort:         httpsrv.Listener.Addr().(*net.TCPAddr).Port,
						InsecureForTests: true,
						STUNTestIP:       ipAddress,
					},
				},
			},
		},
	}

	t.Logf("DERP httpsrv listener: %v", httpsrv.Listener.Addr())

	t.Cleanup(func() {
		httpsrv.CloseClientConnections()
		httpsrv.Close()
		d.Close()
		stunCleanup()
		ln.Close()
	})

	return m, httpsrv.Certificate().Raw
}
