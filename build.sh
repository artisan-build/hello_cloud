#!/bin/sh
# Builds ./app for the `d` branch, inside the image lang.json names (alpine,
# because LDC publishes a musl aarch64 toolchain there). Run as: sh build.sh
#
# -static matters: a musl-linked dynamic executable would not start on Cloud's
# Debian 12 runtime. -J. puts the branch root on the string-import path, which
# is how main.d's import("shared/page.html") and import("og.png") resolve.
set -eux

LDC_VERSION=1.43.0
LDC_DIR="ldc2-${LDC_VERSION}-alpine-aarch64"
LDC_SHA256=2ad9b985f66e05855cfd2581d7e9cf08d28c86afce02dbcd82aad531e0872979

apk add --no-cache build-base curl xz >/dev/null

curl -fsSL "https://github.com/ldc-developers/ldc/releases/download/v${LDC_VERSION}/${LDC_DIR}.tar.xz" -o ldc.tar.xz
echo "${LDC_SHA256}  ldc.tar.xz" | sha256sum -c -
# busybox tar's -J fails on this archive ("short read"), so xz decompresses and
# tar only unpacks.
xz -dc ldc.tar.xz | tar -xf -

"./${LDC_DIR}/bin/ldc2" -O2 -release -static -J. -of=app main.d
strip app
