# `tools/sfx` — shipping a runtime as one ELF

The pipeline moves exactly one release asset, named `app`, and
`.github/workflows/build.yml` checks that it is a `linux/arm64` ELF before it
publishes it. Most languages compile to one of those and need nothing here.

Some do not. A language that carries its own runtime builds a **directory** —
an OTP release, a jlink image plus a jar, a Forth engine plus its `.fi` image
and library tree. Two phase-2 batches independently arrived at the same answer,
and this is it, deduplicated:

```
app  =  [ a static C launcher ][ bundle.tar.gz ][ 24-byte magic ][ 16-digit offset ]
```

Appending bytes to an ELF leaves it a valid, runnable ELF — the program headers
describe what the loader maps, and it ignores the rest — so `file app` still
says `ELF 64-bit LSB ... ARM aarch64` and CI is satisfied without learning
anything new. **No shared file changes.** At startup the launcher reads its own
`/proc/self/exe`, streams the tail through `tar -xz`, and `execv`s the bundle's
entry script.

## Using it

In your branch's `lang.json` `build`, after your toolchain has produced the
bundle directory:

```sh
sh tools/sfx/vendor-libs.sh bundle          # optional; see below
sh tools/sfx/pack.sh <slug> bundle run      # leaves ./app
```

`bundle/run` is your entry script. It is exec'd with `SFX_ROOT` set to the
unpack directory, and `$(dirname "$0")` is that directory too:

```sh
#!/bin/sh
set -e
d=$(cd "$(dirname "$0")" && pwd)
LD_LIBRARY_PATH="$d/native${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
export LD_LIBRARY_PATH
exec "$d/bin/your-server"
```

`pack.sh` must run **inside the branch's build container**, because `cc -static`
has to produce an aarch64 binary.

## The three things that are load-bearing

1. **The launcher lowers `RLIMIT_NOFILE` to 65536 before exec.** Laravel Cloud
   hands the app process a soft fd limit of **1,073,741,816**. Any runtime that
   sizes a table from the fd limit — the BEAM's port table is the one we
   measured — tries to allocate on the order of a gigabyte and is OOM-killed by
   the cgroup *before printing a single line*, at **any** instance size. Cloud
   reports "your application ran out of memory", and adding memory never helps.
   Reproduced exactly with `docker run --memory=256m --ulimit nofile=1073741816`,
   and fixed by nothing more than `ulimit -n 65536`. Doing it in the launcher
   means every bundle gets it; `SFX_KEEP_NOFILE=1` opts out. If your entry point
   is a shell script, `ulimit -n 65536 2>/dev/null || true` is the same fix.
2. **The launcher is `-static`.** Nothing about the host's glibc can break the
   one thing that has to run first.
3. **It unpacks beside `./app`, not into `/tmp`.** On many container hosts
   `/tmp` is a tmpfs, and every byte of a 60 MB bundle would be charged to a
   256 MB instance. `SFX_DIR` overrides; `/tmp` is the fallback when the
   executable's own directory is not writable.

`vendor-libs.sh` copies into `bundle/native` every shared library the bundle
needs that **Debian 12's base image does not have** — Cloud runs plain
`debian:12`, which is far less than any toolchain image. It skips the glibc set
(both ends are bookworm; a second `ld.so` is how you get a loader mismatch) and
anything already inside the bundle.

## Testing it before you push

```sh
docker run -d --name smoke --platform linux/arm64 -p 3100:3000 \
  -e PORT=3000 --memory=256m --ulimit nofile=1073741816 \
  -v "$PWD/app":/srv/app:ro debian:12 /srv/app
```

`--ulimit nofile=1073741816` is the part people skip, and it is the part that
reproduces Cloud. Mount the binary somewhere writable-adjacent (`/srv`, not
`/`) so the launcher can unpack beside it rather than falling back to `/tmp`.

## Not a migration

The `elixir`, `erlang`, `java`, `kotlin`, `scala`, `clojure`, `ocaml`, `racket`,
`roc` and `gleam` branches each carry their own copy of an earlier version of
this. They work; they are left alone. This is the path for the **next** one.
