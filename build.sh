#!/bin/sh
# Builds ./app for the `v` branch, inside the image lang.json names.
# Run as: sh build.sh
#
# V ships a prebuilt linux/arm64 compiler, so this pulls that pinned release
# and checks its SHA-256 rather than bootstrapping from vc. gcc is V's backend.
#
# -prod matters for more than speed: without it, `$embed_file` reads its file
# from disk at RUNTIME, which would break on Cloud's ephemeral filesystem.
set -eux

V_VERSION=0.5.2
V_SHA256=7e102f0ecc722bc59fea83ab1c99ae49c2f7be8f30abee9443220e452a439ed3

apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl unzip gcc libc6-dev >/dev/null

curl -fsSL "https://github.com/vlang/v/releases/download/${V_VERSION}/v_linux_arm64.zip" -o v.zip
echo "${V_SHA256}  v.zip" | sha256sum -c -
unzip -q -o v.zip
./v/v version

./v/v -prod -cc gcc -o app main.v
