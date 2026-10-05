package main

import (
	"context"
	"encoding/json"
	"golang.org/x/net/http2"
	"io"
	"log"
	"net/http"
	"net/http/httptest"
	"os"
	"os/exec"
	"tailscale.com/control/controlhttp/controlhttpserver"
	"tailscale.com/tailcfg"
	"tailscale.com/tstest/integration/testcontrol"
	"tailscale.com/types/key"
)

func main() {
	control := &testcontrol.Server{}
	control.HTTPTestServer = httptest.NewServer(control)
	defer control.HTTPTestServer.Close()
	// Real control test first; separate authenticated echo fixture exercises framing and HTTP/2 flow control.
	// The second echo check uses an authenticated HTTP2 test endpoint on this wrapper.
	sk := key.NewMachine()
	mux := http.NewServeMux()
	mux.HandleFunc("/key", func(w http.ResponseWriter, r *http.Request) {
		json.NewEncoder(w).Encode(tailcfg.OverTLSPublicKeyResponse{PublicKey: sk.Public()})
	})
	mux.HandleFunc("/ts2021", func(w http.ResponseWriter, r *http.Request) {
		c, e := controlhttpserver.AcceptHTTP(context.Background(), w, r, sk, nil)
		if e != nil {
			log.Print(e)
			return
		}
		defer c.Close()
		var h http2.Server
		h.ServeConn(c, &http2.ServeConnOpts{BaseConfig: &http.Server{Handler: http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/lab/echo" {
				w.Header().Set("Content-Type", "application/json")
				io.Copy(w, r.Body)
				return
			}
			if r.URL.Path == "/machine/register" {
				io.WriteString(w, `{"MachineAuthorized":true}`)
				return
			}
			if r.URL.Path == "/machine/map" {
				b := []byte(`{"Node":{"ID":1}}`)
				w.Write([]byte{byte(len(b)), 0, 0, 0})
				w.Write(b)
				return
			}
			w.WriteHeader(404)
		})}})
	})
	echo := httptest.NewServer(mux)
	defer echo.Close()
	real := exec.Command(os.Args[1], "-cp", os.Args[2], "com.monkeycraft.tailscale.ControlProbe", control.HTTPTestServer.URL)
	real.Stdout = os.Stdout
	real.Stderr = os.Stderr
	if e := real.Run(); e != nil {
		log.Fatal(e)
	}
	cmd := exec.Command(os.Args[1], "-cp", os.Args[2], "com.monkeycraft.tailscale.ControlProbe", echo.URL, "echo")
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	if e := cmd.Run(); e != nil {
		log.Fatal(e)
	}
}
