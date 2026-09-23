package main

import (
	"fmt"
	"os"
)

func main() {
	fmt.Fprintln(os.Stderr, "placeholder: wasm tags are applied by scripts/build-wasm.sh")
	os.Exit(0)
}
