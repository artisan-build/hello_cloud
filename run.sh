#!/bin/sh
# Entry point INSIDE the unpacked bundle (bootstrap.c execs ./run).
#
# native/ holds the shared libraries Debian 12's base image does not have --
# see vendor-libs.sh; libcrypto.so.3 is the one that matters, because ERTS
# loads its crypto NIF while `kernel` starts.
#
# THE fd limit line is the one that makes this run on Cloud at all. Laravel
# Cloud hands the app process RLIMIT_NOFILE = 1073741816, and ERTS sizes its
# port table from the fd limit, so the VM allocated on the order of a gigabyte
# and was OOM-killed before printing a line -- on a 512 MB instance as readily
# as on a 256 MB one. Lowering a soft limit never needs privileges. Reproduced
# exactly with `docker run --memory=256m --ulimit nofile=1073741816`.
#
# The ERL_ZFLAGS are small-instance tuning, not the fix: one scheduler and one
# dirty scheduler of each kind, and 32 MB rather than 1 GB of reserved address
# space for the literal and mseg super carriers. This is the configuration the
# 114 MiB measurement was taken in.
#
# RELEASE_DISTRIBUTION=none keeps the release from starting epmd and naming the
# node: this process serves HTTP and nothing clusters with it.
set -e
d=$(cd "$(dirname "$0")" && pwd)

ulimit -n 65536 2>/dev/null || true

LD_LIBRARY_PATH="$d/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
RELEASE_TMP="$d/tmp"
RELEASE_DISTRIBUTION=none
ELIXIR_ERL_OPTIONS="+fnu"
ERL_ZFLAGS="+S 1:1 +SDcpu 1:1 +SDio 1 +A 2 +sbwt none +sbwtdcpu none +sbwtdio none +MIscs 32 +MMscs 32"
export LD_LIBRARY_PATH RELEASE_TMP RELEASE_DISTRIBUTION ELIXIR_ERL_OPTIONS ERL_ZFLAGS
mkdir -p "$RELEASE_TMP"
{
    echo "diag: nproc=$(nproc 2>/dev/null || echo '?')"
    echo "diag: ulimit -n=$(ulimit -n) -v=$(ulimit -v) -s=$(ulimit -s)"
    echo "diag: cgroup.max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo n/a)"
    echo "diag: bundle-fs: $(df -P "$d" 2>/dev/null | tail -1)"
} >&2
exec "$d/bin/hello_cloud" start
