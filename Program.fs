/// Hello from F#, on Laravel Cloud's Go runtime.
///
/// Laravel Cloud runs this binary because the branch carries a `go.mod` at its
/// root, so the environment was detected as Go when it was created and Cloud
/// starts whatever executable the build command left at `./app`. The build
/// command for this environment never compiles any Go: it downloads the binary
/// GitHub Actions built from this commit.
///
/// The shared HTML template, the index URL and the OG card are embedded in the
/// assembly, so nothing on Cloud's ephemeral filesystem matters once the
/// process is up.
module Hello.Program

open System
open System.IO
open System.Reflection
open System.Text
open Microsoft.AspNetCore.Builder
open Microsoft.AspNetCore.Hosting
open Microsoft.AspNetCore.Http

let private language = "F#"
let private branch = "fsharp"
let private repoUrl = "https://github.com/artisan-build/hello_cloud"

let private resource name : byte[] =
    let asm = Assembly.GetExecutingAssembly()
    use stream = asm.GetManifestResourceStream(name)
    if isNull stream then failwithf "embedded resource %s is missing" name
    use buffer = new MemoryStream()
    stream.CopyTo buffer
    buffer.ToArray()

/// The shared template from `main`. Do not fork it per language.
let private template = Encoding.UTF8.GetString(resource "page.html")
/// The index URL, also shared from `main`.
let private indexUrl = Encoding.UTF8.GetString(resource "index-url.txt").Trim()
/// Written by `go run ./tools/ogen -language "F#" -out og.png` before the build.
let private ogPng = resource "og.png"

/// Fills the shared template's seven placeholders.
///
/// `og:image` and `og:url` have to be absolute, so they are built from the
/// request's Host header with a hard-coded https scheme: Cloud terminates TLS
/// upstream and then sends `X-Forwarded-Proto: http` on an https request, so
/// that header cannot be trusted.
let private render (host: string) =
    let bas = "https://" + host
    [ "{{LANGUAGE}}", language
      "{{BRANCH}}", branch
      "{{BRANCH_URL}}", repoUrl + "/tree/" + branch
      "{{OG_IMAGE}}", bas + "/og.png"
      "{{PAGE_URL}}", bas + "/"
      "{{INDEX_URL}}", indexUrl
      "{{EXTRA}}", "" ]
    |> List.fold (fun (acc: string) (needle, value) -> acc.Replace(needle, value)) template

[<EntryPoint>]
let main argv =
    let port =
        match Int32.TryParse(Environment.GetEnvironmentVariable "PORT") with
        | true, p -> p
        | _ -> 3000

    let builder = WebApplication.CreateSlimBuilder(argv)
    // Cloud's per-instance nginx proxies to 127.0.0.1:$PORT over an IPv6-only
    // network, so bind the dual-stack wildcard. Kestrel's ListenAnyIP is an
    // IPv6Any socket with DualMode on, which is what that needs.
    builder.WebHost.ConfigureKestrel(fun opts -> opts.ListenAnyIP port) |> ignore

    let app = builder.Build()

    app.MapGet(
        "/",
        Func<HttpContext, IResult>(fun ctx ->
            let host = if String.IsNullOrEmpty ctx.Request.Host.Value then "localhost" else ctx.Request.Host.Value
            Results.Text(render host, "text/html; charset=utf-8"))
    )
    |> ignore

    app.MapGet(
        "/og.png",
        Func<HttpContext, IResult>(fun ctx ->
            ctx.Response.Headers.CacheControl <- "public, max-age=3600"
            Results.Bytes(ogPng, "image/png"))
    )
    |> ignore

    printfn "hello_cloud: hello from %s, serving on [::]:%d" language port
    app.Run()
    0
