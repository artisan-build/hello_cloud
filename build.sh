#!/bin/sh
# Builds ./app for the scala branch, inside the image lang.json names.
#
# The Maven project lives in jvm/, not at the branch root: Cloud reads the root
# to pick a runtime and REFUSES a branch whose root has a pom.xml ("uses an
# unsupported framework"). One directory down, the root is just main's go.mod.
#
# debian:bookworm-slim rather than a JDK image on purpose: Cloud's runtime is
# Debian 12, and vendor-libs.sh copies libraries out of THIS image into the
# bundle, so the build image's glibc has to be the runtime's. Debian's own
# openjdk-17 and maven are used for exactly that reason; the Scala 3 compiler
# comes from Maven Central as a plugin, so no extra toolchain download.
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

mvn -q -B -f jvm/pom.xml -Dmaven.repo.local="$PWD/target/m2" package

bundle=target/bundle
rm -rf "$bundle"
mkdir -p "$bundle"
cp target/maven/app.jar "$bundle/app.jar"

# jdeps works out which platform modules the shaded jar actually touches, so
# the runtime image stays small without a hand-maintained module list.
# jdeps gives up on a shaded jar whose pieces carry module-info files that
# reference each other ("Module org.slf4j not found, required by
# org.slf4j.simple"), so its answer is a hint, not a requirement.
mods=$("$JAVA_HOME/bin/jdeps" --ignore-missing-deps --print-module-deps \
        --multi-release 17 "$bundle/app.jar" 2>/dev/null || true)
[ -n "$mods" ] || mods=java.base
echo "jdeps modules: $mods"
"$JAVA_HOME/bin/jlink" \
    --add-modules "$mods,jdk.unsupported,java.management,java.logging,java.naming,jdk.net" \
    --no-header-files --no-man-pages --strip-debug --compress=2 \
    --output "$bundle/jre"

install -m 755 run.sh "$bundle/run"
sh vendor-libs.sh "$bundle"
du -sh "$bundle"
sh pack.sh scala "$bundle" run
