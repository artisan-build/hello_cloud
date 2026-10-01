#!/bin/sh
# Builds ./app for the `asm-arm64` branch, inside the image lang.json names.
# Run as: sh build.sh
#
# There is no compiler here and no libc: GNU as assembles main.S and GNU ld
# links it on its own, so the result is a static ELF whose entry point is
# _start. binutils is the only package installed.
set -eux

apk add --no-cache binutils >/dev/null

as -o main.o main.S
ld -o app main.o
