#!/bin/sh
# Entry point INSIDE the unpacked bundle (bootstrap.c execs ./run).
#
# jre/ is a jlink runtime image, so nothing on the host needs a JVM. The flags
# are what a hello-world Jetty needs to behave on the smallest Cloud instance:
# the serial collector instead of G1 (one vCPU, and G1's region bookkeeping is
# pure overhead here), a small thread stack, and a capped metaspace.
set -e
d=$(cd "$(dirname "$0")" && pwd)

# Laravel Cloud hands the app process RLIMIT_NOFILE = 1073741816. Runtimes that
# size a table from the fd limit allocate hundreds of megabytes from that alone
# -- it is what killed the Elixir release on a 512 MB instance. Lowering a soft
# limit never needs privileges.
ulimit -n 65536 2>/dev/null || true

{
    echo "diag: nproc=$(nproc 2>/dev/null || echo '?')"
    echo "diag: ulimit -v=$(ulimit -v) -n=$(ulimit -n) -s=$(ulimit -s)"
    echo "diag: cgroup.max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo n/a)"
    echo "diag: MemTotal=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo '?')kB"
    echo "diag: bundle-fs: $(df -P "$d" 2>/dev/null | tail -1)"
} >&2
# native/ carries libstdc++.so.6, which libjvm.so needs and Debian 12's base
# image does not have -- see vendor-libs.sh.
LD_LIBRARY_PATH="$d/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH

exec "$d/jre/bin/java" \
    -XX:+UseSerialGC \
    -XX:MaxRAMPercentage=45 \
    -XX:MaxMetaspaceSize=96m \
    -XX:-UsePerfData \
    -Xss512k \
    -Dfile.encoding=UTF-8 \
    -Djava.net.preferIPv6Addresses=true \
    -jar "$d/app.jar"
