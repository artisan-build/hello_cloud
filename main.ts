// Hello from Deno, on Laravel Cloud's Go runtime.
//
// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
// root, so the environment was detected as Go when it was created and Cloud
// starts whatever executable the build command left at `./app`. The build
// command never compiles any Go: it downloads the binary GitHub Actions built
// from this commit with `deno compile`.
//
// `deno compile` welds the Deno runtime, this module and the two raw imports
// below into one self-contained executable, so nothing on Cloud's ephemeral
// filesystem matters once the process is up.

// Raw imports: the bytes land inside the compiled binary, not on disk.
import TEMPLATE from "./shared/page.html" with { type: "text" };
import INDEX_URL from "./shared/index-url.txt" with { type: "text" };
import OG_PNG from "./og.png" with { type: "bytes" };

const LANGUAGE = "Deno";
const BRANCH = "deno";
const REPO_URL = "https://github.com/artisan-build/hello_cloud";

/** Fills the shared template's seven placeholders. */
function page(host: string): string {
  const base = `https://${host}`;
  // replaceAll, not replace: {{LANGUAGE}} appears nine times in the template.
  return TEMPLATE
    .replaceAll("{{LANGUAGE}}", LANGUAGE)
    .replaceAll("{{BRANCH_URL}}", `${REPO_URL}/tree/${BRANCH}`)
    .replaceAll("{{BRANCH}}", BRANCH)
    .replaceAll("{{OG_IMAGE}}", `${base}/og.png`)
    .replaceAll("{{PAGE_URL}}", `${base}/`)
    .replaceAll("{{INDEX_URL}}", INDEX_URL.trim())
    .replaceAll("{{EXTRA}}", "");
}

const port = Number(Deno.env.get("PORT") ?? "3000");

// Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
// network, so bind the dual-stack wildcard.
Deno.serve({ hostname: "::", port }, (req) => {
  const url = new URL(req.url);
  // og:image and og:url have to be absolute, so they are built from the
  // request's Host header with a hard-coded https scheme: Cloud terminates TLS
  // upstream and then sends `X-Forwarded-Proto: http` on an https request, so
  // that header cannot be trusted.
  const host = req.headers.get("host") ?? `localhost:${port}`;

  if (url.pathname === "/og.png") {
    return new Response(OG_PNG, {
      headers: {
        "content-type": "image/png",
        "cache-control": "public, max-age=3600",
      },
    });
  }

  if (url.pathname === "/") {
    return new Response(page(host), {
      headers: { "content-type": "text/html; charset=utf-8" },
    });
  }

  return new Response("not found\n", {
    status: 404,
    headers: { "content-type": "text/plain; charset=utf-8" },
  });
});
