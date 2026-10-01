#!/bin/sh
# Builds ./app: a PackageCompiler app bundle, gzipped, appended to the stub.c
# extractor. See stub.c for why ./app has to be a single ELF file.
#
# Run by GitHub Actions inside the image lang.json names, at the repo root, as
# root. Nothing here runs on Laravel Cloud -- Cloud's build command only
# downloads the finished binary.
set -eux

# PackageCompiler shells out to a C compiler and a linker; the julia image has
# neither. apt-get works here (this is the Actions container, where we are
# root) and does not on Cloud.
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential

export JULIA_DEPOT_PATH=/tmp/jdepot

# Pkg.add writes each dependency's real UUID into Project.toml and pins the
# whole resolution in Manifest.toml; neither is committed. Both deps go in one
# call: adding HTTP first makes Julia precompile HelloCloud before Sockets is a
# declared dependency, which logs a loud failure that then resolves itself.
#
# HTTP is pinned to the 1.x line. HTTP 2.8 depends on Reseau, whose __init__
# registers an atexit hook, and PackageCompiler's sysimage build runs that
# package's precompile workload at a point where Julia is already exiting:
# `ERROR: LoadError: cannot register new atexit hook; already exiting.` and the
# sysimage subprocess exits 1. HTTP 1.x has no Reseau and compiles.
julia --project=. -e 'using Pkg; Pkg.add([Pkg.PackageSpec(name="HTTP", version="1"), Pkg.PackageSpec(name="Sockets")]); Pkg.instantiate()'
julia -e 'using Pkg; Pkg.add("PackageCompiler")'

# create_app compiles the package into bundle/: bin/HelloCloud, a sysimage with
# HelloCloud and HTTP in it, libjulia and its shared libraries.
#
# incremental=true, which is NOT the small option. A non-incremental sysimage
# is built by a julia subprocess with --pkgimages=no against a bare base image,
# and HTTP's dependency OpenSSL.jl calls into its JLL's shared library while it
# loads: `could not load symbol "OpenSSL_version_num" ... undefined symbol`,
# and the build exits 1. Keeping the base sysimage keeps the JLL loading
# machinery that the call needs.
julia -e '
    using PackageCompiler
    create_app(".", "bundle";
        executables = ["HelloCloud" => "julia_main"],
        force = true,
        incremental = true,
        filter_stdlibs = false,
        include_lazy_artifacts = false)
'
du -sh bundle

# One gzipped tar of the bundle's contents (no leading bundle/ component, so
# stub.c's ROOT is the bundle root).
tar -czf payload.tgz -C bundle .
ls -l payload.tgz

# stub.c is told the payload size at compile time, so ./app needs no trailer
# and the build needs no tool the julia image lacks (it has no python3).
SIZE=$(wc -c < payload.tgz)
gcc -O2 -Wall -Wextra -DPAYLOAD_LEN="$SIZE" -o stub stub.c

# ./app is the stub with the tarball appended; `file` still calls it an ELF,
# which is what CI checks.
cat stub payload.tgz > app
chmod +x app
ls -l app
