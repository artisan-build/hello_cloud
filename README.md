# hello_cloud

**Laravel Cloud will run any Linux binary you like.** 38 branches, 38 Laravel
Cloud environments, 38 native `linux/arm64` binaries, all serving the same
"Hello from {language}" page. One of them is written in aarch64 assembly. One
of them is COBOL. None of them is a container image.

An experiment from the [Scalpels Lab](https://scalpels.app/lab). Not affiliated
with Laravel — we're just having fun.

## The trick

Laravel Cloud picks an environment's runtime by looking at that environment's
branch, and it looks **once, when the environment is created**. A `go.mod` at
the branch root means the environment is detected as **Go**, which gets it two
things:

1. A start command of **`./app`** — a file path, not a language invocation. It
   is fixed when the environment is created and only the dashboard can change
   it afterwards, so getting it right at create time matters.
2. A **build command you can edit** over the API
   (`PATCH /api/environments/{id}` with `build_command`), pre-filled with
   `go build -trimpath -ldflags="-s -w" -o app .`.

The build command's only real job is to leave an executable at `./app`. **It
does not have to compile anything, and it does not have to be Go.** On every
branch here except `main`, the `go.mod` is the only Go in the repository, no
`go build` runs anywhere in the pipeline, and the thing Cloud starts was
compiled by GHC, or SBCL, or GnuCOBOL, or `as`.

## The pipeline

```
main ───── the index, the shared template, the OG generator, the CI workflow, tools/sfx
 ├── rust ──── lang.json + Cargo.toml + src/main.rs
 ├── cobol ─── lang.json + hello.cob
 ├── forth ─── lang.json + hello.fs
 └── …         35 more, each branched from main
```

**`main` is the honest control.** It is a real Go module, Cloud compiles and
runs it natively with no trick involved, and it serves the index below.

**Binaries are built in GitHub Actions, not on Cloud.** Every language branch
carries one `lang.json`:

```json
{
  "language": "Zig",
  "slug": "zig",
  "framework": "std.http.Server",
  "image": "debian:bookworm-slim",
  "build": "… leave an executable at ./app …"
}
```

`.github/workflows/build.yml` reads it, generates the branch's OG card with
`main`'s generator, runs `build` inside `image` on a free arm64 runner,
**smoke-tests the result on `debian:12` — the same OS image Cloud runs** — and
publishes `app`, `app.sha256` and `VERSION` to a rolling release tagged
`bin-<slug>`. Adding a language needs no CI changes: the toolchain is a
container image named in data.

**Cloud's build command is the same string on 36 of the 38:**

```
sh .cloud/fetch-binary
```

It reads the branch from `LARAVEL_CLOUD_ENV_BRANCH`, waits (up to 10 minutes,
inside Cloud's 15-minute cap) for the release asset whose `VERSION` equals
`LARAVEL_CLOUD_COMMIT_SHA`, checks its SHA-256 and leaves it at `./app`. Losing
that race on purpose is what makes push-to-deploy safe: one `git push` starts
the Actions build and the Cloud deploy together, and the Cloud build simply
waits for its binary. **No Cloud API token exists anywhere in CI.**

**The page and the card are shared, and compiled in.** `shared/page.html` is
one template with seven placeholders; `internal/ogen` renders the 1200×630 OG
card. Each binary embeds both, so nothing on Cloud's ephemeral filesystem
matters once the process is up.

## Every language

| Language | Serving with | Live | Branch |
|---|---|---|---|
| Go | net/http (stdlib) | [hello-cloud-production-kgvqnk.laravel.cloud](https://hello-cloud-production-kgvqnk.laravel.cloud) | [`main`](https://github.com/artisan-build/hello_cloud/tree/main) |
| Rust | axum | [hello-cloud-rust-lxx3gx.laravel.cloud](https://hello-cloud-rust-lxx3gx.laravel.cloud) | [`rust`](https://github.com/artisan-build/hello_cloud/tree/rust) |
| Zig | std.http.Server | [hello-cloud-zig-tifwpj.laravel.cloud](https://hello-cloud-zig-tifwpj.laravel.cloud) | [`zig`](https://github.com/artisan-build/hello_cloud/tree/zig) |
| aarch64 Assembly | raw Linux syscalls | [hello-cloud-asm-arm64-savvq0.laravel.cloud](https://hello-cloud-asm-arm64-savvq0.laravel.cloud) | [`asm-arm64`](https://github.com/artisan-build/hello_cloud/tree/asm-arm64) |
| Ada | GNAT.Sockets | [hello-cloud-ada-q6sndq.laravel.cloud](https://hello-cloud-ada-q6sndq.laravel.cloud) | [`ada`](https://github.com/artisan-build/hello_cloud/tree/ada) |
| Bun | Bun.serve | [hello-cloud-bun-v5rrkf.laravel.cloud](https://hello-cloud-bun-v5rrkf.laravel.cloud) | [`bun`](https://github.com/artisan-build/hello_cloud/tree/bun) |
| C | hand-rolled BSD sockets | [hello-cloud-c-ik7cwe.laravel.cloud](https://hello-cloud-c-ik7cwe.laravel.cloud) | [`c`](https://github.com/artisan-build/hello_cloud/tree/c) |
| C# | ASP.NET Core minimal API (NativeAOT) | [hello-cloud-csharp-tt8sda.laravel.cloud](https://hello-cloud-csharp-tt8sda.laravel.cloud) | [`csharp`](https://github.com/artisan-build/hello_cloud/tree/csharp) |
| C++ | cpp-httplib | [hello-cloud-cpp-fg4hgt.laravel.cloud](https://hello-cloud-cpp-fg4hgt.laravel.cloud) | [`cpp`](https://github.com/artisan-build/hello_cloud/tree/cpp) |
| Clojure | Ring handler on http-kit | [hello-cloud-clojure-l5sevq.laravel.cloud](https://hello-cloud-clojure-l5sevq.laravel.cloud) | [`clojure`](https://github.com/artisan-build/hello_cloud/tree/clojure) |
| COBOL | GnuCOBOL CALL to libc sockets | [hello-cloud-cobol-nmq64r.laravel.cloud](https://hello-cloud-cobol-nmq64r.laravel.cloud) | [`cobol`](https://github.com/artisan-build/hello_cloud/tree/cobol) |
| Common Lisp | Hunchentoot | [hello-cloud-common-lisp-bghwqf.laravel.cloud](https://hello-cloud-common-lisp-bghwqf.laravel.cloud) | [`common-lisp`](https://github.com/artisan-build/hello_cloud/tree/common-lisp) |
| Crystal | Kemal | [hello-cloud-crystal-tk3ome.laravel.cloud](https://hello-cloud-crystal-tk3ome.laravel.cloud) | [`crystal`](https://github.com/artisan-build/hello_cloud/tree/crystal) |
| D | std.socket | [hello-cloud-d-bn0fog.laravel.cloud](https://hello-cloud-d-bn0fog.laravel.cloud) | [`d`](https://github.com/artisan-build/hello_cloud/tree/d) |
| Dart | shelf | [hello-cloud-dart-mbdyzc.laravel.cloud](https://hello-cloud-dart-mbdyzc.laravel.cloud) | [`dart`](https://github.com/artisan-build/hello_cloud/tree/dart) |
| Deno | Deno.serve (std http) | [hello-cloud-deno-4lzczq.laravel.cloud](https://hello-cloud-deno-4lzczq.laravel.cloud) | [`deno`](https://github.com/artisan-build/hello_cloud/tree/deno) |
| Elixir | Plug + Bandit | [hello-cloud-elixir-tirkx0.laravel.cloud](https://hello-cloud-elixir-tirkx0.laravel.cloud) | [`elixir`](https://github.com/artisan-build/hello_cloud/tree/elixir) |
| Erlang | cowboy | [hello-cloud-erlang-thinc8.laravel.cloud](https://hello-cloud-erlang-thinc8.laravel.cloud) | [`erlang`](https://github.com/artisan-build/hello_cloud/tree/erlang) |
| F# | ASP.NET Core minimal API | [hello-cloud-fsharp-inhwxs.laravel.cloud](https://hello-cloud-fsharp-inhwxs.laravel.cloud) | [`fsharp`](https://github.com/artisan-build/hello_cloud/tree/fsharp) |
| Forth | gforth 0.7.3 + unix/socket.fs | [hello-cloud-forth-4fuypl.laravel.cloud](https://hello-cloud-forth-4fuypl.laravel.cloud) | [`forth`](https://github.com/artisan-build/hello_cloud/tree/forth) |
| Fortran | ISO_C_BINDING sockets | [hello-cloud-fortran-4fxtvw.laravel.cloud](https://hello-cloud-fortran-4fxtvw.laravel.cloud) | [`fortran`](https://github.com/artisan-build/hello_cloud/tree/fortran) |
| Gleam | wisp + mist | [hello-cloud-gleam-y4r08q.laravel.cloud](https://hello-cloud-gleam-y4r08q.laravel.cloud) | [`gleam`](https://github.com/artisan-build/hello_cloud/tree/gleam) |
| Haskell | Scotty | [hello-cloud-haskell-sq2axf.laravel.cloud](https://hello-cloud-haskell-sq2axf.laravel.cloud) | [`haskell`](https://github.com/artisan-build/hello_cloud/tree/haskell) |
| Java | Javalin 6 (Jetty) | [hello-cloud-java-ulbhx4.laravel.cloud](https://hello-cloud-java-ulbhx4.laravel.cloud) | [`java`](https://github.com/artisan-build/hello_cloud/tree/java) |
| Julia | HTTP.jl (PackageCompiler) | [hello-cloud-julia-7wbhxl.laravel.cloud](https://hello-cloud-julia-7wbhxl.laravel.cloud) | [`julia`](https://github.com/artisan-build/hello_cloud/tree/julia) |
| Kotlin | Ktor 3 (CIO engine) | [hello-cloud-kotlin-avybeg.laravel.cloud](https://hello-cloud-kotlin-avybeg.laravel.cloud) | [`kotlin`](https://github.com/artisan-build/hello_cloud/tree/kotlin) |
| Lua | Lua 5.4 in a static C host | [hello-cloud-lua-sxhmb8.laravel.cloud](https://hello-cloud-lua-sxhmb8.laravel.cloud) | [`lua`](https://github.com/artisan-build/hello_cloud/tree/lua) |
| Nim | std/asynchttpserver | [hello-cloud-nim-oipbqf.laravel.cloud](https://hello-cloud-nim-oipbqf.laravel.cloud) | [`nim`](https://github.com/artisan-build/hello_cloud/tree/nim) |
| OCaml | Dream | [hello-cloud-ocaml-fqvebe.laravel.cloud](https://hello-cloud-ocaml-fqvebe.laravel.cloud) | [`ocaml`](https://github.com/artisan-build/hello_cloud/tree/ocaml) |
| Odin | core:net | [hello-cloud-odin-uhiugx.laravel.cloud](https://hello-cloud-odin-uhiugx.laravel.cloud) | [`odin`](https://github.com/artisan-build/hello_cloud/tree/odin) |
| Pascal | RTL Sockets unit | [hello-cloud-pascal-ydkgnu.laravel.cloud](https://hello-cloud-pascal-ydkgnu.laravel.cloud) | [`pascal`](https://github.com/artisan-build/hello_cloud/tree/pascal) |
| Perl | Mojolicious (PAR::Packer) | [hello-cloud-perl-jqdjyt.laravel.cloud](https://hello-cloud-perl-jqdjyt.laravel.cloud) | [`perl`](https://github.com/artisan-build/hello_cloud/tree/perl) |
| Racket | web-server | [hello-cloud-racket-0nx5en.laravel.cloud](https://hello-cloud-racket-0nx5en.laravel.cloud) | [`racket`](https://github.com/artisan-build/hello_cloud/tree/racket) |
| Roc | basic-webserver | [hello-cloud-roc-kwilzh.laravel.cloud](https://hello-cloud-roc-kwilzh.laravel.cloud) | [`roc`](https://github.com/artisan-build/hello_cloud/tree/roc) |
| Rust | axum (native Rust runtime) | [hello-cloud-rust-native-cfqbxj.laravel.cloud](https://hello-cloud-rust-native-cfqbxj.laravel.cloud) | [`rust-native`](https://github.com/artisan-build/hello_cloud/tree/rust-native) |
| Scala | cask (Undertow) | [hello-cloud-scala-sizv0v.laravel.cloud](https://hello-cloud-scala-sizv0v.laravel.cloud) | [`scala`](https://github.com/artisan-build/hello_cloud/tree/scala) |
| Swift | Hummingbird | [hello-cloud-swift-k4nelj.laravel.cloud](https://hello-cloud-swift-k4nelj.laravel.cloud) | [`swift`](https://github.com/artisan-build/hello_cloud/tree/swift) |
| V | veb | [hello-cloud-v-27locg.laravel.cloud](https://hello-cloud-v-27locg.laravel.cloud) | [`v`](https://github.com/artisan-build/hello_cloud/tree/v) |

`main` and `rust-native` are the two exceptions: Cloud compiles both of them
itself, from Go and from Cargo. They are the controls.

## What we learned

Thirty-eight languages is a slow, expensive way to read the runtime's mind, and
it worked. In rough order of how much time each one cost:

**`go.mod` alone is enough.** No Go source, no shim, no `package main`. Cloud's
detector wants the manifest; the Go build step is just a build command, and a
build command is a string. We shipped a one-line `cmd/shim` fallback in case
that ever stops being true, and never needed it.

**Detection is per environment, and it only runs once.** The application is
created against the default branch, so `POST /api/applications` ignores the
`branch` you send it. Each later `POST /applications/{app}/environments` with
`{"name": …, "branch": …}` detects from the branch you name, and nothing
re-detects afterwards. Get `go.mod` onto the branch *before* the environment
exists.

**A runtime that ships as a directory still fits.** An OTP release, a jlink
image, a Forth engine plus its `.fi` image and library tree: `tools/sfx` packs
any of them into one `linux/arm64` ELF by appending a gzipped tar to a static C
launcher with a trailer that says where it starts. Appending bytes to an ELF
leaves it a valid ELF, so `file` is satisfied and nothing in the shared
pipeline has to learn a new shape. Two of our six phase-2 batches invented this
independently on the same night, which is usually a sign it is the answer.

**`RLIMIT_NOFILE` is 1,073,741,816, and it kills VMs.** This one cost the most
and generalises the furthest. Cloud hands the app process a soft file-descriptor
limit of about 1.07 billion. Any runtime that sizes a table from it — the
BEAM's port table is the one we caught — tries to allocate on the order of a
gigabyte before printing its first line, and the cgroup kills it. Cloud reports
*"your application is crashing because it ran out of memory"*, and it is wrong:
we failed identically at 256 MB, 512 MB and 1 GB. The fix is one line, needs no
privileges, and takes the process from OOM-killed to 76 MiB resident:

```sh
ulimit -n 65536
```

Reproduce it anywhere with `docker run --memory=256m --ulimit nofile=1073741816`.
It is in `tools/sfx`'s launcher now, so every bundle gets it for free.

**An unsupported framework manifest doesn't fall through — it refuses.** A
`pom.xml` at the branch root does not lose detection to the `go.mod` beside it.
Cloud declines to create the environment at all:

> The [java] branch of the repository [artisan-build/hello_cloud] uses an
> unsupported framework. Only Laravel, Symfony, PHP, Express, Hono, Nuxt,
> Next.js, TanStack Start, Elysia, NestJS, JavaScript, Go, Ruby, Rails, Django,
> FastAPI, Flask, Python, Rust, Axum, Rocket, Actix Web, and Warp applications
> are supported.

That error message is, as far as we can tell, the only place the supported list
is written down. The JVM branches keep their `pom.xml` one directory down.
`mix.exs` and `rebar.config` do not trip it.

**Hibernation is a frozen process, not a restart.** Scale-to-zero works, and
we spent a day convinced it did not, because a wake is a sub-second thaw: no
boot line, no cold first response, nothing in the logs, and `env status` still
says `running` while the environment is asleep. The only honest signal is
`GET /api/environments/{id}/metrics` → `replica_count`, which reads 1 awake and
0 asleep. Measured duty cycle on an idle toy: 34.6%. One open WebSocket holds
it awake indefinitely; it sleeps five minutes after the socket closes.

**`X-Forwarded-Proto` says `http` on an HTTPS request.** Every absolute URL on
these pages is built from `Host` with the scheme hard-coded, because the header
that exists to tell you the scheme tells you the wrong one. (`Cf-Visitor` has
it right.)

**The edge strips `Upgrade` and `Connection`** from WebSocket handshakes before
the per-instance nginx sees them, so a normal HTTP server refuses to upgrade.
Irrelevant for a static page; fatal if you were hoping to port something
realtime.

**`Accept: application/vnd.api+json` or nothing.** Send the Cloud API
`Accept: application/json` and every request comes back `401 Unauthenticated`
with a perfectly good token. It looks exactly like a credentials problem and it
is a content-negotiation problem. This cost an hour before anyone suspected the
header.

## Caveats

- **`linux/arm64`, Debian 12 (bookworm), glibc 2.36, running as `www-data`.**
  Build in a bookworm container or ship a static binary.
- **Plain HTTP on `$PORT`, bound to `[::]`.** Cloud's per-instance nginx proxies
  to `127.0.0.1:$PORT` on an IPv6-only network, so bind the dual-stack IPv6
  wildcard rather than `0.0.0.0`. TLS terminates upstream.
- **The filesystem is ephemeral** — it resets on every deploy, reboot and
  migration. Embed what you serve.
- **15-minute build cap, no `apt` in Cloud's build step** (it does not run as
  root), and that build image is Go 1.24 with `GOTOOLCHAIN=local`. All of the
  `apt-get` in these branches happens in GitHub Actions, inside the toolchain
  container, where you are root.
- **It is an unofficial trick.** Nothing documents it and Laravel could close it
  in any release. If you want this officially, ask them for a "binary" runtime
  or a repository Dockerfile.

## Adding a 39th

1. Branch from `main` (that is what puts `go.mod`, the template, `tools/sfx`
   and the workflow on your branch).
2. Add `lang.json` and your source. Serve the template at `/` and the embedded
   PNG at `/og.png`; bind `[::]` on `$PORT`.
3. Push. Watch the `build` workflow go green.
4. Create the Cloud environment on the branch, swap its build command to
   `sh .cloud/fetch-binary`, shrink the instance, deploy.
5. Append a row to `shared/languages.tsv` and to the table above.

The copy-pasteable version, with every trap above spelled out, lives in the
lab's notes: `brain/projects/hello_cloud/recipe-add-a-language.md`.

## Credit

The trick was found by the
[campfire-rust-experiment](https://github.com/artisan-build/campfire-rust-experiment),
which needed to get a Rust build of Basecamp's Campfire onto Cloud and noticed
that the Go runtime's start command is just a path. That experiment also found
that Cloud has an **undocumented Rust runtime**, detected the same way from a
Cargo workspace at the branch root — which is why `rust-native` is here, and
why "Cloud has no runtime for X" is a claim worth not making.
