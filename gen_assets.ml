(* Emits assets.ml: the shared template, the index URL and the OG card as
   OCaml string literals, so the binary carries them and never reads Cloud's
   ephemeral filesystem. Run by the build before dune, as:

       ocaml gen_assets.ml > assets.ml
*)
let read path =
  let ic = open_in_bin path in
  let n = in_channel_length ic in
  let s = really_input_string ic n in
  close_in ic;
  s

let () =
  List.iter
    (fun (name, path) ->
      Printf.printf "let %s = \"%s\"\n" name (String.escaped (read path)))
    [ ("page", "shared/page.html");
      ("index_url", "shared/index-url.txt");
      ("og_png", "og.png") ]
