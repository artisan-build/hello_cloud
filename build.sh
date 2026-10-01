#!/bin/sh
# Builds ./app: a statically linked C host with Lua 5.4 inside it.
#
# Run by GitHub Actions inside the image lang.json names (debian:bookworm-slim),
# at the repo root, as root. Nothing here runs on Laravel Cloud -- Cloud's build
# command only downloads the finished binary.
#
# Four things happen: install a toolchain, build liblua.a, turn the four
# payloads into one linkable object, and link it all statically.
set -eux

LUA=lua-5.4.7
LUA_SHA256=9fbf5e28ef86c69858f6d3d34eccc32e911c1a28b4120ff3e84aaa70cfbf1e30

apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential curl ca-certificates

curl -fsSL "https://www.lua.org/ftp/$LUA.tar.gz" -o lua.tar.gz
echo "$LUA_SHA256  lua.tar.gz" | sha256sum -c -
tar -xzf lua.tar.gz

# LUA_USE_POSIX, not LUA_USE_LINUX: the Linux define pulls in dlopen for
# package.loadlib and readline for the stand-alone interpreter, and a static
# binary wants neither. Only liblua.a is built -- the `lua` and `luac`
# executables would need readline and are not used.
make -C "$LUA/src" -j"$(nproc)" liblua.a MYCFLAGS="-O2 -DLUA_USE_POSIX"

# `ld -r -b binary` makes every input file a blob in one object file, with
# _binary_<mangled filename>_{start,end} symbols. The two shared files are
# copied to flat names first so those symbols stay predictable.
cp shared/page.html page.html
cp shared/index-url.txt index_url.txt
ld -r -b binary -o payload.o app.lua page.html index_url.txt og.png

# -static: Cloud's runtime is Debian 12, and nothing here needs a shared
# library at all once glibc is linked in. No NSS lookups happen (the server
# never resolves a name), which is the one thing static glibc does badly.
gcc -O2 -Wall -Wextra -static -I"$LUA/src" -o app host.c payload.o "$LUA/src/liblua.a" -lm

strip app
ls -l app
