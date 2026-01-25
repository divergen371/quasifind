open Cmdliner
open Quasifind

(* Wrapper for run to return Cmdliner return type *)
let run root_dir expr_str_opt max_depth follow_symlinks include_hidden jobs exec_command exec_batch_command help_short =
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
            let mgr = Eio.Stdenv.process_mgr _env in
            
            (* For batch execution, we need to collect paths *)
            let batch_paths = ref [] in

            Traversal.traverse cfg root_dir typed_ast (fun entry ->
              (* 4. Eval *)
              if Eval.eval now typed_ast entry then (
                (* 5. Output / Exec *)
                match exec_command with
                | Some cmd_tmpl ->
                    (* Execute per file *)
                    Exec.run_one ~mgr ~sw:() cmd_tmpl entry.path
                | None ->
                    (* Only accumulate for batch or print if no batch *)
                    ()
                ;
                
                match exec_batch_command with
                | Some _ -> batch_paths := entry.path :: !batch_paths
                | None -> ()
                ;
                
                (* Print if no exec commands are defined *)
                if Option.is_none exec_command && Option.is_none exec_batch_command then
                   Printf.printf "%s\n%!" entry.path
              )
            );
            
            (* Batch execution *)
            (match exec_batch_command with
            | Some cmd_tmpl ->
                if !batch_paths <> [] then
                  Exec.run_batch ~mgr ~sw:() cmd_tmpl (List.rev !batch_paths)
            | None -> ());
            
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

let exec_command =
  let doc = "Execute command for each found file. {} is replaced by the path." in
  Arg.(value & opt (some string) None & info ["exec"; "x"] ~docv:"CMD" ~doc)

let exec_batch_command =
  let doc = "Execute command once with all found files as arguments. {} is replaced by all paths." in
  Arg.(value & opt (some string) None & info ["exec-batch"; "X"] ~docv:"CMD" ~doc)

let help_short =
  let doc = "Show this help." in
  Arg.(value & flag & info ["h"] ~doc)

let cmd =
  let doc = "Quasi-find: a typed, find-like filesystem query tool" in
  let info = Cmd.info "quasifind" ~version:"0.1.0" ~doc in
  Cmd.v info Term.(ret (const run $ root_dir $ expr_str $ max_depth $ follow_symlinks $ include_hidden $ jobs $ exec_command $ exec_batch_command $ help_short))

let () = exit (Cmd.eval cmd)
