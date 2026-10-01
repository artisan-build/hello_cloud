#!/bin/sh
# Builds ./app for the elixir branch, inside the image lang.json names.
#
# The product of `mix release` is a DIRECTORY carrying its own ERTS, so it is
# packed into a single self-extracting linux/arm64 ELF -- see bootstrap.c.
set -eux

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    gcc libc6-dev git >/dev/null

export MIX_ENV=prod HEX_OFFLINE=0
mix local.hex --force --if-missing
mix local.rebar --force --if-missing
mix deps.get
mix release hello_cloud --overwrite

rel=target/_build/prod/rel/hello_cloud
install -m 755 run.sh "$rel/run"
sh vendor-libs.sh "$rel"
du -sh "$rel"
sh pack.sh elixir "$rel" run
