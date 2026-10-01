#!/bin/sh
# Builds ./app for the erlang branch, inside the image lang.json names.
#
# A rebar3 release with include_erts is a DIRECTORY carrying its own ERTS, so
# it is packed into a single self-extracting linux/arm64 ELF -- see bootstrap.c.
set -eux

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    gcc libc6-dev git >/dev/null

# The page, the index URL and the OG card become base64 literals in a generated
# header, so hc_render compiles them in rather than reading any file at runtime.
set +x
mkdir -p target/gen
{
    printf -- '-define(PAGE_B64, "%s").\n'      "$(base64 -w0 shared/page.html)"
    printf -- '-define(INDEX_URL_B64, "%s").\n' "$(base64 -w0 shared/index-url.txt)"
    printf -- '-define(OG_B64, "%s").\n'        "$(base64 -w0 og.png)"
} > target/gen/hc_data.hrl
wc -c target/gen/hc_data.hrl
set -x

rebar3 as prod release

rel=target/_build/prod/rel/hello_cloud
install -m 755 run.sh "$rel/run"
sh vendor-libs.sh "$rel"
du -sh "$rel"
sh pack.sh erlang "$rel" run
