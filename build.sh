#!/bin/sh
# Builds ./app for the `c` branch, inside the image lang.json names (alpine,
# for a static musl toolchain). Run as: sh build.sh
#
# The three assets are linked in as data instead of being read at runtime:
# `ld -r -b binary` turns each file into an object with
# _binary_<path with non-alphanumerics as underscores>_{start,end} symbols,
# which main.c declares as extern. Nothing is read from disk at runtime.
set -eux

apk add --no-cache build-base >/dev/null

ld -r -b binary -o assets.o og.png shared/page.html shared/index-url.txt

cc -static -O2 -std=c11 -Wall -Wextra -Werror -o app main.c assets.o
strip app
