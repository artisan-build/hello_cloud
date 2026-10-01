## Hello from Nim, on Laravel Cloud's Go runtime.
##
## Laravel Cloud runs this binary because the branch carries a `go.mod` at its
## root, so the environment was detected as Go when it was created and Cloud
## starts whatever executable the build command left at `./app`. The build
## command never compiles any Go: it downloads the binary GitHub Actions built
## from this commit.
##
## `staticRead` pulls the shared template, the index URL and the OG card into
## the executable at compile time, so nothing on Cloud's ephemeral filesystem
## matters once the process is up.
##
## The server is `std/asynchttpserver` rather than Jester: Jester hands
## httpbeast only (port, bindAddr, numThreads) and leaves httpbeast's `domain`
## at AF_INET, so a Jester app cannot listen on the IPv6 wildcard that Cloud's
## per-instance nginx dials. `asynchttpserver.serve` takes `domain` directly.

import std/[asyncdispatch, asynchttpserver, httpcore, nativesockets, os, strutils]

const
  Language = "Nim"
  Branch = "nim"
  RepoUrl = "https://github.com/artisan-build/hello_cloud"
  Template = staticRead("shared/page.html")
  IndexUrl = staticRead("shared/index-url.txt")
  OgPng = staticRead("og.png")

proc page(host: string): string =
  ## Fills the shared template's seven placeholders. `strutils.replace`
  ## replaces every occurrence, and {{LANGUAGE}} appears nine times.
  let base = "https://" & host
  result = Template
    .replace("{{LANGUAGE}}", Language)
    .replace("{{BRANCH_URL}}", RepoUrl & "/tree/" & Branch)
    .replace("{{BRANCH}}", Branch)
    .replace("{{OG_IMAGE}}", base & "/og.png")
    .replace("{{PAGE_URL}}", base & "/")
    .replace("{{INDEX_URL}}", IndexUrl.strip())
    .replace("{{EXTRA}}", "")

proc handle(req: Request) {.async.} =
  ## og:image and og:url have to be absolute, so they are built from the
  ## request's Host header with a hard-coded https scheme: Cloud terminates TLS
  ## upstream and then sends `X-Forwarded-Proto: http` on an https request, so
  ## that header cannot be trusted.
  let host = if req.headers.hasKey("host"): $req.headers["host"] else: "localhost"

  case req.url.path
  of "/og.png":
    await req.respond(Http200, OgPng, newHttpHeaders({
      "Content-Type": "image/png",
      "Cache-Control": "public, max-age=3600"}))
  of "/":
    await req.respond(Http200, page(host), newHttpHeaders({
      "Content-Type": "text/html; charset=utf-8"}))
  else:
    await req.respond(Http404, "not found\n", newHttpHeaders({
      "Content-Type": "text/plain; charset=utf-8"}))

when isMainModule:
  let port = Port(parseInt(getEnv("PORT", "3000")))
  let server = newAsyncHttpServer()
  echo "hello_cloud: hello from ", Language, ", serving on [::]:", port.uint16
  # Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
  # network, so bind the dual-stack wildcard.
  waitFor server.serve(port, handle, "::", domain = AF_INET6)
