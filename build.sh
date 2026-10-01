#!/bin/sh
# Builds ./app for the java branch, inside the image lang.json names.
#
# debian:bookworm-slim rather than a JDK image on purpose: Cloud's runtime is
# Debian 12, and vendor-libs.sh copies libraries out of THIS image into the
# bundle, so the build image's glibc has to be the runtime's. Debian's own
# openjdk-17 and maven are used for exactly that reason.
#
# The product is a jlink runtime image plus a shaded jar -- a DIRECTORY -- so it
# is packed into a single self-extracting linux/arm64 ELF; see bootstrap.c.
set -eux

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    openjdk-17-jdk-headless maven gcc libc6-dev ca-certificates >/dev/null

JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
export JAVA_HOME
"$JAVA_HOME/bin/java" -version

mvn -q -B -Dmaven.repo.local=target/m2 package

bundle=target/bundle
rm -rf "$bundle"
mkdir -p "$bundle"
cp target/app.jar "$bundle/app.jar"

# jdeps works out which platform modules the shaded jar actually touches, so
# the runtime image stays small without a hand-maintained module list.
mods=$("$JAVA_HOME/bin/jdeps" --ignore-missing-deps --print-module-deps \
        --multi-release 17 "$bundle/app.jar")
echo "jdeps modules: $mods"
"$JAVA_HOME/bin/jlink" \
    --add-modules "$mods,jdk.unsupported,java.management" \
    --no-header-files --no-man-pages --strip-debug --compress=2 \
    --output "$bundle/jre"

install -m 755 run.sh "$bundle/run"
sh vendor-libs.sh "$bundle"
du -sh "$bundle"
sh pack.sh java "$bundle" run
