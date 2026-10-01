#!/bin/sh
# usage: sh vendor-libs.sh <bundle dir>
#
# Copies into <bundle dir>/native every shared library the bundle's own ELF
# files need but Debian 12's BASE image does not ship. The one that actually
# bites is libcrypto.so.3: ERTS's `crypto` NIF is loaded while `kernel` starts,
# so without it the VM dies before any application runs -- and the debian:12
# image has no libssl3 package. The glibc trio is excluded on purpose: the build
# image and Cloud's runtime are both bookworm, so the host's own copy is right,
# and shipping a second ld.so is how you get a loader mismatch.
set -eu
dir=$1
mkdir -p "$dir/native"

find "$dir" -type f -print | while read -r f; do
    ldd "$f" 2>/dev/null | sed -n 's/.*=> \(\/[^ ]*\).*/\1/p'
done | sort -u | while read -r so; do
    case "$(basename "$so")" in
        libc.so.6|libm.so.6|libdl.so.2|libpthread.so.0|librt.so.1|libresolv.so.2|\
        libutil.so.1|libgcc_s.so.1|ld-linux-aarch64.so.1|libz.so.1|libanl.so.1) continue ;;
    esac
    # A jlink runtime image ships its own libjava/libjli/libnet; don't shadow
    # them with a second copy on LD_LIBRARY_PATH.
    if find "$dir" -name "$(basename "$so")" ! -path "$dir/native/*" | grep -q .; then
        continue
    fi
    cp -n "$so" "$dir/native/" 2>/dev/null || true
done

ls -l "$dir/native"
