#!/bin/sh
# Entry point INSIDE the unpacked bundle (bootstrap.c execs ./run).
#
# native/ holds the shared libraries Debian 12's base image does not have --
# see vendor-libs.sh; libcrypto.so.3 is the one that matters, because ERTS
# loads its crypto NIF while `kernel` starts.
#
# ERL_ZFLAGS pins the BEAM to one scheduler. It has to: ERTS sizes its
# scheduler threads AND its per-scheduler allocator carriers from the CPU count
# it can SEE, which inside a container is the host's, not the instance's quota.
# Unpinned, this hello-world release was killed for running out of memory on a
# 512 MB Laravel Cloud instance before it printed a line.
#
# RELEASE_DISTRIBUTION=none keeps the release from starting epmd and naming the
# node: this process serves HTTP and nothing clusters with it.
set -e
d=$(cd "$(dirname "$0")" && pwd)
LD_LIBRARY_PATH="$d/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
RELEASE_TMP="$d/tmp"
RELEASE_DISTRIBUTION=none
ELIXIR_ERL_OPTIONS="+fnu"
ERL_ZFLAGS="+S 1:1 +SDcpu 1:1 +SDio 1 +A 2 +sbwt none +sbwtdcpu none +sbwtdio none +MBas aobf"
export LD_LIBRARY_PATH RELEASE_TMP RELEASE_DISTRIBUTION ELIXIR_ERL_OPTIONS ERL_ZFLAGS
mkdir -p "$RELEASE_TMP"
echo "run: nproc=$(nproc 2>/dev/null || echo '?') ERL_ZFLAGS=$ERL_ZFLAGS" >&2
exec "$d/bin/hello_cloud" start
