#!/bin/sh
# The entry point inside the bundle that ./app unpacks.
#
# Erlang's own `erl` script finds its ROOTDIR by walking up from $0 until it
# sees an erts-* directory, so an installation copied into the bundle is
# relocatable as-is. The two OpenSSL shared objects the `crypto` NIF needs
# travel in the bundle too -- Debian 12, Cloud's runtime image, has no
# libcrypto.so.3 -- so no runtime is assumed on the host and nothing outside
# this directory is read.
set -eu
BASE=$(cd "$(dirname "$0")" && pwd)
LD_LIBRARY_PATH="$BASE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$BASE/erlang/bin/erl" \
    -pa "$BASE"/shipment/*/ebin \
    -eval 'hello@@main:run(hello)' \
    -noshell
