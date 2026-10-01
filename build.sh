#!/bin/sh
# Builds ./app: a Hummingbird server with the Swift runtime linked in.
#
# Run by GitHub Actions inside the image lang.json names, at the repo root, as
# root. Nothing here runs on Laravel Cloud -- Cloud's build command only
# downloads the finished binary.
set -eux

sh genpayload.sh

# --static-swift-stdlib puts the Swift runtime inside the binary, so Debian 12
# needs no Swift installed. The image is bookworm-based for the same reason the
# Rust branch's is: Cloud's runtime is Debian 12 / glibc 2.36, and a binary
# linked against a newer glibc will not load there.
swift build -c release --static-swift-stdlib

cp .build/release/app app

# 112 MB unstripped: the static Swift runtime brings a lot of debug info.
strip app
ls -l app
