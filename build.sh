#!/bin/sh
# Builds ./app for the `odin` branch, inside the image lang.json names.
# Run as: sh build.sh
#
# Odin ships no official toolchain image, so this pulls the pinned linux/arm64
# release tarball and checks its SHA-256. Odin drives `clang` as its linker,
# which is the only other thing installed here.
set -eux

ODIN_RELEASE=dev-2026-09
ODIN_DIR="odin-linux-arm64-nightly+2026-09-01"
ODIN_SHA256=c150c6f2d13668f3a1c4116ef96ea85c1ba1c9ededfd76081cd3c7d4ba92aa91

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl clang >/dev/null

curl -fsSL "https://github.com/odin-lang/Odin/releases/download/${ODIN_RELEASE}/odin-linux-arm64-${ODIN_RELEASE}.tar.gz" -o odin.tar.gz
echo "${ODIN_SHA256}  odin.tar.gz" | sha256sum -c -
tar -xzf odin.tar.gz
"./${ODIN_DIR}/odin" version

"./${ODIN_DIR}/odin" build main.odin -file -out:app -o:speed
