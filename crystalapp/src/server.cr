# Hello from Crystal, on Laravel Cloud's Go runtime.
#
# Laravel Cloud runs this binary because the branch carries a `go.mod` at its
# root, so the environment was detected as Go when it was created and Cloud
# starts whatever executable the build command left at `./app`. The build
# command never compiles any Go: it downloads the binary GitHub Actions built
# from this commit.
#
# The binary is statically linked against musl on Alpine, because the official
# crystallang/crystal images have no linux/arm64 manifest and a dynamically
# linked Crystal binary would want libgc and libpcre2 on the runtime host.
require "base64"
require "kemal"

LANGUAGE = "Crystal"
BRANCH   = "crystal"
REPO_URL = "https://github.com/artisan-build/hello_cloud"

# Compile-time embedding. `read_file` is a macro, so the template and the index
# URL are string literals in the binary. The OG card goes through base64
# because a PNG is not valid UTF-8 and has no business in a string literal.
TEMPLATE  = {{ read_file("#{__DIR__}/../../shared/page.html") }}
INDEX_URL = {{ read_file("#{__DIR__}/../../shared/index-url.txt") }}
# A `{{ }}` interpolation is only expanded inside a macro body, which is what
# `{% begin %}` opens here: in ordinary code `"{{ ... }}"` is just a string, and
# Base64.decode then chokes on the brace.
{% begin %}
OG_PNG = Base64.decode("{{ `base64 ../og.png | tr -d '\n'`.strip.id }}")
{% end %}

# Fills the shared template's seven placeholders. `gsub` with a string pattern
# replaces every occurrence, and {{LANGUAGE}} appears nine times.
def page(host : String) : String
  base = "https://#{host}"
  TEMPLATE
    .gsub("{{LANGUAGE}}", LANGUAGE)
    .gsub("{{BRANCH_URL}}", "#{REPO_URL}/tree/#{BRANCH}")
    .gsub("{{BRANCH}}", BRANCH)
    .gsub("{{OG_IMAGE}}", "#{base}/og.png")
    .gsub("{{PAGE_URL}}", "#{base}/")
    .gsub("{{INDEX_URL}}", INDEX_URL.strip)
    .gsub("{{EXTRA}}", "")
end

# og:image and og:url have to be absolute, so they are built from the request's
# Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
# then sends `X-Forwarded-Proto: http` on an https request, so that header
# cannot be trusted.
get "/" do |env|
  env.response.content_type = "text/html; charset=utf-8"
  page(env.request.headers["Host"]? || "localhost")
end

get "/og.png" do |env|
  env.response.content_type = "image/png"
  env.response.headers["Cache-Control"] = "public, max-age=3600"
  env.response.write(OG_PNG)
end

# Nothing is served from disk: Cloud's filesystem is ephemeral and there is no
# public/ directory in the binary's working directory.
serve_static false

# Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
# network, so bind the dual-stack wildcard.
Kemal.config.host_binding = "::"
Kemal.config.env = "production"
Kemal.run (ENV["PORT"]? || "3000").to_i
