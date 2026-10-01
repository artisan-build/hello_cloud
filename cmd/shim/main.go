// Command shim is the documented fallback for the go.mod trick. The trick
// assumes Laravel Cloud's Go runtime only needs *an* executable at ./app, and
// never checks that `go build` produced it. If a future Cloud release does
// check, a language branch's build command becomes
//
//	<fetch the language binary to ./hello> && go build -o app ./cmd/shim
//
// and ./app becomes a genuine Go binary whose entire job is to exec ./hello.
// Nothing else about a language branch changes.
package main

import (
	"log"
	"os"
	"syscall"
)

func main() {
	target := os.Getenv("HELLO_BINARY")
	if target == "" {
		target = "./hello"
	}
	if err := syscall.Exec(target, append([]string{target}, os.Args[1:]...), os.Environ()); err != nil {
		log.Fatalf("shim: exec %s: %v", target, err)
	}
}
