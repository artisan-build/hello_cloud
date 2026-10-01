// Hello from V, on Laravel Cloud's Go runtime.
//
// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
// root, so the environment was detected as Go when it was created and Cloud
// starts whatever executable the build command left at `./app`. No Go is
// compiled for this branch; the build command downloads the binary that GitHub
// Actions built from this commit.
//
// The web layer is veb, V's own framework. The shared HTML template, the index
// URL and the OG card are `$embed_file`d, so nothing is read from Cloud's
// ephemeral disk -- note that this only holds in a `-prod` build, which is what
// build.sh does: without it V reads an embedded file from disk at runtime.
module main

import os
import veb

const language = 'V'
const branch = 'v'
const repo = 'https://github.com/artisan-build/hello_cloud'

const page_template = $embed_file('shared/page.html')
const index_url = $embed_file('shared/index-url.txt')
const og_png = $embed_file('og.png')

pub struct Context {
	veb.Context
}

pub struct App {}

pub fn (app &App) index(mut ctx Context) veb.Result {
	host := ctx.get_header(.host) or { 'localhost' }
	return ctx.send_response_to_client('text/html; charset=utf-8', render_page(host))
}

@['/og.png']
pub fn (app &App) og_image(mut ctx Context) veb.Result {
	ctx.set_custom_header('cache-control', 'public, max-age=3600') or {}
	return ctx.send_response_to_client('image/png', og_png.to_bytes().bytestr())
}

// Fills the shared template's seven placeholders.
//
// og:image and og:url have to be absolute, so they are built from the request's
// Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
// then sends `X-Forwarded-Proto: http` on an https request, so that header
// cannot be trusted.
fn render_page(host string) string {
	return page_template.to_string().replace('{{LANGUAGE}}', language).replace('{{BRANCH_URL}}',
		'${repo}/tree/${branch}').replace('{{BRANCH}}', branch).replace('{{OG_IMAGE}}',
		'https://${host}/og.png').replace('{{PAGE_URL}}', 'https://${host}/').replace('{{INDEX_URL}}',
		index_url.to_string().trim_space()).replace('{{EXTRA}}', '') // {{EXTRA}} is only filled on main
}

fn listen_port() int {
	port := os.getenv('PORT').int()
	if port <= 0 || port > 65535 {
		return 3000
	}
	return port
}

fn main() {
	port := listen_port()
	println('hello_cloud: hello from ${language}, serving on [::]:${port}')
	mut app := &App{}
	// veb.run binds host '' with family .ip6, i.e. the IPv6 wildcard. That is
	// dual-stack on Linux, which is what Cloud's per-instance nginx needs: it
	// proxies to 127.0.0.1:$PORT over an IPv6-only network.
	veb.run[App, Context](mut app, port)
}
