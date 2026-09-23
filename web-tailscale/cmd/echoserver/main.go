package main

import (
	"flag"
	"io"
	"log"
	"net"
	"os"
	"os/signal"
	"syscall"

	"monkeycraft.dev/web-tailscale/internal/wsframe"
)

func main() {
	addr := flag.String("addr", "127.0.0.1:19600", "listen address")
	mode := flag.String("mode", "ws", "tcp or ws")
	flag.Parse()
	ln, err := net.Listen("tcp", *addr)
	if err != nil {
		log.Fatal(err)
	}
	log.Printf("echo %s listening on %s", *mode, ln.Addr())
	go func() {
		c := make(chan os.Signal, 1)
		signal.Notify(c, syscall.SIGINT, syscall.SIGTERM)
		<-c
		ln.Close()
	}()
	for {
		c, err := ln.Accept()
		if err != nil {
			return
		}
		go handle(c, *mode)
	}
}

func handle(c net.Conn, mode string) {
	defer c.Close()
	if mode == "tcp" {
		_, _ = io.Copy(c, c)
		return
	}
	if err := wsframe.ServerHandshake(c); err != nil {
		return
	}
	conn := wsframe.NewConn(c, wsframe.RoleServer, wsframe.DefaultLimits())
	for {
		msg, err := conn.ReadMessage()
		if err != nil {
			return
		}
		if msg.Opcode == wsframe.OpcodeClose {
			return
		}
		if err := conn.WriteMessage(msg.Opcode, msg.Payload); err != nil {
			return
		}
	}
}
