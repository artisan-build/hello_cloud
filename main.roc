# Hello from Roc, on Laravel Cloud's Go runtime.
#
# Laravel Cloud runs this binary because the branch carries a `go.mod` at its
# root, so the environment was detected as Go when it was created and Cloud
# starts whatever executable the build command left at `./app`. The build
# command for this environment never compiles any Go: it downloads the binary
# GitHub Actions built from this commit.
#
# The shared template, the index URL and the OG card are INGESTED FILES, so
# they are compiled into the binary and nothing is read from Cloud's ephemeral
# filesystem at run time.
app [Model, init!, respond!] {
    pf: platform "https://github.com/roc-lang/basic-webserver/releases/download/0.13.0/fSNqJj3-twTrb0jJKHreMimVWD7mebDOj0mnslMm2GM.tar.br",
}

import pf.Http exposing [Request, Response]
import pf.Url

import "shared/page.html" as page_template : Str
import "shared/index-url.txt" as index_url_file : Str
import "og.png" as og_png : List U8

language = "Roc"
branch = "roc"
repo_url = "https://github.com/artisan-build/hello_cloud"

Model : {}

init! : {} => Result Model []
init! = |{}| Ok({})

# `req.uri` is the raw request target, so it carries whatever query string a
# shared link brings with it. `Str.ends_with(req.uri, "/og.png")` was false for
# `/og.png?utm_source=x`, and the else branch then served the HTML page as the
# OG card -- and served it for every other path too, so nothing 404ed.
# `Url.path` is the platform's own accessor; it drops both the query and any
# fragment, which leaves the two routes exact.
respond! : Request, Model => Result Response [ServerErr Str]_
respond! = |req, _|
    path = req.uri |> Url.from_str |> Url.path

    if path == "/og.png" then
        Ok(
            {
                status: 200,
                headers: [
                    { name: "Content-Type", value: "image/png" },
                    { name: "Cache-Control", value: "public, max-age=3600" },
                ],
                body: og_png,
            },
        )
    else if path == "/" then
        Ok(
            {
                status: 200,
                headers: [{ name: "Content-Type", value: "text/html; charset=utf-8" }],
                body: Str.to_utf8(render(host_of(req))),
            },
        )
    else
        Ok(
            {
                status: 404,
                headers: [{ name: "Content-Type", value: "text/plain; charset=utf-8" }],
                body: Str.to_utf8("not found\n"),
            },
        )

# og:image and og:url have to be absolute, so they are built from the request's
# Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
# then sends `X-Forwarded-Proto: http` on an https request, so that header
# cannot be trusted.
host_of : Request -> Str
host_of = |req|
    req.headers
    |> List.keep_if(|h| h.name == "host" or h.name == "Host")
    |> List.first
    |> Result.map_ok(|h| h.value)
    |> Result.with_default("localhost")

render : Str -> Str
render = |host|
    base = "https://${host}"

    page_template
    |> Str.replace_each("{{LANGUAGE}}", language)
    |> Str.replace_each("{{BRANCH}}", branch)
    |> Str.replace_each("{{BRANCH_URL}}", "${repo_url}/tree/${branch}")
    |> Str.replace_each("{{OG_IMAGE}}", "${base}/og.png")
    |> Str.replace_each("{{PAGE_URL}}", "${base}/")
    |> Str.replace_each("{{INDEX_URL}}", Str.trim(index_url_file))
    |> Str.replace_each("{{EXTRA}}", "")
