#!/bin/sh
# Pack a runtime bundle into a single linux/arm64 ELF at ./app.
#   sh pack.sh <slug> <bundle dir> <entry script, relative to the bundle root>
# See bootstrap.c for why the pipeline's one `app` asset has to be an ELF.
set -eu
slug=$1
dir=$2
entry=$3
mkdir -p target
cc -O2 -static -Wall -o target/bootstrap \
   -DSFX_SLUG="\"$slug\"" -DSFX_ENTRY="\"$entry\"" bootstrap.c
tar -czf target/bundle.tar.gz -C "$dir" .
off=$(wc -c < target/bootstrap | tr -d ' ')
cat target/bootstrap target/bundle.tar.gz > app
printf 'HELLO_CLOUD_SFX_TRAILER1%016d' "$off" >> app
chmod 755 app
ls -l app
