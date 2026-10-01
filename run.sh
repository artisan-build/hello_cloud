#!/bin/sh
# Entry point INSIDE the unpacked bundle (bootstrap.c execs ./run).
#
# native/ holds the shared libraries Debian 12's base image does not have --
# see vendor-libs.sh. RELEASE_DISTRIBUTION=none keeps the release from starting
# epmd and naming the node: this process serves HTTP and nothing clusters.
set -e
d=$(cd "$(dirname "$0")" && pwd)
LD_LIBRARY_PATH="$d/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
RELEASE_TMP="$d/tmp"
RELEASE_DISTRIBUTION=none
ELIXIR_ERL_OPTIONS="+fnu"
export LD_LIBRARY_PATH RELEASE_TMP RELEASE_DISTRIBUTION ELIXIR_ERL_OPTIONS
mkdir -p "$RELEASE_TMP"
exec "$d/bin/hello_cloud" start
