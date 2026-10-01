#!/bin/sh
# Builds ./app for the `cpp` branch, inside the image lang.json names (alpine,
# for a static musl toolchain). Run as: sh build.sh
#
# cpp-httplib is one header, pinned by tag and checked by SHA-256 rather than
# vendored into the branch. The three assets are linked in as data:
# `ld -r -b binary` turns each file into an object with
# _binary_<path with non-alphanumerics as underscores>_{start,end} symbols,
# which main.cpp declares as extern "C". Nothing is read from disk at runtime.
set -eux

HTTPLIB_VERSION=v0.58.0
HTTPLIB_SHA256=aa14e7e7bd2703694e0a6b6855af3b8c406102ab1fc56ac905fe33619b31faa5

apk add --no-cache build-base curl >/dev/null

curl -fsSL "https://raw.githubusercontent.com/yhirose/cpp-httplib/${HTTPLIB_VERSION}/httplib.h" -o httplib.h
echo "${HTTPLIB_SHA256}  httplib.h" | sha256sum -c -

ld -r -b binary -o assets.o og.png shared/page.html shared/index-url.txt

g++ -static -O2 -std=c++17 -Wall -Wextra -o app main.cpp assets.o -pthread
strip app
