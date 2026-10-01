# Hello from Julia, on Laravel Cloud's Go runtime.
#
# Laravel Cloud runs this binary because the branch carries a `go.mod` at its
# root, so the environment was detected as Go when it was created and Cloud
# starts whatever executable the build command left at ./app. Nothing Go is
# compiled: the build command downloads the binary GitHub Actions built from
# this commit.
#
# What ./app is, for this branch, is unusual and is explained in stub.c: a
# PackageCompiler app is a directory -- a launcher, a sysimage, libjulia and
# its shared libraries -- and the pipeline carries exactly one file. So the
# directory is a tarball appended to a small C program that extracts it once
# and execs the launcher.
module HelloCloud

using HTTP
using Sockets

const LANGUAGE = "Julia"
const BRANCH = "julia"
const REPO_URL = "https://github.com/artisan-build/hello_cloud"

# Read at build time, baked into the sysimage: Cloud's filesystem is ephemeral
# and the extracted bundle holds no copy of the repo.
const TEMPLATE = read(joinpath(@__DIR__, "..", "shared", "page.html"), String)
const INDEX_URL = strip(read(joinpath(@__DIR__, "..", "shared", "index-url.txt"), String))
const OG_PNG = read(joinpath(@__DIR__, "..", "og.png"))

"""
Fills the shared template's seven placeholders.

`og:image` and `og:url` have to be absolute, so they are built from the
request's Host header with a hard-coded https scheme: Cloud terminates TLS
upstream and then sends `X-Forwarded-Proto: http` on an https request, so that
header cannot be trusted.
"""
function page(host::AbstractString)
    clean = filter(c -> isletter(c) || isdigit(c) || c in ".-:[]", host)
    isempty(clean) && (clean = "localhost")
    base = "https://" * clean
    values = Dict(
        "LANGUAGE" => LANGUAGE,
        "BRANCH" => BRANCH,
        "BRANCH_URL" => "$REPO_URL/tree/$BRANCH",
        "OG_IMAGE" => "$base/og.png",
        "PAGE_URL" => "$base/",
        "INDEX_URL" => INDEX_URL,
        "EXTRA" => "",
    )
    replace(TEMPLATE, r"\{\{([A-Z_]+)\}\}" => s -> get(values, s[3:end-2], ""))
end

function handle(req::HTTP.Request)
    if req.target == "/og.png"
        return HTTP.Response(200, ["Content-Type" => "image/png",
                                  "Cache-Control" => "public, max-age=3600"], OG_PNG)
    elseif req.target == "/"
        host = HTTP.header(req, "Host", "localhost")
        return HTTP.Response(200, ["Content-Type" => "text/html; charset=utf-8"], page(host))
    end
    HTTP.Response(404, ["Content-Type" => "text/plain; charset=utf-8"], "not found\n")
end

"""
The entry point PackageCompiler turns into the bundle's executable.
"""
function julia_main()::Cint
    port = parse(Int, get(ENV, "PORT", "3000"))
    # Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
    # network, so bind the dual-stack IPv6 wildcard. Julia's Sockets builds the
    # sockaddr from an IPv6 value rather than resolving a name, so there is no
    # getaddrinfo to refuse it on a host without IPv6, and IPV6_V6ONLY stays at
    # the Linux default of off -- one socket, both families.
    println("hello_cloud: hello from $LANGUAGE, serving on [::]:$port")
    flush(stdout)
    HTTP.serve(handle, Sockets.IPv6("::"), port)
    return 0
end

end # module
