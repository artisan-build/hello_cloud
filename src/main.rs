//! Hello from Rust, on Laravel Cloud's Go runtime.
//!
//! Laravel Cloud runs this binary because the branch carries a `go.mod` at its
//! root, so the environment was detected as Go when it was created and Cloud
//! starts whatever executable the build command left at `./app`. The build
//! command for this environment never compiles any Go: it downloads the binary
//! GitHub Actions built from this commit.
//!
//! Both the shared HTML template and the OG card are compiled in, so nothing on
//! Cloud's ephemeral filesystem matters once the process is up.

use std::net::{Ipv6Addr, SocketAddr};

use axum::{
    extract::Host,
    http::{header, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Router,
};

const LANGUAGE: &str = "Rust";
const BRANCH: &str = "rust";
const REPO_URL: &str = "https://github.com/artisan-build/hello_cloud";

/// The shared template from `main`. Do not fork it per language.
const TEMPLATE: &str = include_str!("../shared/page.html");
/// The index URL, also shared from `main`.
const INDEX_URL: &str = include_str!("../shared/index-url.txt");
/// Written by `go run ./tools/ogen -language Rust -out og.png` before the build.
const OG_PNG: &[u8] = include_bytes!("../og.png");

#[tokio::main]
async fn main() {
    let app = Router::new().route("/", get(page)).route("/og.png", get(og));

    // Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
    // network, so bind the dual-stack wildcard.
    let port: u16 = std::env::var("PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);
    let addr = SocketAddr::from((Ipv6Addr::UNSPECIFIED, port));

    let listener = tokio::net::TcpListener::bind(addr)
        .await
        .unwrap_or_else(|e| panic!("hello_cloud: bind {addr}: {e}"));
    println!("hello_cloud: hello from {LANGUAGE}, serving on {addr}");
    axum::serve(listener, app).await.expect("serve");
}

/// Fills the shared template's seven placeholders.
///
/// `og:image` and `og:url` have to be absolute, so they are built from the
/// request's Host header with a hard-coded https scheme: Cloud terminates TLS
/// upstream and then sends `X-Forwarded-Proto: http` on an https request, so
/// that header cannot be trusted.
async fn page(Host(host): Host) -> Response {
    let base = format!("https://{host}");
    let body = TEMPLATE
        .replace("{{LANGUAGE}}", LANGUAGE)
        .replace("{{BRANCH}}", BRANCH)
        .replace("{{BRANCH_URL}}", &format!("{REPO_URL}/tree/{BRANCH}"))
        .replace("{{OG_IMAGE}}", &format!("{base}/og.png"))
        .replace("{{PAGE_URL}}", &format!("{base}/"))
        .replace("{{INDEX_URL}}", INDEX_URL.trim())
        .replace("{{EXTRA}}", "");

    (
        StatusCode::OK,
        [(
            header::CONTENT_TYPE,
            HeaderValue::from_static("text/html; charset=utf-8"),
        )],
        body,
    )
        .into_response()
}

async fn og() -> Response {
    (
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("image/png"),
            ),
            (
                header::CACHE_CONTROL,
                HeaderValue::from_static("public, max-age=3600"),
            ),
        ],
        OG_PNG,
    )
        .into_response()
}
