/*
 * A static C host for the Lua that actually answers the request.
 *
 * Laravel Cloud runs this binary because the branch carries a `go.mod` at its
 * root, so the environment was detected as Go when it was created and Cloud
 * starts whatever executable the build command left at `./app`. Nothing Go is
 * compiled: the build command downloads the binary GitHub Actions built from
 * this commit.
 *
 * The division of labour here is the point. C does the two things Lua has no
 * standard library for -- an IPv6 listening socket and the HTTP framing -- and
 * every byte of the response body comes out of `app.lua`, which fills the
 * shared template. Lua 5.4 is linked in statically, so is glibc, so the whole
 * thing is one file with no runtime on the host.
 *
 * The four payloads (the Lua script, the shared template, the shared index URL
 * and the OG card) are linked in as binary blobs by `ld -r -b binary`, so the
 * filesystem is not read at run time at all.
 */

#include <errno.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/socket.h>
#include <sys/types.h>
#include <unistd.h>

#include "lauxlib.h"
#include "lua.h"
#include "lualib.h"

#define LANGUAGE "Lua"
#define BRANCH "lua"
#define REPO_URL "https://github.com/artisan-build/hello_cloud"

/* Symbols from `ld -r -b binary`; the names come from the input filenames. */
extern const char _binary_app_lua_start[], _binary_app_lua_end[];
extern const char _binary_page_html_start[], _binary_page_html_end[];
extern const char _binary_index_url_txt_start[], _binary_index_url_txt_end[];
extern const char _binary_og_png_start[], _binary_og_png_end[];

#define BLOB_LEN(name) ((size_t)(_binary_##name##_end - _binary_##name##_start))

static lua_State *L;

/* Pushes a blob as a Lua string, length-delimited: the blobs are not
 * NUL-terminated, so strlen() on them would run off the end. */
static void push_blob(lua_State *l, const char *start, size_t len)
{
    lua_pushlstring(l, start, len);
}

static void lua_fail(const char *what)
{
    fprintf(stderr, "hello_cloud: %s: %s\n", what, lua_tostring(L, -1));
    exit(1);
}

static void lua_boot(void)
{
    L = luaL_newstate();
    if (L == NULL) {
        fprintf(stderr, "hello_cloud: luaL_newstate failed\n");
        exit(1);
    }
    luaL_openlibs(L);

    /* Everything app.lua needs, as globals, so the script has no I/O to do. */
    push_blob(L, _binary_page_html_start, BLOB_LEN(page_html));
    lua_setglobal(L, "TEMPLATE");
    push_blob(L, _binary_index_url_txt_start, BLOB_LEN(index_url_txt));
    lua_setglobal(L, "INDEX_URL");
    lua_pushstring(L, LANGUAGE);
    lua_setglobal(L, "LANGUAGE");
    lua_pushstring(L, BRANCH);
    lua_setglobal(L, "BRANCH");
    lua_pushstring(L, REPO_URL);
    lua_setglobal(L, "REPO_URL");

    if (luaL_loadbuffer(L, _binary_app_lua_start, BLOB_LEN(app_lua), "@app.lua") != LUA_OK)
        lua_fail("loading app.lua");
    if (lua_pcall(L, 0, 0, 0) != LUA_OK)
        lua_fail("running app.lua");

    lua_getglobal(L, "render");
    if (!lua_isfunction(L, -1)) {
        fprintf(stderr, "hello_cloud: app.lua defined no global render()\n");
        exit(1);
    }
    lua_pop(L, 1);
}

/* Calls render(host) in Lua. Returns a pointer into the Lua state, valid until
 * the next call, and sets *len. */
static const char *render(const char *host, size_t *len)
{
    lua_settop(L, 0);
    lua_getglobal(L, "render");
    lua_pushstring(L, host);
    if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
        fprintf(stderr, "hello_cloud: render(): %s\n", lua_tostring(L, -1));
        return NULL;
    }
    return lua_tolstring(L, -1, len);
}

static void write_all(int fd, const char *buf, size_t len)
{
    while (len > 0) {
        ssize_t n = write(fd, buf, len);
        if (n <= 0) {
            if (n < 0 && errno == EINTR)
                continue;
            return;
        }
        buf += n;
        len -= (size_t)n;
    }
}

static void respond(int fd, const char *status, const char *ctype, const char *extra,
                    const char *body, size_t len)
{
    char head[512];
    int n = snprintf(head, sizeof head,
                     "HTTP/1.1 %s\r\n"
                     "Content-Type: %s\r\n"
                     "Content-Length: %zu\r\n"
                     "%s"
                     "Connection: close\r\n"
                     "\r\n",
                     status, ctype, len, extra);
    if (n > 0)
        write_all(fd, head, (size_t)n);
    if (len > 0)
        write_all(fd, body, len);
}

/* Reads the request head (up to the blank line), and copies the path and the
 * Host header out of it. A page like this needs nothing else from the request. */
static int read_request(int fd, char *path, size_t path_cap, char *host, size_t host_cap)
{
    char buf[8192];
    size_t have = 0;

    path[0] = '\0';
    host[0] = '\0';

    while (have < sizeof buf - 1) {
        ssize_t n = read(fd, buf + have, sizeof buf - 1 - have);
        if (n < 0 && errno == EINTR)
            continue;
        if (n <= 0)
            break;
        have += (size_t)n;
        buf[have] = '\0';
        if (strstr(buf, "\r\n\r\n") || strstr(buf, "\n\n"))
            break;
    }
    if (have == 0)
        return -1;
    buf[have] = '\0';

    if (sscanf(buf, "%*s %255s", path) != 1)
        return -1;

    /* Route on the path alone. A shared link arrives as "/?fbclid=..." or
     * "/og.png?utm_source=...", and strcmp against a literal "/" would 404 it.
     * The fragment never reaches a server, but cut it too and the comparison
     * cannot be surprised. */
    path[strcspn(path, "?#")] = '\0';

    for (char *line = strchr(buf, '\n'); line != NULL; line = strchr(line, '\n')) {
        line++;
        if (strncasecmp(line, "Host:", 5) != 0)
            continue;
        const char *v = line + 5;
        while (*v == ' ' || *v == '\t')
            v++;
        size_t i = 0;
        while (v[i] != '\0' && v[i] != '\r' && v[i] != '\n' && i < host_cap - 1)
            i++;
        memcpy(host, v, i);
        host[i] = '\0';
        break;
    }
    (void)path_cap;
    return 0;
}

/* Only [A-Za-z0-9.:-] get through, so the Host header cannot inject attributes
 * into the absolute og:image / og:url it ends up in. */
static void sanitise_host(char *host)
{
    char *w = host;
    for (char *r = host; *r != '\0'; r++) {
        if ((*r >= 'a' && *r <= 'z') || (*r >= 'A' && *r <= 'Z') ||
            (*r >= '0' && *r <= '9') || *r == '.' || *r == '-' || *r == ':' ||
            *r == '[' || *r == ']')
            *w++ = *r;
    }
    *w = '\0';
    if (host[0] == '\0')
        strcpy(host, "localhost");
}

static void serve(int fd)
{
    char path[256];
    char host[256];

    if (read_request(fd, path, sizeof path, host, sizeof host) != 0)
        return;
    sanitise_host(host);

    if (strcmp(path, "/og.png") == 0) {
        respond(fd, "200 OK", "image/png", "Cache-Control: public, max-age=3600\r\n",
                _binary_og_png_start, BLOB_LEN(og_png));
        return;
    }
    if (strcmp(path, "/") != 0) {
        static const char nf[] = "not found\n";
        respond(fd, "404 Not Found", "text/plain; charset=utf-8", "", nf, sizeof nf - 1);
        return;
    }

    size_t len = 0;
    const char *body = render(host, &len);
    if (body == NULL) {
        static const char err[] = "render failed\n";
        respond(fd, "500 Internal Server Error", "text/plain; charset=utf-8", "", err,
                sizeof err - 1);
        return;
    }
    respond(fd, "200 OK", "text/html; charset=utf-8", "", body, len);
}

int main(void)
{
    const char *p = getenv("PORT");
    unsigned short port = (unsigned short)((p != NULL && *p != '\0') ? atoi(p) : 3000);

    /* A dead client mid-write must not kill the server. */
    signal(SIGPIPE, SIG_IGN);

    lua_boot();

    int srv = socket(AF_INET6, SOCK_STREAM, 0);
    if (srv < 0) {
        perror("hello_cloud: socket");
        return 1;
    }
    int one = 1;
    setsockopt(srv, SOL_SOCKET, SO_REUSEADDR, &one, sizeof one);

    /* The dual-stack IPv6 wildcard: Cloud's per-instance nginx proxies to
     * 127.0.0.1:$PORT over an IPv6-only network, and IPV6_V6ONLY is off by
     * default on Linux, which is what makes both reachable. */
    struct sockaddr_in6 addr;
    memset(&addr, 0, sizeof addr);
    addr.sin6_family = AF_INET6;
    addr.sin6_addr = in6addr_any;
    addr.sin6_port = htons(port);

    if (bind(srv, (struct sockaddr *)&addr, sizeof addr) != 0) {
        perror("hello_cloud: bind");
        return 1;
    }
    if (listen(srv, 64) != 0) {
        perror("hello_cloud: listen");
        return 1;
    }
    printf("hello_cloud: hello from %s, serving on [::]:%u\n", LANGUAGE, port);
    fflush(stdout);

    /* One request at a time, each connection closed when it is answered. The
     * Lua state is single-threaded by design and a static page needs no more. */
    for (;;) {
        int fd = accept(srv, NULL, NULL);
        if (fd < 0) {
            if (errno == EINTR)
                continue;
            perror("hello_cloud: accept");
            return 1;
        }
        serve(fd);
        close(fd);
    }
}
