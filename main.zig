//! Hello from Zig, on Laravel Cloud's Go runtime.
//!
//! Cloud has no Zig runtime. It runs this binary because the branch carries a
//! `go.mod` at its root, so Cloud detected Go when the environment was created
//! and starts whatever executable the build command left at `./app`. No Go is
//! compiled for this branch; the build command downloads the binary that GitHub
//! Actions built from this commit.
//!
//! No framework: `std.http.Server` is the whole web layer. The binary is fully
//! static (`-target aarch64-linux-musl`), so Cloud's glibc version is moot, and
//! both the shared HTML template and the OG card are compiled in.

const std = @import("std");

const language = "Zig";
const branch_name = "zig";
const repo_url = "https://github.com/artisan-build/hello_cloud";

/// The shared template from `main`. Do not fork it per language.
const template = @embedFile("shared/page.html");
/// The index URL, also shared from `main`.
const index_url = @embedFile("shared/index-url.txt");
/// Written by `go run ./tools/ogen -language Zig -out og.png` before the build.
const og_png = @embedFile("og.png");

pub fn main() !void {
    var gpa: std.heap.GeneralPurposeAllocator(.{}) = .{};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    // Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
    // network. Binding the IPv6 wildcard is dual-stack on Linux, so this one
    // listener answers both.
    const port = listenPort();
    const address = std.net.Address.parseIp6("::", port) catch unreachable;
    var server = try address.listen(.{ .reuse_address = true });
    defer server.deinit();

    std.debug.print("hello_cloud: hello from {s}, serving on [::]:{d}\n", .{ language, port });

    while (true) {
        const connection = server.accept() catch |err| {
            std.debug.print("hello_cloud: accept: {s}\n", .{@errorName(err)});
            continue;
        };
        const thread = std.Thread.spawn(.{}, serveConnection, .{ allocator, connection }) catch |err| {
            std.debug.print("hello_cloud: spawn: {s}\n", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
        thread.detach();
    }
}

fn listenPort() u16 {
    const raw = std.posix.getenv("PORT") orelse return 3000;
    return std.fmt.parseInt(u16, raw, 10) catch 3000;
}

fn serveConnection(allocator: std.mem.Allocator, connection: std.net.Server.Connection) void {
    defer connection.stream.close();

    var read_buffer: [16 * 1024]u8 = undefined;
    var http = std.http.Server.init(connection, &read_buffer);

    while (http.state == .ready) {
        var request = http.receiveHead() catch |err| {
            if (err != error.HttpConnectionClosing) {
                std.debug.print("hello_cloud: receiveHead: {s}\n", .{@errorName(err)});
            }
            return;
        };
        handle(allocator, &request) catch |err| {
            std.debug.print("hello_cloud: handle: {s}\n", .{@errorName(err)});
            return;
        };
    }
}

fn handle(allocator: std.mem.Allocator, request: *std.http.Server.Request) !void {
    const target = request.head.target;

    if (std.mem.eql(u8, target, "/og.png")) {
        return request.respond(og_png, .{ .extra_headers = &.{
            .{ .name = "content-type", .value = "image/png" },
            .{ .name = "cache-control", .value = "public, max-age=3600" },
        } });
    }

    if (!std.mem.eql(u8, target, "/")) {
        return request.respond("not found\n", .{ .status = .not_found });
    }

    const body = try renderPage(allocator, requestHost(request) orelse "localhost");
    defer allocator.free(body);
    return request.respond(body, .{ .extra_headers = &.{
        .{ .name = "content-type", .value = "text/html; charset=utf-8" },
    } });
}

fn requestHost(request: *std.http.Server.Request) ?[]const u8 {
    var it = request.iterateHeaders();
    while (it.next()) |header| {
        if (std.ascii.eqlIgnoreCase(header.name, "host")) return header.value;
    }
    return null;
}

/// Fills the shared template's seven placeholders.
///
/// `og:image` and `og:url` have to be absolute, so they are built from the
/// request's Host header with a hard-coded https scheme: Cloud terminates TLS
/// upstream and then sends `X-Forwarded-Proto: http` on an https request, so
/// that header cannot be trusted.
fn renderPage(allocator: std.mem.Allocator, host: []const u8) ![]u8 {
    const branch_url = try std.fmt.allocPrint(allocator, "{s}/tree/{s}", .{ repo_url, branch_name });
    defer allocator.free(branch_url);
    const og_url = try std.fmt.allocPrint(allocator, "https://{s}/og.png", .{host});
    defer allocator.free(og_url);
    const page_url = try std.fmt.allocPrint(allocator, "https://{s}/", .{host});
    defer allocator.free(page_url);

    const replacements = [_][2][]const u8{
        .{ "{{LANGUAGE}}", language },
        .{ "{{BRANCH}}", branch_name },
        .{ "{{BRANCH_URL}}", branch_url },
        .{ "{{OG_IMAGE}}", og_url },
        .{ "{{PAGE_URL}}", page_url },
        .{ "{{INDEX_URL}}", std.mem.trim(u8, index_url, " \t\r\n") },
        .{ "{{EXTRA}}", "" },
    };

    var out = try allocator.dupe(u8, @as([]const u8, template));
    errdefer allocator.free(out);
    for (replacements) |replacement| {
        const next = try replaceAlloc(allocator, out, replacement[0], replacement[1]);
        allocator.free(out);
        out = next;
    }
    return out;
}

fn replaceAlloc(
    allocator: std.mem.Allocator,
    input: []const u8,
    needle: []const u8,
    replacement: []const u8,
) ![]u8 {
    const size = std.mem.replacementSize(u8, input, needle, replacement);
    const out = try allocator.alloc(u8, size);
    _ = std.mem.replace(u8, input, needle, replacement, out);
    return out;
}
