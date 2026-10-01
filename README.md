# hello_cloud

**Laravel Cloud will run any Linux binary you like.** One branch per language,
one Laravel Cloud environment per branch, each serving a static
"Hello from {language}" page from a native `linux/arm64` binary.

| Language | Serving with | Live | Branch |
|---|---|---|---|
| Go | `net/http` (stdlib) | [hello-cloud-production-kgvqnk.laravel.cloud](https://hello-cloud-production-kgvqnk.laravel.cloud) | [`main`](https://github.com/artisan-build/hello_cloud/tree/main) |
| Rust | axum | [hello-cloud-rust-lxx3gx.laravel.cloud](https://hello-cloud-rust-lxx3gx.laravel.cloud) | [`rust`](https://github.com/artisan-build/hello_cloud/tree/rust) |
| Zig | `std.http.Server` | [hello-cloud-zig-tifwpj.laravel.cloud](https://hello-cloud-zig-tifwpj.laravel.cloud) | [`zig`](https://github.com/artisan-build/hello_cloud/tree/zig) |

An experiment from the [Scalpels Lab](https://scalpels.app/lab). Not affiliated
with Laravel — we're just having fun.

## The trick

Laravel Cloud picks an environment's runtime by looking at that environment's
branch, and it looks **once, when the environment is created**. A `go.mod` at the
branch root means the environment is detected as **Go**, which gets it two
things:

1. A start command of **`./app`** — a file path, not a language invocation. It is
   fixed when the environment is created and only the dashboard can change it
   afterwards, so getting it at create time matters.
2. A **build command you can edit** over the API
   (`PATCH /api/environments/{id}` with `build_command`), pre-filled with
   `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o app .`.

The build command's only real job is to leave an executable at `./app`. **It does
not have to compile anything, and it does not have to be Go.** Measured on this
repo: with a build command of `sh .cloud/fetch-binary`, which does nothing but
download a prebuilt Rust binary and `chmod +x app`, the deploy succeeds and
Cloud serves the binary. No `go build` runs anywhere in the pipeline. A `go.mod`
is the only Go in the repository for every branch except `main`.

Two API details that cost real time to find:

- **`POST /api/applications` ignores `branch`.** The application is created
  against the repository's default branch, so the default environment is
  detected from `main`. You then create one environment per language with
  `POST /api/applications/{app}/environments` `{"name": …, "branch": …}`, and
  *that* call detects from the branch you name.
- **Every branch must have `go.mod` at its root before its environment is
  created.** Detection does not run again later.

## How this repo uses it

```
main ────────── the index, the shared template, the OG generator, the CI workflow
 ├── rust ───── lang.json + Cargo.toml + src/main.rs
 ├── zig ────── lang.json + main.zig
 └── …          one branch per language, each branched from main
```

**`main` is the honest control.** It is a real Go module, so Cloud compiles and
runs it natively with no trick involved, and it serves the index of every
language.

**Binaries are built in GitHub Actions, not on Cloud.** Every language branch
carries a `lang.json`:

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
`main`'s generator, runs `build` inside `image` on a free arm64 runner, **smoke-
tests the result on `debian:12` — the same OS image Cloud runs** — and publishes
`app`, `app.sha256` and `VERSION` as assets of a rolling release tagged
`bin-<slug>`. Adding a language needs no CI changes: the toolchain is a container
image named in data.

**Cloud's build command is the same string on every language environment:**

```
sh .cloud/fetch-binary
```

`.cloud/fetch-binary` reads the branch from `LARAVEL_CLOUD_ENV_BRANCH`, waits
(up to 10 minutes, inside Cloud's 15-minute cap) for the release asset whose
`VERSION` equals `LARAVEL_CLOUD_COMMIT_SHA`, checks its SHA-256 and leaves it at
`./app`. Losing that race on purpose is what makes push-to-deploy safe: a single
`git push` starts the Actions build and the Cloud deploy at the same time, and
the Cloud build simply waits for its binary. CI uploads `VERSION` in a second,
later call so that a matching `VERSION` really does mean the binary is already
there. **No Cloud API token is needed anywhere in CI.**

**The page and the card are shared, and compiled in.** `shared/page.html` is one
template with seven placeholders (`{{LANGUAGE}}`, `{{BRANCH}}`, `{{BRANCH_URL}}`,
`{{OG_IMAGE}}`, `{{PAGE_URL}}`, `{{INDEX_URL}}`, `{{EXTRA}}`); `internal/ogen`
renders the 1200×630 OG card. Each language's binary embeds the template and the
PNG, so nothing on Cloud's ephemeral filesystem matters once the process is up.
`og:image` and `og:url` are built from the request's `Host` header with an
https scheme hard-coded — see the caveats.

## Adding a language

1. Branch from `main` (this is what puts `go.mod`, the template and the workflow
   on your branch).
2. Add `lang.json` and your source. Serve the template at `/` and the embedded
   PNG at `/og.png`; bind `[::]` on `$PORT`.
3. Push. Watch the `build` workflow go green.
4. Create the Cloud environment on the branch, set its build command to
   `sh .cloud/fetch-binary`, shrink its instance, deploy.
5. Append a row to `shared/languages.tsv` and a row to the table above.

The full, copy-pasteable version lives in the lab's notes:
`brain/projects/hello_cloud/recipe-add-a-language.md`.

## Caveats

- **`linux/arm64`, Debian 12 (bookworm), glibc 2.36, running as `www-data`.**
  Build in a bookworm container or ship a static binary. Anything linked against
  a newer glibc will not load.
- **Plain HTTP on `$PORT`, bound to `[::]`.** Cloud's per-instance nginx proxies
  to `127.0.0.1:$PORT` on an IPv6-only network, so bind the IPv6 wildcard
  dual-stack rather than `0.0.0.0`. TLS terminates upstream.
- **`X-Forwarded-Proto` lies.** It says `http` on an https request (`Cf-Visitor`
  says `https`). Any absolute URL you build from it will be wrong, which is why
  the scheme is hard-coded here.
- **The edge strips `Upgrade` and `Connection` from WebSocket handshakes**, so a
  normal HTTP server will refuse to upgrade. Irrelevant for a static page;
  fatal if you were hoping to port something realtime.
- **The filesystem is ephemeral** — it resets on every deploy, reboot and
  migration. Embed what you serve.
- **15-minute build cap, no `apt` in the build image** (the build does not run as
  root), and the build image is Go 1.24.13 with `GOTOOLCHAIN=local`, so a `go`
  directive newer than that fails.
- **It is an unofficial trick.** Nothing documents it and Laravel could close it
  in any release. If you want this officially, ask them for a "binary" runtime or
  a repository Dockerfile.

## Credit

The trick was found by the
[campfire-rust-experiment](https://github.com/artisan-build/campfire-rust-experiment),
which needed to get a Rust build of Basecamp's Campfire onto Cloud and noticed
that the Go runtime's start command is just a path. That experiment also found
that Cloud has an **undocumented Rust runtime**, detected the same way from a
Cargo workspace at the branch root — so "Cloud has no runtime for X" is a claim
worth not making.
