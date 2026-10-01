#!/bin/sh
# The entry point inside the bundle that ./app unpacks.
#
# Dream links OpenSSL and libev, and Debian 12 -- Cloud's runtime image --
# has neither libssl.so.3 nor libcrypto.so.3 nor libev.so.4. The three shared
# objects travel in the bundle, so no runtime is assumed on the host.
# (A fully static link was tried first and is not available here: pulling
# libc.a into the aarch64 binary overflows the GOT -- "relocation truncated
# to fit: R_AARCH64_LD64_GOTPAGE_LO15" -- because the OCaml runtime objects
# are compiled -fpic rather than -fPIC.)
set -eu
BASE=$(cd "$(dirname "$0")" && pwd)
LD_LIBRARY_PATH="$BASE/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$BASE/server"
