// Command ogen writes the Open Graph card for one language to a PNG file.
//
//	go run ./tools/ogen -language Rust -out og.png
//
// CI runs this on a language branch before that branch's own build, so the
// language's binary can embed the PNG and nothing image-shaped is committed.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/artisan-build/hello_cloud/internal/ogen"
)

func main() {
	language := flag.String("language", "", "language name, e.g. Rust")
	out := flag.String("out", "og.png", "output PNG path")
	flag.Parse()

	if *language == "" {
		fmt.Fprintln(os.Stderr, "ogen: -language is required")
		os.Exit(2)
	}

	data, err := ogen.PNG(*language)
	if err != nil {
		fmt.Fprintln(os.Stderr, "ogen:", err)
		os.Exit(1)
	}
	if err := os.WriteFile(*out, data, 0o644); err != nil {
		fmt.Fprintln(os.Stderr, "ogen:", err)
		os.Exit(1)
	}
	fmt.Printf("ogen: wrote %s (%d bytes, %dx%d) for %q\n", *out, len(data), ogen.Width, ogen.Height, *language)
}
