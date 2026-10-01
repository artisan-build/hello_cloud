// Hello from C#, on Laravel Cloud's Go runtime.
//
// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
// root, so the environment was detected as Go when it was created and Cloud
// starts whatever executable the build command left at `./app`. The build
// command never compiles any Go: it downloads the binary GitHub Actions built
// from this commit.
//
// The binary is a NativeAOT ASP.NET Core minimal API — one ELF with the CLR
// compiled away, carrying the shared template and the OG card as embedded
// resources.
using System.Reflection;

const string language = "C#";
const string branch = "csharp";
const string repoUrl = "https://github.com/artisan-build/hello_cloud";

var assembly = Assembly.GetExecutingAssembly();

static byte[] Resource(Assembly assembly, string name)
{
    using var stream = assembly.GetManifestResourceStream(name)
        ?? throw new InvalidOperationException($"embedded resource {name} is missing");
    using var buffer = new MemoryStream();
    stream.CopyTo(buffer);
    return buffer.ToArray();
}

var template = System.Text.Encoding.UTF8.GetString(Resource(assembly, "page.html"));
var indexUrl = System.Text.Encoding.UTF8.GetString(Resource(assembly, "index-url.txt")).Trim();
var ogPng = Resource(assembly, "og.png");

// Fills the shared template's seven placeholders. Replace, not ReplaceFirst:
// {{LANGUAGE}} appears nine times.
string Page(string host)
{
    var baseUrl = $"https://{host}";
    return template
        .Replace("{{LANGUAGE}}", language)
        .Replace("{{BRANCH_URL}}", $"{repoUrl}/tree/{branch}")
        .Replace("{{BRANCH}}", branch)
        .Replace("{{OG_IMAGE}}", $"{baseUrl}/og.png")
        .Replace("{{PAGE_URL}}", $"{baseUrl}/")
        .Replace("{{INDEX_URL}}", indexUrl)
        .Replace("{{EXTRA}}", "");
}

var port = Environment.GetEnvironmentVariable("PORT") ?? "3000";

// CreateSlimBuilder is the AOT-friendly host: no startup assembly scanning.
var builder = WebApplication.CreateSlimBuilder(args);
// Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
// network, so bind the dual-stack wildcard.
builder.WebHost.UseUrls($"http://[::]:{port}");

var app = builder.Build();

// og:image and og:url have to be absolute, so they are built from the request's
// Host header with a hard-coded https scheme: Cloud terminates TLS upstream and
// then sends `X-Forwarded-Proto: http` on an https request, so that header
// cannot be trusted.
app.MapGet("/", (HttpRequest request) =>
    Results.Content(Page(request.Host.Value), "text/html", System.Text.Encoding.UTF8));

app.MapGet("/og.png", (HttpResponse response) =>
{
    response.Headers.CacheControl = "public, max-age=3600";
    return Results.Bytes(ogPng, "image/png");
});

Console.WriteLine($"hello_cloud: hello from {language}, serving on [::]:{port}");
app.Run();
