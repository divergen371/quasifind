open Cmdliner
open Quasifind

(* --- Search Command --- *)

let search root_dir expr_str_opt max_depth follow_symlinks include_hidden jobs exec_command exec_batch_command help_short =
  if help_short then `Help (`Auto, None)
  else match expr_str_opt with
  | None -> `Help (`Auto, None)
  | Some expr_str ->
    let concurrency = match jobs with | None -> 1 | Some n -> n in
    let strategy = if concurrency > 1 then Traversal.Parallel concurrency else Traversal.DFS in
    let config = Config.load () in
    let cfg = { Traversal.strategy; max_depth; follow_symlinks; include_hidden; ignore = config.ignore } in

    match Parser.parse expr_str with
    | Error msg -> `Error (false, "Parse Error: " ^ msg)
    | Ok untyped_ast ->
        match Typecheck.check untyped_ast with
        | Error err -> `Error (false, "Type Error: " ^ Typecheck.string_of_error err)
        | Ok typed_ast ->
            Eio_main.run @@ fun _env ->
            let now = Unix.gettimeofday () in
            let mgr = Eio.Stdenv.process_mgr _env in
            
            let batch_paths = ref [] in
            let all_found_paths = ref [] in (* For history *)

            Traversal.traverse cfg root_dir typed_ast (fun entry ->
              if Eval.eval now typed_ast entry then (
                (* Collect for history *)
                all_found_paths := entry.path :: !all_found_paths;

                match exec_command with
                | Some cmd_tmpl -> Exec.run_one ~mgr ~sw:() cmd_tmpl entry.path
                | None -> ();
                
                match exec_batch_command with
                | Some _ -> batch_paths := entry.path :: !batch_paths
                | None -> ();
                
                if Option.is_none exec_command && Option.is_none exec_batch_command then
                   Printf.printf "%s\n%!" entry.path
              )
            );
            
            (match exec_batch_command with
            | Some cmd_tmpl ->
                if !batch_paths <> [] then
                  Exec.run_batch ~mgr ~sw:() cmd_tmpl (List.rev !batch_paths)
            | None -> ());
            
            (* Save History *)
            History.add ~cmd:Sys.argv ~results:(List.rev !all_found_paths);
            
            `Ok ()

(* --- History Command --- *)

let format_entry (e : History.entry) =
  let time = Unix.localtime e.timestamp in
  let time_str = Printf.sprintf "%04d-%02d-%02d %02d:%02d" 
    (time.tm_year + 1900) (time.tm_mon + 1) time.tm_mday time.tm_hour time.tm_min 
  in
  (* Reconstruct command string from list *)
  (* Skip first arg if it is executable path? usually ["quasifind"; "." ...] *)
  let cmd_str = String.concat " " e.command in
  Printf.sprintf "[%s] %s (%d results)" time_str cmd_str e.results_count

let run_history exec =
  let history = History.load () in
  if history = [] then (
    Printf.printf "No history found.\n";
    `Ok ()
  ) else
    let candidates = List.map format_entry history in
    (* Show latest first? they are loaded from append log, so last is latest. *)
    (* History.load implementation reverses lines? 
       In History.ml: `lines := line :: !lines` (reverses order read) 
       Then `(List.rev !lines)` (restores file order: oldest first).
       Then `List.filter_map ...`.
       So `history` list is Oldest -> Latest.
       User usually wants Latest first.
    *)
    let candidates = List.rev candidates in
    let history_rev = List.rev history in
    
    if exec then
      let config = Config.load () in
      match Interactive.select ~finder:config.fuzzy_finder candidates with
      | Some selection ->
          let rec find_idx idx = function
            | [] -> None
            | c :: cs -> if c = selection then Some idx else find_idx (idx + 1) cs
          in
          (match find_idx 0 candidates with
           | Some idx ->
               let entry = List.nth history_rev idx in
               let prog_in_history = List.hd entry.command in
               let args = Array.of_list entry.command in
               
               (* Try to be smart about the executable path.
                  If the history command looks like it was "quasifind" or the current executable,
                  use the current running binary to ensure it exists. *)
               let prog_to_run =
                 if Filename.basename prog_in_history = "main.exe" || Filename.basename prog_in_history = "quasifind" then
                   Sys.executable_name
                 else
                   prog_in_history
               in
               
               (* args.(0) should conventionally be the program name.
                  If we change prog_to_run, we might want to update args.(0) too, but execvp uses prog argument for file. *)
               
               (try Unix.execvp prog_to_run args 
                with Unix.Unix_error (err, fn, p) ->
                  Printf.eprintf "Execution failed: %s (function: %s, path: %s)\n" (Unix.error_message err) fn p;
                  `Error (false, "Execution failed")
               )
           | None -> `Ok ()
          )
      | None -> `Ok ()
    else (
      List.iter (fun c -> Printf.printf "%s\n" c) candidates;
      `Ok ()
    )

(* --- CLI Definitions --- *)

(* --- CLI Definitions --- *)

(* Shared args for search *)
let root_dir = Arg.(value & pos 0 string "." & info [] ~docv:"DIR" ~doc:"Root directory to search.")
let expr_str = Arg.(value & pos 1 (some string) None & info [] ~docv:"EXPR" ~doc:"DSL expression. Required unless -h is used.")
let max_depth = Arg.(value & opt (some int) None & info ["max-depth"; "d"] ~docv:"DEPTH" ~doc:"Maximum depth to traverse.")
let follow_symlinks = Arg.(value & flag & info ["follow"; "L"] ~doc:"Follow symbolic links.")
let include_hidden = Arg.(value & flag & info ["hidden"; "H"] ~doc:"Include hidden files and directories.")
let jobs = Arg.(value & opt (some int) None & info ["jobs"; "j"] ~docv:"JOBS" ~doc:"Number of parallel jobs.")
let exec_command = Arg.(value & opt (some string) None & info ["exec"; "x"] ~docv:"CMD" ~doc:"Execute command per file.")
let exec_batch_command = Arg.(value & opt (some string) None & info ["exec-batch"; "X"] ~docv:"CMD" ~doc:"Execute command batch.")
let help_short = Arg.(value & flag & info ["h"] ~doc:"Show this help.")

let search_t = Term.(ret (const search $ root_dir $ expr_str $ max_depth $ follow_symlinks $ include_hidden $ jobs $ exec_command $ exec_batch_command $ help_short))

let search_info = Cmd.info "quasifind" ~doc:"Quasi-find: a typed, find-like filesystem query tool" ~version:"0.1.0"

(* History args *)
let history_exec = Arg.(value & flag & info ["exec"; "e"] ~doc:"Select and execute a command from history.")
let history_t = Term.(ret (const run_history $ history_exec))
let history_info = Cmd.info "quasifind history" ~doc:"Show or execute command history"

let () = 
  let argv = Sys.argv in
  let n = Array.length argv in
  if n > 1 && argv.(1) = "history" then
    (* Shift argv for history command: PROGRAM history args... -> PROGRAM args... *)
    let new_argv = Array.init (n - 1) (fun i -> if i = 0 then argv.(0) else argv.(i+1)) in
    exit (Cmd.eval ~argv:new_argv (Cmd.v history_info history_t))
  else if n > 1 && argv.(1) = "search" then
    (* Shift argv for search command: PROGRAM search args... -> PROGRAM args... *)
    let new_argv = Array.init (n - 1) (fun i -> if i = 0 then argv.(0) else argv.(i+1)) in
    exit (Cmd.eval ~argv:new_argv (Cmd.v search_info search_t))
  else
    exit (Cmd.eval (Cmd.v search_info search_t))
