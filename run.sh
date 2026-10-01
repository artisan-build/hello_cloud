#!/bin/sh
# Entry point INSIDE the unpacked bundle (bootstrap.c execs ./run).
#
# native/ holds the shared libraries Debian 12's base image does not have --
# see vendor-libs.sh; libcrypto.so.3 is the one that matters, because ERTS
# loads its crypto NIF while `kernel` starts.
#
# ERL_ZFLAGS: three Cloud deploys of this release were killed with "out of
# memory" before the VM printed a line, at 256 MB AND at 512 MB, so the cause
# is not simply a small instance. These flags cut the two things ERTS sizes
# generously by default: one scheduler and one dirty scheduler of each kind
# instead of one per visible CPU, and 32 MB rather than 1 GB of reserved
# address space for the literal and mseg super carriers.
#
# RELEASE_DISTRIBUTION=none keeps the release from starting epmd and naming the
# node: this process serves HTTP and nothing clusters with it.
set -e
d=$(cd "$(dirname "$0")" && pwd)
LD_LIBRARY_PATH="$d/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
RELEASE_TMP="$d/tmp"
RELEASE_DISTRIBUTION=none
ELIXIR_ERL_OPTIONS="+fnu"
ERL_ZFLAGS="+S 1:1 +SDcpu 1:1 +SDio 1 +A 2 +sbwt none +sbwtdcpu none +sbwtdio none +MIscs 32 +MMscs 32"
export LD_LIBRARY_PATH RELEASE_TMP RELEASE_DISTRIBUTION ELIXIR_ERL_OPTIONS ERL_ZFLAGS
mkdir -p "$RELEASE_TMP"
# Diagnostics, kept because they are the only window onto what Cloud's runtime
# actually hands a process that is not PHP.
{
    echo "diag: nproc=$(nproc 2>/dev/null || echo '?')"
    echo "diag: ulimit -v=$(ulimit -v) -m=$(ulimit -m) -n=$(ulimit -n) -s=$(ulimit -s)"
    echo "diag: cgroup.max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo n/a)"
    echo "diag: cgroup.high=$(cat /sys/fs/cgroup/memory.high 2>/dev/null || echo n/a)"
    echo "diag: MemTotal=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo '?')kB"
    echo "diag: bundle-fs: $(df -P "$d" 2>/dev/null | tail -1)"
    echo "diag: tmp-fs:    $(df -P /tmp 2>/dev/null | tail -1)"
} >&2
exec "$d/bin/hello_cloud" start
