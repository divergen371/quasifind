open Cmdliner
open Quasifind

(* Wrapper for run to return Cmdliner return type *)
let run root_dir expr_str_opt max_depth follow_symlinks include_hidden jobs help_short =
  if help_short then `Help (`Auto, None)
  else match expr_str_opt with
  | None -> `Help (`Auto, None) (* Show help if no expression provided *)
  | Some expr_str ->
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
      include_hidden;
    } in

    (* 1. Parse *)
    match Parser.parse expr_str with
    | Error msg ->
        `Error (false, "Parse Error: " ^ msg)
    | Ok untyped_ast ->
        (* 2. Typecheck *)
        match Typecheck.check untyped_ast with
        | Error err ->
            `Error (false, "Type Error: " ^ Typecheck.string_of_error err)
        | Ok typed_ast ->
            (* 3. Traverse & Eval *)
            Eio_main.run @@ fun _env ->
            (* Use absolute path for root if possible, or leave as is. Traversal handles it. *)
            let now = Unix.gettimeofday () in
            Traversal.traverse cfg root_dir typed_ast (fun entry ->
              (* 4. Eval *)
              if Eval.eval now typed_ast entry then
                (* 5. Output *)
                Printf.printf "%s\n%!" entry.path
            );
            `Ok ()

(* CLI Definitions *)

let root_dir =
  let doc = "Root directory to search." in
  Arg.(value & pos 0 string "." & info [] ~docv:"DIR" ~doc)

let expr_str =
  let doc = "DSL expression. Required unless -h is used." in
  Arg.(value & pos 1 (some string) None & info [] ~docv:"EXPR" ~doc)

let max_depth =
  let doc = "Maximum depth to traverse." in
  Arg.(value & opt (some int) None & info ["max-depth"; "d"] ~docv:"DEPTH" ~doc)

let follow_symlinks =
  let doc = "Follow symbolic links." in
  Arg.(value & flag & info ["follow"; "L"] ~doc)

let include_hidden =
  let doc = "Include hidden files and directories (starting with .)." in
  Arg.(value & flag & info ["hidden"; "H"] ~doc)

let jobs =
  let doc = "Number of parallel jobs (threads). Default is 1 (sequential)." in
  Arg.(value & opt (some int) None & info ["jobs"; "j"] ~docv:"JOBS" ~doc)

let help_short =
  let doc = "Show this help." in
  Arg.(value & flag & info ["h"] ~doc)

let cmd =
  let doc = "Quasi-find: a typed, find-like filesystem query tool" in
  let info = Cmd.info "quasifind" ~version:"0.1.0" ~doc in
  Cmd.v info Term.(ret (const run $ root_dir $ expr_str $ max_depth $ follow_symlinks $ include_hidden $ jobs $ help_short))

let () = exit (Cmd.eval cmd)
