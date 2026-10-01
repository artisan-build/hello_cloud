#!/bin/sh
# Builds ./app for the clojure branch, inside the image lang.json names.
#
# Maven resolves the dependency jars and nothing more: Clojure compiles its own
# source at startup, so the bundle carries the jars, the .clj source and the
# three embedded files on the classpath. No uberjar, no AOT, no Clojure build
# tool.
#
# The Maven project lives in jvm/, not at the branch root: Cloud reads the root
# to pick a runtime and REFUSES a branch whose root has a pom.xml ("uses an
# unsupported framework"). One directory down, the root is just main's go.mod.
#
# debian:bookworm-slim rather than a JDK image on purpose: Cloud's runtime is
# Debian 12, and vendor-libs.sh copies libraries out of THIS image into the
# bundle, so the build image's glibc has to be the runtime's.
#
# The product is a DIRECTORY, so it is packed into a single self-extracting
# linux/arm64 ELF; see bootstrap.c.
set -eux

apt-get update -qq
DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends \
    openjdk-17-jdk-headless maven gcc libc6-dev ca-certificates >/dev/null

JAVA_HOME=$(dirname "$(dirname "$(readlink -f "$(command -v javac)")")")
export JAVA_HOME
"$JAVA_HOME/bin/java" -version

bundle=target/bundle
rm -rf "$bundle"
mkdir -p "$bundle/lib" "$bundle/clj"

mvn -q -B -f jvm/pom.xml -Dmaven.repo.local="$PWD/target/m2" \
    dependency:copy-dependencies -DoutputDirectory="$PWD/$bundle/lib" \
    -DincludeScope=runtime
ls -l "$bundle/lib"

# Source and the three embedded files, all on one classpath root.
cp -R jvm/src/main/clojure/. "$bundle/clj/"
cp shared/page.html shared/index-url.txt og.png "$bundle/clj/"

# jdeps over the dependency jars; its answer is a hint, with java.base as the
# floor, because it gives up on jars carrying module-info files that reference
# each other.
mods=$("$JAVA_HOME/bin/jdeps" --ignore-missing-deps --print-module-deps \
        --multi-release 17 "$bundle"/lib/*.jar 2>/dev/null || true)
[ -n "$mods" ] || mods=java.base
echo "jdeps modules: $mods"
"$JAVA_HOME/bin/jlink" \
    --add-modules "$mods,jdk.unsupported,java.management,java.logging,java.naming,jdk.net,java.sql" \
    --no-header-files --no-man-pages --strip-debug --compress=2 \
    --output "$bundle/jre"

install -m 755 run.sh "$bundle/run"
sh vendor-libs.sh "$bundle"
du -sh "$bundle"
sh pack.sh clojure "$bundle" run
