(* Hello from OCaml, on Laravel Cloud's Go runtime.

   Laravel Cloud runs this binary because the branch carries a [go.mod] at its
   root, so the environment was detected as Go when it was created and Cloud
   starts whatever executable the build command left at [./app]. The build
   command for this environment never compiles any Go: it downloads the binary
   GitHub Actions built from this commit.

   The shared HTML template, the index URL and the OG card are compiled in as
   string literals (see gen_assets.ml), so nothing on Cloud's ephemeral
   filesystem matters once the process is up. *)

let language = "OCaml"
let branch = "ocaml"
let repo_url = "https://github.com/artisan-build/hello_cloud"
let index_url = String.trim Assets.index_url

(* A tiny search-and-replace; the template has seven placeholders and no
   templating engine is worth a dependency for that. *)
let replace ~needle ~value haystack =
  let nl = String.length needle and hl = String.length haystack in
  let buf = Buffer.create (hl + 256) in
  let i = ref 0 in
  while !i < hl do
    if !i + nl <= hl && String.sub haystack !i nl = needle then begin
      Buffer.add_string buf value;
      i := !i + nl
    end
    else begin
      Buffer.add_char buf haystack.[!i];
      incr i
    end
  done;
  Buffer.contents buf

(* og:image and og:url have to be absolute, so they are built from the
   request's Host header with a hard-coded https scheme: Cloud terminates TLS
   upstream and then sends [X-Forwarded-Proto: http] on an https request, so
   that header cannot be trusted. *)
let render host =
  let base = "https://" ^ host in
  List.fold_left
    (fun page (needle, value) -> replace ~needle ~value page)
    Assets.page
    [ ("{{LANGUAGE}}", language);
      ("{{BRANCH}}", branch);
      ("{{BRANCH_URL}}", repo_url ^ "/tree/" ^ branch);
      ("{{OG_IMAGE}}", base ^ "/og.png");
      ("{{PAGE_URL}}", base ^ "/");
      ("{{INDEX_URL}}", index_url);
      ("{{EXTRA}}", "") ]

let page request =
  let host = Option.value (Dream.header request "Host") ~default:"localhost" in
  Dream.respond
    ~headers:[ ("Content-Type", "text/html; charset=utf-8") ]
    (render host)

let og _request =
  Dream.respond
    ~headers:
      [ ("Content-Type", "image/png");
        ("Cache-Control", "public, max-age=3600") ]
    Assets.og_png

let () =
  let port =
    match Sys.getenv_opt "PORT" with
    | Some p -> ( try int_of_string p with _ -> 3000)
    | None -> 3000
  in
  Printf.printf "hello_cloud: hello from %s, serving on [::]:%d\n%!" language port;
  (* Cloud's per-instance nginx proxies to $PORT over an IPv6-only network, so
     bind the IPv6 wildcard. Linux leaves IPV6_V6ONLY off by default, which
     makes that socket dual-stack. *)
  Dream.run ~interface:"::" ~port ~error_handler:Dream.debug_error_handler
  @@ Dream.router [ Dream.get "/" page; Dream.get "/og.png" og ]
