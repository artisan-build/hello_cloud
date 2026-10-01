// Hello from C++, on Laravel Cloud's Go runtime.
//
// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
// root, so the environment was detected as Go when it was created and Cloud
// starts whatever executable the build command left at `./app`. No Go is
// compiled for this branch; the build command downloads the binary that GitHub
// Actions built from this commit.
//
// The web layer is cpp-httplib, a single header pinned by build.sh. The binary
// is fully static (musl, `-static`), so the host's glibc version is moot, and
// the shared HTML template, the index URL and the OG card are linked in as data
// by `ld -r -b binary` rather than read from Cloud's ephemeral disk.

#include <cstdlib>
#include <cstdio>
#include <string>
#include <string_view>

#include "httplib.h"

namespace {

constexpr std::string_view kLanguage = "C++";
constexpr std::string_view kBranch = "cpp";
constexpr std::string_view kRepo = "https://github.com/artisan-build/hello_cloud";

// Linked in by build.sh with `ld -r -b binary`; the symbol names come from the
// file paths it was handed.
extern "C" {
extern const char _binary_shared_page_html_start[], _binary_shared_page_html_end[];
extern const char _binary_shared_index_url_txt_start[], _binary_shared_index_url_txt_end[];
extern const char _binary_og_png_start[], _binary_og_png_end[];
}

std::string_view embedded(const char* start, const char* end) {
    return {start, static_cast<std::size_t>(end - start)};
}

std::string replace_all(std::string input, std::string_view needle, std::string_view value) {
    for (std::size_t at = input.find(needle); at != std::string::npos;
         at = input.find(needle, at + value.size())) {
        input.replace(at, needle.size(), value);
    }
    return input;
}

std::string trimmed(std::string_view s) {
    const auto first = s.find_first_not_of(" \t\r\n");
    if (first == std::string_view::npos) return {};
    return std::string(s.substr(first, s.find_last_not_of(" \t\r\n") - first + 1));
}

// Fills the shared template's seven placeholders.
//
// og:image and og:url have to be absolute, so they are built from the request's
// Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
// then sends `X-Forwarded-Proto: http` on an https request, so that header
// cannot be trusted.
std::string render_page(const std::string& host) {
    std::string page(embedded(_binary_shared_page_html_start, _binary_shared_page_html_end));
    page = replace_all(std::move(page), "{{LANGUAGE}}", kLanguage);
    page = replace_all(std::move(page), "{{BRANCH_URL}}", std::string(kRepo) + "/tree/" + std::string(kBranch));
    page = replace_all(std::move(page), "{{BRANCH}}", kBranch);
    page = replace_all(std::move(page), "{{OG_IMAGE}}", "https://" + host + "/og.png");
    page = replace_all(std::move(page), "{{PAGE_URL}}", "https://" + host + "/");
    page = replace_all(std::move(page),
                       "{{INDEX_URL}}",
                       trimmed(embedded(_binary_shared_index_url_txt_start, _binary_shared_index_url_txt_end)));
    page = replace_all(std::move(page), "{{EXTRA}}", "");  // only main fills this
    return page;
}

int listen_port() {
    if (const char* raw = std::getenv("PORT")) {
        const long port = std::strtol(raw, nullptr, 10);
        if (port > 0 && port <= 65535) return static_cast<int>(port);
    }
    return 3000;
}

}  // namespace

int main() {
    httplib::Server server;

    server.Get("/", [](const httplib::Request& req, httplib::Response& res) {
        std::string host = req.get_header_value("Host");
        if (host.empty()) host = "localhost";
        res.set_content(render_page(host), "text/html; charset=utf-8");
    });

    server.Get("/og.png", [](const httplib::Request&, httplib::Response& res) {
        const auto png = embedded(_binary_og_png_start, _binary_og_png_end);
        res.set_header("cache-control", "public, max-age=3600");
        res.set_content(png.data(), png.size(), "image/png");
    });

    const int port = listen_port();
    std::printf("hello_cloud: hello from %s, serving on [::]:%d\n", std::string(kLanguage).c_str(), port);
    std::fflush(stdout);

    // Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
    // network. cpp-httplib leaves IPV6_V6ONLY off (CPPHTTPLIB_IPV6_V6ONLY is
    // false by default), so binding the IPv6 wildcard answers both families.
    if (!server.listen("::", port)) {
        std::fprintf(stderr, "hello_cloud: could not listen on [::]:%d\n", port);
        return 1;
    }
    return 0;
}
