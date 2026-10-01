// Command app is the index for hello_cloud. Laravel Cloud runs it because the
// branch carries a go.mod, so the environment was detected as Go -- and here
// that is the literal truth: `main` is a real Go module and Cloud compiles this
// file. Every other branch gets the same treatment from Cloud and answers with
// a binary built from another language instead.
//
// This is also the reference implementation of the shared page's placeholder
// substitution, which every language branch re-implements in a dozen lines of
// its own language. Keep them in step.
package main

import (
	"bytes"
	"embed"
	"html"
	"log"
	"net"
	"net/http"
	"os"
	"strings"
	"sync"
	"time"

	"github.com/artisan-build/hello_cloud/internal/ogen"
)

const (
	// language is what this binary says hello from. On main that is the truth.
	language = "Go"
	branch   = "main"
	repoURL  = "https://github.com/artisan-build/hello_cloud"
)

//go:embed shared/page.html shared/index-url.txt shared/languages.tsv
var shared embed.FS

func main() {
	template := mustRead("shared/page.html")
	indexURL := strings.TrimSpace(mustRead("shared/index-url.txt"))
	langs := parseLanguages(mustRead("shared/languages.tsv"))
	extra := directory(langs)

	var once sync.Once
	var card []byte
	var cardErr error

	mux := http.NewServeMux()

	mux.HandleFunc("/og.png", func(w http.ResponseWriter, r *http.Request) {
		once.Do(func() { card, cardErr = ogen.PNG(language) })
		if cardErr != nil {
			http.Error(w, cardErr.Error(), http.StatusInternalServerError)
			return
		}
		w.Header().Set("Content-Type", "image/png")
		w.Header().Set("Cache-Control", "public, max-age=3600")
		http.ServeContent(w, r, "og.png", time.Time{}, bytes.NewReader(card))
	})

	mux.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path != "/" {
			http.NotFound(w, r)
			return
		}
		w.Header().Set("Content-Type", "text/html; charset=utf-8")
		_, _ = w.Write([]byte(render(template, r.Host, indexURL, extra)))
	})

	// Laravel Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an
	// IPv6-only network, so bind the dual-stack wildcard rather than 0.0.0.0.
	addr := net.JoinHostPort("::", port())
	log.Printf("hello_cloud: hello from %s, serving on %s", language, addr)
	srv := &http.Server{Addr: addr, Handler: mux, ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(srv.ListenAndServe())
}

// render fills the shared template's seven placeholders. host comes from the
// request because og:image and og:url must be absolute; the scheme is
// hard-coded to https because Cloud terminates TLS upstream and then sends
// X-Forwarded-Proto: http on an https request, so that header cannot be used.
func render(template, host, indexURL, extra string) string {
	base := "https://" + host
	return strings.NewReplacer(
		"{{LANGUAGE}}", language,
		"{{BRANCH}}", branch,
		"{{BRANCH_URL}}", repoURL+"/tree/"+branch,
		"{{OG_IMAGE}}", base+"/og.png",
		"{{PAGE_URL}}", base+"/",
		"{{INDEX_URL}}", indexURL,
		"{{EXTRA}}", extra,
	).Replace(template)
}

func port() string {
	if p := os.Getenv("PORT"); p != "" {
		return p
	}
	return "3000"
}

func mustRead(name string) string {
	b, err := shared.ReadFile(name)
	if err != nil {
		log.Fatalf("hello_cloud: %v", err)
	}
	return string(b)
}

// languageRow is one row of shared/languages.tsv.
type languageRow struct {
	Slug, Name, Framework, URL string
}

func parseLanguages(tsv string) []languageRow {
	var out []languageRow
	for _, line := range strings.Split(strings.TrimSpace(tsv), "\n") {
		line = strings.TrimRight(line, "\r")
		if strings.TrimSpace(line) == "" || strings.HasPrefix(line, "#") {
			continue
		}
		f := strings.Split(line, "\t")
		if len(f) < 4 {
			continue
		}
		out = append(out, languageRow{Slug: f[0], Name: f[1], Framework: f[2], URL: f[3]})
	}
	return out
}

// directory renders the table of every live language: the one thing the index
// page has that a language page does not.
func directory(langs []languageRow) string {
	var b strings.Builder
	b.WriteString(`<section class="extra"><h2>Every language</h2>`)
	b.WriteString(`<p class="note">One branch, one Laravel Cloud environment, one native binary each.</p>`)
	b.WriteString(`<table><thead><tr><th>Language</th><th>Serving with</th><th>Branch</th></tr></thead><tbody>`)
	for _, l := range langs {
		b.WriteString(`<tr><td><a href="` + html.EscapeString(l.URL) + `">` + html.EscapeString(l.Name) + `</a></td>`)
		b.WriteString(`<td class="fw">` + html.EscapeString(l.Framework) + `</td>`)
		b.WriteString(`<td><a href="` + html.EscapeString(repoURL+"/tree/"+l.Slug) + `"><code>` + html.EscapeString(l.Slug) + `</code></a></td></tr>`)
	}
	b.WriteString(`</tbody></table></section>`)
	return b.String()
}
