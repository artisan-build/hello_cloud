//! Hello from Rust, on Laravel Cloud's native Rust runtime.
//!
//! This branch carries no `go.mod`. Its root is a Cargo workspace, and runtime
//! detection runs per environment from that environment's branch at the moment
//! the environment is created, so this environment came back with Cloud's
//! default Rust build command, `cargo build --release`. Cloud compiles this
//! crate from source on every deploy, copies every executable it finds in
//! `target/release` into `/var/www/bin`, and starts the first one it finds
//! there -- no GitHub Actions asset, no prebuilt binary.
//!
//! The shared HTML template, the shared index URL and the OG card are all
//! compiled in, so nothing on Cloud's ephemeral filesystem matters once the
//! process is up.
//!
//! Every response carries the process's start time and uptime. That is here on
//! purpose: it is how we tell a woken-from-hibernation process (uptime resets)
//! from one that never slept.

use std::net::{Ipv6Addr, SocketAddr};
use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    extract::{Host, State},
    http::{header, HeaderName, HeaderValue, StatusCode},
    response::{IntoResponse, Response},
    routing::get,
    Router,
};

const LANGUAGE: &str = "Rust";
const BRANCH: &str = "rust-native";
const REPO_URL: &str = "https://github.com/artisan-build/hello_cloud";

/// The shared template from `main`. Do not fork it per language.
const TEMPLATE: &str = include_str!("../shared/page.html");
/// The index URL, also shared from `main`.
const INDEX_URL: &str = include_str!("../shared/index-url.txt");
/// Rendered by `go run ./tools/ogen -language Rust -out og.png`. Unlike the
/// Actions-built branches, this one builds on Cloud, where there is no Go
/// toolchain to render the card -- so the card is committed next to the source.
const OG_PNG: &[u8] = include_bytes!("../og.png");

/// When this process started, in both forms a reader might want.
#[derive(Clone, Copy)]
struct Started {
    unix: u64,
    at: Instant,
}

const X_PROCESS_START: HeaderName = HeaderName::from_static("x-process-start");
const X_UPTIME_SECONDS: HeaderName = HeaderName::from_static("x-uptime-seconds");

#[tokio::main]
async fn main() {
    let started = Started {
        unix: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs())
            .unwrap_or(0),
        at: Instant::now(),
    };

    let app = Router::new()
        .route("/", get(page))
        .route("/og.png", get(og))
        .with_state(started);

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
    println!(
        "hello_cloud: hello from {LANGUAGE} (native runtime), pid {}, started {}, serving on {addr}",
        std::process::id(),
        started.unix
    );
    axum::serve(listener, app).await.expect("serve");
}

/// Fills the shared template's seven placeholders.
///
/// `og:image` and `og:url` have to be absolute, so they are built from the
/// request's Host header with a hard-coded https scheme: Cloud terminates TLS
/// upstream and then sends `X-Forwarded-Proto: http` on an https request, so
/// that header cannot be trusted.
async fn page(State(started): State<Started>, Host(host): Host) -> Response {
    let base = format!("https://{host}");
    let body = TEMPLATE
        .replace("{{LANGUAGE}}", LANGUAGE)
        .replace("{{BRANCH}}", BRANCH)
        .replace("{{BRANCH_URL}}", &format!("{REPO_URL}/tree/{BRANCH}"))
        .replace("{{OG_IMAGE}}", &format!("{base}/og.png"))
        .replace("{{PAGE_URL}}", &format!("{base}/"))
        .replace("{{INDEX_URL}}", INDEX_URL.trim())
        .replace("{{EXTRA}}", &extra(started));

    (
        StatusCode::OK,
        [
            (
                header::CONTENT_TYPE,
                HeaderValue::from_static("text/html; charset=utf-8"),
            ),
            (X_PROCESS_START, header_value(started.unix)),
            (X_UPTIME_SECONDS, header_value(uptime(started))),
        ],
        body,
    )
        .into_response()
}

async fn og(State(started): State<Started>) -> Response {
    (
        StatusCode::OK,
        [
            (header::CONTENT_TYPE, HeaderValue::from_static("image/png")),
            (
                header::CACHE_CONTROL,
                HeaderValue::from_static("public, max-age=3600"),
            ),
            (X_PROCESS_START, header_value(started.unix)),
            (X_UPTIME_SECONDS, header_value(uptime(started))),
        ],
        OG_PNG,
    )
        .into_response()
}

fn uptime(started: Started) -> u64 {
    started.at.elapsed().as_secs()
}

fn header_value(n: u64) -> HeaderValue {
    HeaderValue::from_str(&n.to_string()).unwrap_or(HeaderValue::from_static("0"))
}

/// The one block of per-branch copy. The shared template's own paragraph
/// describes the Go-runtime branches, which is every branch but this one, so
/// this section says what actually happens here.
fn extra(started: Started) -> String {
    format!(
        concat!(
            r#"<section class="extra"><h2>Except on this branch</h2>"#,
            r#"<p class="note">There is no <code>go.mod</code> here. The root is a Cargo workspace, "#,
            r#"so Laravel Cloud detected Rust when this environment was created: it compiles the crate "#,
            r#"from source with <code>cargo build --release</code> on every deploy and starts the "#,
            r#"executable that lands in <code>/var/www/bin</code>. Nothing is prebuilt. Everything else "#,
            r#"on the page is the same shared template every language uses.</p>"#,
            r#"<p class="note">This process started at <code>{}</code> (unix) and has been up "#,
            r#"<code>{}s</code>. Both numbers are also on every response, as "#,
            r#"<code>X-Process-Start</code> and <code>X-Uptime-Seconds</code> -- an idle environment "#,
            r#"that hibernates comes back with the uptime reset.</p></section>"#
        ),
        started.unix,
        uptime(started)
    )
}
