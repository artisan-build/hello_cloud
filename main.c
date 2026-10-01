/*
 * Hello from C, on Laravel Cloud's Go runtime.
 *
 * Laravel Cloud runs this binary because the branch carries a `go.mod` at its
 * root, so the environment was detected as Go when it was created and Cloud
 * starts whatever executable the build command left at `./app`. No Go is
 * compiled for this branch; the build command downloads the binary that GitHub
 * Actions built from this commit.
 *
 * No framework and no HTTP library: a BSD socket, an accept loop and enough
 * request parsing to find the path and the Host header. The binary is fully
 * static (musl, `-static`), so the host's glibc version is moot, and the shared
 * HTML template, the index URL and the OG card are all linked in as data by
 * `ld -r -b binary` (see build.sh) rather than read from Cloud's ephemeral disk.
 */
#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <unistd.h>

static const char LANGUAGE[] = "C";
static const char BRANCH[] = "c";
static const char REPO[] = "https://github.com/artisan-build/hello_cloud";

/* Linked in by build.sh with `ld -r -b binary`; the symbol names come from the
 * file paths it was handed. */
extern const char _binary_shared_page_html_start[], _binary_shared_page_html_end[];
extern const char _binary_shared_index_url_txt_start[], _binary_shared_index_url_txt_end[];
extern const char _binary_og_png_start[], _binary_og_png_end[];

/* ------------------------------------------------------------------ buffer */

struct buf {
    char *data;
    size_t len, cap;
};

static int buf_reserve(struct buf *b, size_t extra)
{
    if (b->len + extra <= b->cap)
        return 0;
    size_t cap = b->cap ? b->cap : 8192;
    while (cap < b->len + extra)
        cap *= 2;
    char *data = realloc(b->data, cap);
    if (!data)
        return -1;
    b->data = data;
    b->cap = cap;
    return 0;
}

static int buf_add(struct buf *b, const char *s, size_t n)
{
    if (buf_reserve(b, n) != 0)
        return -1;
    memcpy(b->data + b->len, s, n);
    b->len += n;
    return 0;
}

static int buf_str(struct buf *b, const char *s)
{
    return buf_add(b, s, strlen(s));
}

/* ------------------------------------------------------------------- render */

/* Fills the shared template's seven placeholders.
 *
 * og:image and og:url have to be absolute, so they are built from the request's
 * Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
 * then sends `X-Forwarded-Proto: http` on an https request, so that header
 * cannot be trusted. */
static int render_page(struct buf *out, const char *host)
{
    const char *tpl = _binary_shared_page_html_start;
    size_t tpl_len = (size_t)(_binary_shared_page_html_end - _binary_shared_page_html_start);

    /* The index URL ships with a trailing newline; trim it. */
    const char *index_url = _binary_shared_index_url_txt_start;
    size_t index_len = (size_t)(_binary_shared_index_url_txt_end - _binary_shared_index_url_txt_start);
    while (index_len && (index_url[index_len - 1] == '\n' || index_url[index_len - 1] == '\r' ||
                         index_url[index_len - 1] == ' ' || index_url[index_len - 1] == '\t'))
        index_len--;

    for (size_t i = 0; i < tpl_len;) {
        if (i + 2 > tpl_len || tpl[i] != '{' || tpl[i + 1] != '{') {
            if (buf_add(out, tpl + i, 1) != 0)
                return -1;
            i++;
            continue;
        }
        const char *close = memchr(tpl + i, '}', tpl_len - i);
        if (!close) {
            if (buf_add(out, tpl + i, 1) != 0)
                return -1;
            i++;
            continue;
        }
        size_t name_at = i + 2;
        size_t name_len = (size_t)(close - (tpl + name_at));
        int ok = 0;

        if (name_len == 8 && !memcmp(tpl + name_at, "LANGUAGE", 8))
            ok = buf_str(out, LANGUAGE) == 0;
        else if (name_len == 6 && !memcmp(tpl + name_at, "BRANCH", 6))
            ok = buf_str(out, BRANCH) == 0;
        else if (name_len == 10 && !memcmp(tpl + name_at, "BRANCH_URL", 10))
            ok = buf_str(out, REPO) == 0 && buf_str(out, "/tree/") == 0 && buf_str(out, BRANCH) == 0;
        else if (name_len == 8 && !memcmp(tpl + name_at, "OG_IMAGE", 8))
            ok = buf_str(out, "https://") == 0 && buf_str(out, host) == 0 && buf_str(out, "/og.png") == 0;
        else if (name_len == 8 && !memcmp(tpl + name_at, "PAGE_URL", 8))
            ok = buf_str(out, "https://") == 0 && buf_str(out, host) == 0 && buf_str(out, "/") == 0;
        else if (name_len == 9 && !memcmp(tpl + name_at, "INDEX_URL", 9))
            ok = buf_add(out, index_url, index_len) == 0;
        else if (name_len == 5 && !memcmp(tpl + name_at, "EXTRA", 5))
            ok = 1; /* only main fills this */
        else {
            /* Not a placeholder after all: copy the braces through verbatim. */
            if (buf_add(out, tpl + i, 1) != 0)
                return -1;
            i++;
            continue;
        }
        if (!ok)
            return -1;
        i = name_at + name_len + 2; /* past `}}` */
    }
    return 0;
}

/* ------------------------------------------------------------------ request */

static void write_all(int fd, const char *data, size_t len)
{
    while (len) {
        ssize_t n = write(fd, data, len);
        if (n <= 0) {
            if (n < 0 && errno == EINTR)
                continue;
            return;
        }
        data += n;
        len -= (size_t)n;
    }
}

static void respond(int fd, const char *status, const char *type, const char *body, size_t len)
{
    char head[256];
    int n = snprintf(head, sizeof head,
                     "HTTP/1.1 %s\r\n"
                     "content-type: %s\r\n"
                     "content-length: %zu\r\n"
                     "connection: close\r\n"
                     "\r\n",
                     status, type, len);
    if (n > 0)
        write_all(fd, head, (size_t)n);
    write_all(fd, body, len);
}

/* Copies the Host header value into `host`, lowercase-insensitively, stopping
 * at CR/LF. Falls back to "localhost" so a request without one still renders. */
static void find_host(const char *req, size_t len, char *host, size_t host_cap)
{
    snprintf(host, host_cap, "%s", "localhost");
    for (size_t i = 0; i + 5 < len; i++) {
        if (i != 0 && req[i - 1] != '\n')
            continue;
        if (strncasecmp(req + i, "host:", 5) != 0)
            continue;
        size_t v = i + 5;
        while (v < len && (req[v] == ' ' || req[v] == '\t'))
            v++;
        size_t end = v;
        while (end < len && req[end] != '\r' && req[end] != '\n')
            end++;
        size_t n = end - v;
        if (n == 0 || n >= host_cap)
            return;
        memcpy(host, req + v, n);
        host[n] = '\0';
        return;
    }
}

static void serve(int fd)
{
    char req[16384];
    size_t have = 0;
    while (have < sizeof req - 1) {
        ssize_t n = read(fd, req + have, sizeof req - 1 - have);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            break;
        have += (size_t)n;
        req[have] = '\0';
        if (strstr(req, "\r\n\r\n") || strstr(req, "\n\n"))
            break;
    }
    if (have == 0)
        return;
    req[have] = '\0';

    /* "GET /path HTTP/1.1" -- the path is between the first two spaces. */
    const char *p = memchr(req, ' ', have);
    char path[1024] = "/";
    if (p) {
        p++;
        const char *q = strpbrk(p, " \r\n");
        size_t n = q ? (size_t)(q - p) : strlen(p);
        if (n && n < sizeof path) {
            memcpy(path, p, n);
            path[n] = '\0';
        }
    }

    if (!strcmp(path, "/og.png")) {
        respond(fd, "200 OK", "image/png", _binary_og_png_start,
                (size_t)(_binary_og_png_end - _binary_og_png_start));
        return;
    }
    if (strcmp(path, "/")) {
        respond(fd, "404 Not Found", "text/plain; charset=utf-8", "not found\n", 10);
        return;
    }

    char host[512];
    find_host(req, have, host, sizeof host);

    struct buf page = { 0 };
    if (render_page(&page, host) != 0) {
        free(page.data);
        respond(fd, "500 Internal Server Error", "text/plain; charset=utf-8", "render failed\n", 14);
        return;
    }
    respond(fd, "200 OK", "text/html; charset=utf-8", page.data, page.len);
    free(page.data);
}

int main(void)
{
    /* A client that hangs up mid-write must not kill the server. */
    signal(SIGPIPE, SIG_IGN);
    setvbuf(stdout, NULL, _IOLBF, 0);

    const char *env = getenv("PORT");
    long port = env ? strtol(env, NULL, 10) : 3000;
    if (port <= 0 || port > 65535)
        port = 3000;

    int srv = socket(AF_INET6, SOCK_STREAM, 0);
    if (srv < 0) {
        perror("socket");
        return 1;
    }
    int one = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    /* Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
     * network. Binding the IPv6 wildcard is dual-stack on Linux, so this one
     * listener answers both; IPV6_V6ONLY is deliberately left alone. */
    struct sockaddr_in6 addr;
    memset(&addr, 0, sizeof addr);
    addr.sin6_family = AF_INET6;
    addr.sin6_addr = in6addr_any;
    addr.sin6_port = htons((unsigned short)port);
    if (bind(srv, (struct sockaddr *)&addr, sizeof addr) != 0) {
        perror("bind");
        return 1;
    }
    if (listen(srv, 128) != 0) {
        perror("listen");
        return 1;
    }
    printf("hello_cloud: hello from %s, serving on [::]:%ld\n", LANGUAGE, port);

    for (;;) {
        int fd = accept(srv, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR)
                continue;
            perror("accept");
            continue;
        }
        serve(fd);
        close(fd);
    }
}
