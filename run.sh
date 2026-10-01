#!/bin/sh
# Entry point INSIDE the unpacked bundle (bootstrap.c execs ./run).
#
# jre/ is a jlink runtime image, so nothing on the host needs a JVM. clj/ is
# both the source path and the resource root; Clojure compiles core.clj on the
# way up, which is why there is no uberjar here.
set -e
d=$(cd "$(dirname "$0")" && pwd)

# Laravel Cloud hands the app process RLIMIT_NOFILE = 1073741816. Runtimes that
# size a table from the fd limit allocate hundreds of megabytes from that alone
# -- it is what killed the Elixir release on a 512 MB instance. Lowering a soft
# limit never needs privileges.
ulimit -n 65536 2>/dev/null || true

{
    echo "diag: nproc=$(nproc 2>/dev/null || echo '?')"
    echo "diag: ulimit -n=$(ulimit -n) -v=$(ulimit -v) -s=$(ulimit -s)"
    echo "diag: cgroup.max=$(cat /sys/fs/cgroup/memory.max 2>/dev/null || cat /sys/fs/cgroup/memory/memory.limit_in_bytes 2>/dev/null || echo n/a)"
    echo "diag: bundle-fs: $(df -P "$d" 2>/dev/null | tail -1)"
} >&2

# native/ carries libstdc++.so.6, which libjvm.so needs and Debian 12's base
# image does not have -- see vendor-libs.sh.
LD_LIBRARY_PATH="$d/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH

# The lib/* entry is expanded by the JVM, not the shell, so it stays quoted.
exec "$d/jre/bin/java" \
    -XX:+UseSerialGC \
    -XX:MaxRAMPercentage=40 \
    -XX:MaxMetaspaceSize=128m \
    -XX:-UsePerfData \
    -Xss1m \
    -Dfile.encoding=UTF-8 \
    -Dclojure.spec.skip-macros=true \
    -Djava.net.preferIPv6Addresses=true \
    -cp "$d/lib/*:$d/clj" \
    clojure.main -m hello-cloud.core
