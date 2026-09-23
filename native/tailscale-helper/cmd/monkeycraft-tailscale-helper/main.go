package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/backend"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/engine"
	"github.com/use-ai-for-mc/monkeycraft/native/tailscale-helper/internal/version"
)

func main() {
	showVersion := flag.Bool("version", false, "print helper version and exit")
	fake := flag.Bool("fake", false, "use in-process fake backend (tests only)")
	flag.Parse()
	if *showVersion {
		fmt.Fprintf(os.Stdout, "monkeycraft-tailscale-helper %s protocol=%d tailscale=%s commit=%s\n",
			version.Version, version.Protocol, version.Tailscale, version.GitCommit)
		os.Exit(0)
	}
	factory := backend.DefaultFactory()
	if *fake {
		factory = func() backend.Backend { return backend.NewFake() }
	}
	os.Exit(engine.New(os.Stdin, os.Stdout, os.Stderr, factory).Run())
}
