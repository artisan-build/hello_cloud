#!/bin/sh
# Pack a runtime bundle into a single linux/arm64 ELF at ./app.
#
#     sh tools/sfx/pack.sh <slug> <bundle dir> <entry, relative to the bundle root>
#
# <entry> is executed inside the unpacked bundle with SFX_ROOT set to the
# unpack directory. See bootstrap.c for why the pipeline's one `app` asset has
# to be an ELF, and tools/sfx/README.md for the whole recipe.
#
# Run this inside the language's own build container (the one lang.json names),
# not on the host: `cc -static` has to produce an aarch64 binary and the bundle
# has to be tarred as root-readable.
set -eu

slug=${1:?usage: pack.sh <slug> <bundle dir> <entry>}
dir=${2:?usage: pack.sh <slug> <bundle dir> <entry>}
entry=${3:?usage: pack.sh <slug> <bundle dir> <entry>}

here=$(cd "$(dirname "$0")" && pwd)
test -x "$dir/$entry" || { echo "pack.sh: $dir/$entry is not executable" >&2; exit 1; }

mkdir -p target
cc -O2 -static -Wall -o target/bootstrap \
   -DSFX_SLUG="\"$slug\"" -DSFX_ENTRY="\"$entry\"" "$here/bootstrap.c"

tar -czf target/bundle.tar.gz -C "$dir" .
off=$(wc -c < target/bootstrap | tr -d ' ')
cat target/bootstrap target/bundle.tar.gz > app
printf 'HELLO_CLOUD_SFX_TRAILER1%016d' "$off" >> app
chmod 755 app

echo "pack.sh: $(du -sh "$dir" | cut -f1) bundle -> $(wc -c < app | tr -d ' ') byte app"
# `file` is not in debian:12's base image, so this is best-effort; CI runs the
# real ELF check on the runner, which does have it.
command -v file >/dev/null && file app || true
