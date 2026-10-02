#!/bin/sh
# usage: sh tools/sfx/vendor-libs.sh <bundle dir>
#
# Copies into <bundle dir>/native every shared library the bundle's own ELF
# files need but Debian 12's BASE image does not ship -- Cloud's runtime is
# `debian:12` with nothing added, which is a much smaller set of libraries than
# any language toolchain image. Point LD_LIBRARY_PATH at that directory from
# the bundle's entry script.
#
# The one that actually bites: libcrypto.so.3. ERTS loads its `crypto` NIF
# while `kernel` starts, and the debian:12 image has no libssl3, so without it
# the BEAM dies before any application runs. Clojure pulled in twelve, because
# jdeps asks for java.desktop and ring-core reaches into javax.imageio.
#
# The glibc set is excluded on purpose: the build image and Cloud's runtime are
# both bookworm, so the host's own copy is the right one, and shipping a second
# ld.so is how you get a loader mismatch. Anything already inside the bundle is
# skipped too, so a jlink image's own libjava.so is not shadowed by a copy.
set -eu
dir=${1:?usage: vendor-libs.sh <bundle dir>}
mkdir -p "$dir/native"

find "$dir" -type f -print | while read -r f; do
    ldd "$f" 2>/dev/null | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p'
done | sort -u | while read -r so; do
    case "$(basename "$so")" in
        libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|libresolv.so.2|\
        libutil.so.1|libgcc_s.so.1|ld-linux-aarch64.so.1|libz.so.1|libanl.so.1) continue ;;
    esac
    if find "$dir" -name "$(basename "$so")" ! -path "$dir/native/*" | grep -q .; then
        continue
    fi
    cp -n "$so" "$dir/native/" 2>/dev/null || true
done

ls -l "$dir/native"
