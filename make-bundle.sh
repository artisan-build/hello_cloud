#!/bin/sh
# Assemble the gforth bundle that tools/sfx/pack.sh turns into ./app.
#
# gforth's deliverable is three things, not one: the engine ELF, the .fi image
# it loads, and the Forth library tree the image reads `unix/socket.fs` from.
# A fourth has to be made here: gforth's c-library facility compiles its C glue
# with gcc and libtool AT RUN TIME and caches the shared object under
# $HOME/.gforth/libcc-named. Cloud's runtime is a bare debian:12 with neither
# compiler, so we warm that cache during the build and ship it -- gforth then
# finds the .so and never shells out.
set -eu

V=0.7.3
B=bundle
rm -rf "$B"
mkdir -p "$B/bin" "$B/lib" "$B/assets" "$B/home"

cp /usr/bin/gforth-$V                               "$B/bin/gforth"
cp /usr/lib/aarch64-linux-gnu/gforth/$V/gforth.fi   "$B/gforth.fi"
cp -R /usr/share/gforth/$V/.                        "$B/lib/"
rm -rf "$B/lib/doc" "$B/lib/TAGS"

cp hello.fs "$B/hello.fs"
cp run      "$B/run"
chmod +x    "$B/run"

cp shared/page.html     "$B/assets/page.html"
cp shared/index-url.txt "$B/assets/index-url.txt"
cp og.png               "$B/assets/og.png"

# Warm the libcc cache with the real engine, image and path the bundle will
# use, so the cached object is the one it looks for at run time.
HOME="$(pwd)/$B/home" "$B/bin/gforth" -p "$(pwd)/$B/lib" -i "$(pwd)/$B/gforth.fi" \
    -e 'require unix/socket.fs bye'
test -d "$B/home/.gforth/libcc-named" || { echo "make-bundle: libcc cache is missing" >&2; exit 1; }
ls -l "$B/home/.gforth/libcc-named/.libs/"

# Everything the bundle's own ELFs need that debian:12 does not ship. For
# gforth that is libltdl.so.7, which is not in the base image.
sh tools/sfx/vendor-libs.sh "$B"

du -sh "$B"
