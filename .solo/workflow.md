# Workflow: hello_cloud

**A FUN, USELESS DEMO** (Ed, 2026-10-01). One repo, one Laravel Cloud application, one branch (and one Cloud environment) per
language. Each branch serves a static "Hello from {language}" page with a link to its own branch, OG tags and an OG image
("{language} running on Laravel Cloud"), using the **go.mod trick** found in campfire-rust-experiment: a `go.mod` at the repo
root makes Cloud detect the Go runtime when the environment is created, its start command is `./app`, and the build command
(editable via the API) only has to leave an executable at `./app`, whatever language produced it.

## Phase & mode
- phase: toy / demo. No customers, no data.
- default mode: A-autonomous. **Push directly to `main` and to language branches**, no PRs (Ed's call for a toy).
- Cloud: org `org-9e4a1722-9442-404e-abdb-1ca55f845597`. Deploys to THIS project's Cloud application and its environments are
  pre-authorised. Nothing else in the org may be touched.

## Hard gate
- The binary builds for **linux/arm64** (Cloud is Debian 12, aarch64, glibc 2.36). Prefer fully static binaries.
- It serves the page on `$PORT` bound to `[::]` (Cloud's network is IPv6-only internally; the per-instance nginx proxies to port 3000).
- Live check: `curl` the environment URL → 200, the body contains "Hello from {language}", and the og:image URL → 200 image/png.

## Hard rules
- No secrets anywhere. No Cloud ids or URLs need to be secret, but never commit API tokens.
- Never set env vars for Cloud-provisioned resources (there are none here anyway).
- `.cloud/config.json` is committed (brain standing policy).
