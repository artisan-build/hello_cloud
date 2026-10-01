/**
 * Hello from D, on Laravel Cloud's Go runtime.
 *
 * Laravel Cloud runs this binary because the branch carries a `go.mod` at its
 * root, so the environment was detected as Go when it was created and Cloud
 * starts whatever executable the build command left at `./app`. No Go is
 * compiled for this branch; the build command downloads the binary that GitHub
 * Actions built from this commit.
 *
 * No framework: `std.socket` is the whole web layer -- a TCP listener, an accept
 * loop, and just enough request parsing to find the path and the Host header.
 * The shared HTML template, the index URL and the OG card come in through D's
 * `import("...")` string imports (ldc2 is given `-J.`), so they are baked into
 * the binary and nothing is read from Cloud's ephemeral disk.
 */
module app;

import std.algorithm : findSplit, startsWith;
import std.array : replace;
import std.conv : to;
import std.process : environment;
import std.socket;
import std.stdio : writefln, stdout;
import std.string : indexOf, splitLines, strip, toLower;

enum language = "D";
enum branch = "d";
enum repo = "https://github.com/artisan-build/hello_cloud";

enum pageTemplate = import("shared/page.html");
enum indexUrl = import("shared/index-url.txt");
immutable ubyte[] ogPng = cast(immutable ubyte[]) import("og.png");

/**
 * Fills the shared template's seven placeholders.
 *
 * og:image and og:url have to be absolute, so they are built from the request's
 * Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
 * then sends `X-Forwarded-Proto: http` on an https request, so that header
 * cannot be trusted.
 */
string renderPage(string host)
{
    return pageTemplate
        .replace("{{LANGUAGE}}", language)
        .replace("{{BRANCH_URL}}", repo ~ "/tree/" ~ branch)
        .replace("{{BRANCH}}", branch)
        .replace("{{OG_IMAGE}}", "https://" ~ host ~ "/og.png")
        .replace("{{PAGE_URL}}", "https://" ~ host ~ "/")
        .replace("{{INDEX_URL}}", indexUrl.strip())
        .replace("{{EXTRA}}", ""); // only main fills this
}

ushort listenPort()
{
    try
    {
        const raw = environment.get("PORT", "");
        if (raw.length)
        {
            const port = raw.to!int;
            if (port > 0 && port <= 65_535)
                return cast(ushort) port;
        }
    }
    catch (Exception)
    {
    }
    return 3000;
}

string requestPath(string request)
{
    auto afterMethod = request.findSplit(" ");
    if (!afterMethod)
        return "/";
    auto beforeVersion = afterMethod[2].findSplit(" ");
    return beforeVersion ? beforeVersion[0] : "/";
}

string requestHost(string request)
{
    foreach (line; request.splitLines())
    {
        const colon = line.indexOf(':');
        if (colon <= 0)
            continue;
        if (line[0 .. colon].toLower() != "host")
            continue;
        return line[colon + 1 .. $].strip();
    }
    return "localhost";
}

void respond(Socket client, string status, string contentType, const(void)[] body_)
{
    const head = "HTTP/1.1 " ~ status ~ "\r\ncontent-type: " ~ contentType
        ~ "\r\ncontent-length: " ~ body_.length.to!string ~ "\r\nconnection: close\r\n\r\n";
    sendAll(client, cast(const(void)[]) head);
    sendAll(client, body_);
}

void sendAll(Socket client, const(void)[] data)
{
    auto bytes = cast(const(ubyte)[]) data;
    while (bytes.length)
    {
        const sent = client.send(bytes);
        if (sent <= 0)
            return; // peer gone: drop the rest of this response
        bytes = bytes[sent .. $];
    }
}

void serve(Socket client)
{
    ubyte[16 * 1024] buffer;
    size_t held;
    while (held < buffer.length)
    {
        const received = client.receive(buffer[held .. $]);
        if (received <= 0)
            break;
        held += received;
        if ((cast(string) buffer[0 .. held]).indexOf("\r\n\r\n") >= 0)
            break;
    }
    if (held == 0)
        return;

    const request = (cast(char[]) buffer[0 .. held]).idup;
    const path = requestPath(request);

    if (path == "/og.png")
    {
        respond(client, "200 OK",
            "image/png\r\ncache-control: public, max-age=3600", ogPng);
        return;
    }
    if (path != "/")
    {
        respond(client, "404 Not Found", "text/plain; charset=utf-8", "not found\n");
        return;
    }
    respond(client, "200 OK", "text/html; charset=utf-8", renderPage(requestHost(request)));
}

void main()
{
    const port = listenPort();

    // Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
    // network. Binding the IPv6 wildcard is dual-stack on Linux and std.socket
    // never touches IPV6_V6ONLY, so this one listener answers both families.
    auto listener = new TcpSocket(AddressFamily.INET6);
    listener.setOption(SocketOptionLevel.SOCKET, SocketOption.REUSEADDR, true);
    listener.bind(new Internet6Address(Internet6Address.ADDR_ANY, port));
    listener.listen(128);

    writefln("hello_cloud: hello from %s, serving on [::]:%d", language, port);
    stdout.flush();

    while (true)
    {
        auto client = listener.accept();
        scope (exit)
        {
            client.shutdown(SocketShutdown.BOTH);
            client.close();
        }
        serve(client);
    }
}
