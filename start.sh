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

# THE line. Laravel Cloud hands the app process RLIMIT_NOFILE = 1,073,741,816,
# and ERTS sizes its port table from the fd limit -- so the BEAM tried to
# allocate on the order of a gigabyte for a table it never uses one entry of,
# and the cgroup killed it before it printed anything. That is why this branch
# failed identically at 256 MB, 512 MB and 1 GB, and why Cloud's "increase your
# memory" advice never helped. Found by batch c (phase2-c-beam-jvm.md 4.1) on
# Elixir, reproduced with `docker run --memory=256m --ulimit nofile=1073741816`.
# Lowering a soft limit needs no privileges.
ulimit -n 65536 2>/dev/null || true

# Small-instance tuning, not the fix: one scheduler of each kind, no busy-wait,
# and 32 MB rather than 1 GB of reserved address space for the literal and
# mseg super carriers.
{
    echo "diag: nproc=$(nproc 2>/dev/null || echo '?')"
    echo "diag: ulimit -n=$(ulimit -n) -s=$(ulimit -s)"
    echo "diag: cgroup.max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || echo n/a)"
    echo "diag: bundle-fs: $(df -P "$BASE" 2>/dev/null | tail -1)"
} >&2
exec "$BASE/erlang/bin/erl" \
    +S 1:1 +SDcpu 1:1 +SDio 1 +A 2 \
    +sbwt none +sbwtdcpu none +sbwtdio none \
    +MIscs 32 +MMscs 32 \
    -pa "$BASE"/shipment/*/ebin \
    -eval 'hello@@main:run(hello)' \
    -noshell
