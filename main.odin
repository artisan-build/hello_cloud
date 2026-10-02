// Hello from Odin, on Laravel Cloud's Go runtime.
//
// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
// root, so the environment was detected as Go when it was created and Cloud
// starts whatever executable the build command left at `./app`. No Go is
// compiled for this branch; the build command downloads the binary that GitHub
// Actions built from this commit.
//
// No framework: `core:net` is the whole web layer -- a TCP listener, an accept
// loop, and just enough request parsing to find the path and the Host header.
// The shared HTML template, the index URL and the OG card are all `#load`ed at
// compile time, so nothing is read from Cloud's ephemeral disk.
package main

import "core:fmt"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"

LANGUAGE :: "Odin"
BRANCH :: "odin"
REPO :: "https://github.com/artisan-build/hello_cloud"

TEMPLATE := string(#load("shared/page.html"))
INDEX_URL := string(#load("shared/index-url.txt"))
OG_PNG := #load("og.png")

main :: proc() {
	port := listen_port()

	// Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
	// network. Binding the IPv6 wildcard is dual-stack on Linux -- core:net
	// never touches IPV6_V6ONLY -- so this one listener answers both families.
	listener, listen_err := net.listen_tcp(net.Endpoint{address = net.IP6_Any, port = port})
	if listen_err != nil {
		fmt.eprintfln("hello_cloud: listen on [::]:%d failed: %v", port, listen_err)
		os.exit(1)
	}
	defer net.close(listener)

	fmt.printfln("hello_cloud: hello from %s, serving on [::]:%d", LANGUAGE, port)

	for {
		client, _, accept_err := net.accept_tcp(listener)
		if accept_err != nil {
			fmt.eprintfln("hello_cloud: accept: %v", accept_err)
			continue
		}
		serve(client)
		net.close(client)
	}
}

listen_port :: proc() -> int {
	buf: [16]byte
	raw := os.get_env_buf(buf[:], "PORT")
	if raw == "" {
		return 3000
	}
	value, ok := strconv.parse_int(raw)
	if !ok || value <= 0 || value > 65535 {
		return 3000
	}
	return value
}

serve :: proc(client: net.TCP_Socket) {
	buf: [16 * 1024]byte
	received := 0
	for received < len(buf) {
		n, err := net.recv_tcp(client, buf[received:])
		if err != nil || n == 0 {
			break
		}
		received += n
		if strings.contains(string(buf[:received]), "\r\n\r\n") {
			break
		}
	}
	if received == 0 {
		return
	}
	request := string(buf[:received])

	if request_path(request) == "/og.png" {
		respond(client, "200 OK", "image/png", OG_PNG)
		return
	}
	if request_path(request) != "/" {
		respond(client, "404 Not Found", "text/plain; charset=utf-8", transmute([]byte)string("not found\n"))
		return
	}

	page := render_page(request_host(request))
	defer delete(page)
	respond(client, "200 OK", "text/html; charset=utf-8", transmute([]byte)page)
}

// "GET /path HTTP/1.1" -- the path is between the first two spaces. Social
// sites append `?fbclid=...` and `?utm_source=...`, so `?` ends the path too,
// as does `#` if a client ever sends a fragment.
request_path :: proc(request: string) -> string {
	start := strings.index_byte(request, ' ')
	if start < 0 {
		return "/"
	}
	rest := request[start + 1:]
	end := strings.index_any(rest, " \r\n?#")
	if end < 0 {
		return "/"
	}
	return rest[:end]
}

// The Host header value, or "localhost" when the request carries none.
request_host :: proc(request: string) -> string {
	// split_lines_iterator advances its argument, and Odin parameters are
	// immutable, so it iterates over a local copy of the same bytes.
	rest := request
	for line in strings.split_lines_iterator(&rest) {
		colon := strings.index_byte(line, ':')
		if colon < 0 {
			continue
		}
		if !strings.equal_fold(line[:colon], "host") {
			continue
		}
		return strings.trim_space(line[colon + 1:])
	}
	return "localhost"
}

// Fills the shared template's seven placeholders.
//
// og:image and og:url have to be absolute, so they are built from the request's
// Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
// then sends `X-Forwarded-Proto: http` on an https request, so that header
// cannot be trusted.
render_page :: proc(host: string) -> string {
	branch_url := fmt.tprintf("%s/tree/%s", REPO, BRANCH)
	og_image := fmt.tprintf("https://%s/og.png", host)
	page_url := fmt.tprintf("https://%s/", host)

	replacements := [?][2]string{
		{"{{LANGUAGE}}", LANGUAGE},
		{"{{BRANCH_URL}}", branch_url},
		{"{{BRANCH}}", BRANCH},
		{"{{OG_IMAGE}}", og_image},
		{"{{PAGE_URL}}", page_url},
		{"{{INDEX_URL}}", strings.trim_space(INDEX_URL)},
		{"{{EXTRA}}", ""}, // only main fills this
	}

	out := strings.clone(TEMPLATE)
	for replacement in replacements {
		next, _ := strings.replace_all(out, replacement[0], replacement[1])
		delete(out)
		out = next
	}
	return out
}

respond :: proc(client: net.TCP_Socket, status, content_type: string, body: []byte) {
	head := fmt.tprintf(
		"HTTP/1.1 %s\r\ncontent-type: %s\r\ncontent-length: %d\r\nconnection: close\r\n\r\n",
		status,
		content_type,
		len(body),
	)
	_, head_err := net.send_tcp(client, transmute([]byte)head)
	if head_err != nil {
		return
	}
	net.send_tcp(client, body)
}
