// Hello from Swift, on Laravel Cloud's Go runtime.
//
// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
// root, so the environment was detected as Go when it was created and Cloud
// starts whatever executable the build command left at ./app. Nothing Go is
// compiled: the build command downloads the binary GitHub Actions built from
// this commit.
//
// The binary is built with `--static-swift-stdlib`, so the Swift runtime is
// inside it and Debian 12 needs no Swift installed. The shared template, the
// shared index URL and the OG card are string literals in the generated
// Payload.swift, so nothing is read from Cloud's ephemeral filesystem.
//
// Nothing here imports Foundation. On Linux that is a deliberate choice: it
// keeps libcurl and libxml2 out of the link, and those are shared libraries a
// bare Debian 12 would have to provide.
import Glibc
import Hummingbird
import NIOCore

let language = "Swift"
let branch = "swift"
let repoURL = "https://github.com/artisan-build/hello_cloud"

let ogBytes = Base64.decode(ogPNGBase64)
let templateBytes = Array(template.utf8)

/// Fills the shared template's seven `{{PLACEHOLDER}}` slots in one pass.
///
/// Written against UTF-8 bytes rather than `replacingOccurrences(of:with:)`,
/// which lives in Foundation.
func renderPage(host rawHost: String) -> String {
    let host = rawHost.isEmpty
        ? "localhost"
        : String(rawHost.filter { $0.isLetter || $0.isNumber || "-.:[]".contains($0) })
    let base = "https://\(host)"
    let values: [String: String] = [
        "LANGUAGE": language,
        "BRANCH": branch,
        "BRANCH_URL": "\(repoURL)/tree/\(branch)",
        // og:image and og:url have to be absolute, and the scheme is
        // hard-coded: Cloud terminates TLS upstream and then sends
        // X-Forwarded-Proto: http on an https request, so that header cannot
        // be trusted.
        "OG_IMAGE": "\(base)/og.png",
        "PAGE_URL": "\(base)/",
        "INDEX_URL": indexURL,
        "EXTRA": "",
    ]

    var out = [UInt8]()
    out.reserveCapacity(templateBytes.count + 512)
    let open: [UInt8] = [0x7b, 0x7b]   // {{
    let close: [UInt8] = [0x7d, 0x7d]  // }}
    var i = 0
    while i < templateBytes.count {
        if i + 1 < templateBytes.count, templateBytes[i] == open[0], templateBytes[i + 1] == open[1],
           let end = closing(from: i + 2, close: close),
           let value = values[String(decoding: templateBytes[(i + 2)..<end], as: UTF8.self)]
        {
            out.append(contentsOf: Array(value.utf8))
            i = end + 2
            continue
        }
        out.append(templateBytes[i])
        i += 1
    }
    return String(decoding: out, as: UTF8.self)
}

/// The index of the `}}` that closes a placeholder opened at `from`, or nil if
/// this `{{` is not a placeholder after all.
func closing(from: Int, close: [UInt8]) -> Int? {
    var j = from
    while j + 1 < templateBytes.count {
        if templateBytes[j] == close[0], templateBytes[j + 1] == close[1] { return j }
        // Placeholder names are upper case and underscores; anything else means
        // this was not one.
        let c = templateBytes[j]
        let isName = (c >= 0x41 && c <= 0x5a) || c == 0x5f
        if !isName { return nil }
        j += 1
    }
    return nil
}

func envInt(_ name: String, _ fallback: Int) -> Int {
    guard let raw = getenv(name) else { return fallback }
    return Int(String(cString: raw)) ?? fallback
}

/// Everything lives inside `main()` rather than in top-level code: under Swift
/// 6 strict concurrency, top-level code in a file called main.swift is
/// main-actor isolated, and a `Router` is not Sendable, so it cannot be handed
/// to a non-isolated async function from there.
@main
struct Main {
    static func main() async throws {
        let router = Router()

        router.get("/") { request, _ -> Response in
            // HTTPTypes marks the Host field unavailable on purpose: in HTTP/2 the
            // authority is a pseudo-header, so it is read from the request head.
            let host = request.head.authority ?? "localhost"
            var headers = HTTPFields()
            headers[.contentType] = "text/html; charset=utf-8"
            return Response(
                status: .ok,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(string: renderPage(host: host)))
            )
        }

        router.get("/og.png") { _, _ -> Response in
            var headers = HTTPFields()
            headers[.contentType] = "image/png"
            headers[.cacheControl] = "public, max-age=3600"
            return Response(
                status: .ok,
                headers: headers,
                body: .init(byteBuffer: ByteBuffer(bytes: ogBytes))
            )
        }

        // Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an
        // IPv6-only network, so the wanted socket is the dual-stack IPv6
        // wildcard: IPV6_V6ONLY is off by default on Linux, so one socket
        // answers both families.
        //
        // NIO turns a BindAddress into a sockaddr with
        // SocketAddress.makeAddressResolvingHost, which is getaddrinfo, and
        // glibc's getaddrinfo refuses even a numeric IPv6 address on a host
        // that has no non-loopback IPv6 address of its own: it returns
        // EAI_ADDRFAMILY, which arrives here as
        // SocketAddressError.UnknownHost (a struct nested in the enum of the
        // same name -- catching the enum does not catch it). That is every
        // container without IPv6: a plain `docker run`, and the runner this
        // binary is smoke-tested on. The kernel is willing; only the resolver
        // objects.
        //
        // So: ask for the dual-stack socket, and fall back to the IPv4 wildcard
        // when the host has no IPv6 at all. On Cloud the first one binds, and
        // the startup line in the deploy log says which it was.
        let port = envInt("PORT", 3000)
        do {
            try await Self.serve(router: router, on: .hostname("::", port: port))
        } catch let error as SocketAddressError.UnknownHost {
            print("hello_cloud: [::] is unavailable (\(error)); falling back to 0.0.0.0")
            try await Self.serve(router: router, on: .hostname("0.0.0.0", port: port))
        }
    }

    static func serve(router: Router<BasicRequestContext>, on address: BindAddress) async throws {
        let app = Application(
            router: router,
            configuration: .init(address: address, serverName: "hello_cloud")
        )
        print("hello_cloud: hello from \(language), serving on \(address)")
        try await app.runService()
    }
}
