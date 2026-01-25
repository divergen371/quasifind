open Cmdliner
open Quasifind

let run root_dir expr_str max_depth follow_symlinks jobs =
  let concurrency = match jobs with
    | None -> 1 
    | Some n -> n
  in
  let strategy = 
    if concurrency > 1 then Traversal.Parallel concurrency
    else Traversal.DFS
  in
  
  let cfg = {
    Traversal.strategy;
    max_depth;
    follow_symlinks;
  } in

  (* 1. Parse *)
  match Parser.parse expr_str with
  | Error msg ->
      Printf.eprintf "Parse Error: %s\n%!" msg;
      exit 1
  | Ok untyped_ast ->
      (* 2. Typecheck *)
      match Typecheck.check untyped_ast with
      | Error err ->
          Printf.eprintf "Type Error: %s\n%!" (Typecheck.string_of_error err);
          exit 1
      | Ok typed_ast ->
          (* 3. Traverse & Eval *)
          Eio_main.run @@ fun _env ->
          (* Use absolute path for root if possible, or leave as is. Traversal handles it. *)
          Traversal.traverse cfg root_dir typed_ast (fun entry ->
            (* 4. Output *)
            (* For now just print path *)
            Printf.printf "%s\n%!" entry.path
          )

(* CLI Definitions *)

let root_dir =
  let doc = "Root directory to search." in
  Arg.(value & pos 0 string "." & info [] ~docv:"DIR" ~doc)

let expr_str =
  let doc = "DSL expression." in
  Arg.(required & pos 1 (some string) None & info [] ~docv:"EXPR" ~doc)

let max_depth =
  let doc = "Maximum depth to traverse." in
  Arg.(value & opt (some int) None & info ["max-depth"; "d"] ~docv:"DEPTH" ~doc)

let follow_symlinks =
  let doc = "Follow symbolic links." in
  Arg.(value & flag & info ["follow"; "L"] ~doc)

let jobs =
  let doc = "Number of parallel jobs (threads). Default is 1 (sequential)." in
  Arg.(value & opt (some int) None & info ["jobs"; "j"] ~docv:"JOBS" ~doc)

let cmd =
  let doc = "Quasi-find: a typed, find-like filesystem query tool" in
  let info = Cmd.info "quasifind" ~version:"0.1.0" ~doc in
  Cmd.v info Term.(const run $ root_dir $ expr_str $ max_depth $ follow_symlinks $ jobs)

let () = exit (Cmd.eval cmd)
