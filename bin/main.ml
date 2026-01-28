open Cmdliner
open Quasifind

(* --- Search Command --- *)

let rec search root_dir expr_str_opt max_depth follow_symlinks include_hidden jobs exec_command exec_batch_command exclude profile_name save_profile_name watch_mode watch_interval watch_log webhook_url email_addr slack_url stealth_mode suspicious_mode update_rules check_ghost reset_config reset_rules help_short =
  if help_short then `Help (`Auto, None)
  else (
  (* Handle reset requests *)
  if reset_config then (
    Config.reset_to_default ();
    `Ok ()
  ) else if reset_rules then (
    Rule_loader.reset_to_default ();
    `Ok ()
  ) else if update_rules then (
    Rule_converter.update_from_source ();
    `Ok ()
  ) else (
  (* Regular Search Logic *)
  
  (* If --stealth is enabled, mask process name *)
  if stealth_mode then Stealth.enable ();

  (* If --profile is specified, load profile and use its settings *)
  match profile_name with
  | Some name ->
      (match Profile.load name with
       | Error msg -> `Error (false, msg)
       | Ok profile ->
           let actual_root = match profile.root_dir with Some r -> r | None -> root_dir in
           let actual_expr = profile.expr in
           let actual_depth = match max_depth with Some _ -> max_depth | None -> profile.max_depth in
           let actual_follow = follow_symlinks || profile.follow_symlinks in
           let actual_hidden = include_hidden || profile.include_hidden in
           let actual_exclude = profile.exclude @ exclude in
           search actual_root (Some actual_expr) actual_depth actual_follow actual_hidden jobs exec_command exec_batch_command actual_exclude None None watch_mode watch_interval watch_log webhook_url email_addr slack_url stealth_mode suspicious_mode update_rules check_ghost reset_config reset_rules false
      )
  | None ->
      (* Prepare configuration and runner *)
      let config = Config.load () in
      (* cfg construction moved inside run_logic to access domain_mgr *)

      (* Common execution logic *)
      let run_logic typed_ast =
        Eio_main.run @@ fun _env ->
        let now = Unix.gettimeofday () in
        let mgr = Eio.Stdenv.process_mgr _env in
        let domain_mgr = Eio.Stdenv.domain_mgr _env in
        let spawn_fn = fun f -> Eio.Domain_manager.run domain_mgr f in
        
        let concurrency = match jobs with | None -> 1 | Some n -> n in
        let strategy = if concurrency > 1 then Traversal.Parallel concurrency else Traversal.DFS in
        let ignore_patterns = config.ignore @ exclude in
        let ignore_re = List.map (fun p -> Re.Glob.glob p |> Re.compile) ignore_patterns in
        
        let cfg = { Traversal.strategy; max_depth; follow_symlinks; include_hidden; ignore = ignore_patterns; ignore_re; preserve_timestamps = stealth_mode; spawn = Some spawn_fn } in
        
        let batch_paths = ref [] in
        let all_found_paths = ref [] in
        
        (* Thread-safe result collection: Use a Stream with termination signal *)
        let results_stream = Eio.Stream.create 4096 in
        
        Eio.Fiber.both
          (fun () ->
             (* Consumer Fiber *)
             let rec loop () =
               match Eio.Stream.take results_stream with
               | None -> () (* End of stream *)
               | Some (entry : Eval.entry) ->
                   all_found_paths := entry.path :: !all_found_paths;
                   
                   (match exec_command with
                   | Some cmd_tmpl -> Exec.run_one ~mgr ~sw:() cmd_tmpl entry.path
                   | None -> ());
                   
                   (match exec_batch_command with
                   | Some _ -> batch_paths := entry.path :: !batch_paths
                   | None -> ());
                   
                   if Option.is_none exec_command && Option.is_none exec_batch_command then
                     Printf.printf "%s\n%!" entry.path;
                   loop ()
             in
             loop ()
          )
          (fun () ->
             (* Producer Fiber: Traversal *)
             Traversal.traverse cfg root_dir typed_ast (fun entry ->
               if Eval.eval ~preserve_timestamps:stealth_mode now typed_ast entry then (
                 Eio.Stream.add results_stream (Some entry)
               )
             );
             Eio.Stream.add results_stream None
          );
        
        (match exec_batch_command with
        | Some cmd_tmpl ->
            if !batch_paths <> [] then
              Exec.run_batch ~mgr ~sw:() cmd_tmpl (List.rev !batch_paths)
        | None -> ());
        
        History.add ~cmd:Sys.argv ~results:(List.rev !all_found_paths);
        
        if watch_mode then (
          let interval = match watch_interval with Some i -> float_of_int i | None -> 2.0 in
          let final_webhook = match webhook_url with Some _ -> webhook_url | None -> config.webhook_url in
          let final_email = match email_addr with Some _ -> email_addr | None -> config.email in
          let final_slack = match slack_url with Some _ -> slack_url | None -> config.slack_url in
          Watcher.watch_with_output ~interval ~root:root_dir ~cfg ~expr:typed_ast ?log_file:watch_log ?webhook_url:final_webhook ?email_addr:final_email ?slack_url:final_slack ()
        );
        
        if suspicious_mode || check_ghost then (
          let ghosts = Ghost.scan root_dir in
          if ghosts <> [] then (
            Printf.printf "\n[!] Ghost Files Detected (deleted but open):\n";
            List.iter (fun g -> Printf.printf "    %s\n" g) ghosts
          )
        );
        
        `Ok ()
      in

      match expr_str_opt with
      | None -> 
          if check_ghost && not suspicious_mode then
             (* Check ghost only mode - no file search needed typically, or scan all? *)
             (* Ideally we don't start traversal if only check_ghost, but structure assumes traversal. *)
             (* We can create a dummy AST "false" to skip traversal or just validly run empty search. *)
             (* Better: run logic with "false" (match nothing) so we only get ghosts. *)
             run_logic Ast.Typed.False
          else if not suspicious_mode then `Help (`Auto, None) 
          else
             (* Suspicious mode without explicit expr -> use suspicious rules *)
             let untyped_ast = Suspicious.rules () in
             (match Typecheck.check untyped_ast with
              | Error err -> `Error (false, "Type Error (Suspicious Rules): " ^ Typecheck.string_of_error err)
              | Ok typed_ast -> run_logic typed_ast)

      | Some expr_str ->
          (* Save profile if requested *)
          (match save_profile_name with
           | Some name ->
               let profile : Profile.t = {
                 root_dir = if root_dir = "." then None else Some root_dir;
                 expr = expr_str;
                 max_depth;
                 follow_symlinks;
                 include_hidden;
                 exclude;
               } in
               (match Profile.save ~name profile with
                | Ok () -> Printf.printf "Profile '%s' saved.\n%!" name
                | Error msg -> Printf.eprintf "Warning: %s\n%!" msg)
           | None -> ());

          match Parser.parse expr_str with
          | Error msg -> `Error (false, "Parse Error: " ^ msg)
          | Ok user_ast ->
              let final_ast = 
                if suspicious_mode then Ast.Untyped.And (user_ast, Suspicious.rules ())
                else user_ast
              in
              match Typecheck.check final_ast with
              | Error err -> `Error (false, "Type Error: " ^ Typecheck.string_of_error err)
              | Ok typed_ast -> run_logic typed_ast
  )
  )


(* --- History Command --- *)

(* Shell quoting helper *)
let quote_arg s =
  if s = "" then "''"
  else if String.contains s ' ' || String.contains s '"' || String.contains s '\'' || String.contains s '(' || String.contains s ')' then
    let b = Buffer.create (String.length s + 2) in
    Buffer.add_char b '\'';
    String.iter (fun c ->
      if c = '\'' then Buffer.add_string b "'\\''"
      else Buffer.add_char b c
    ) s;
    Buffer.add_char b '\'';
    Buffer.contents b
  else s

let quote_command cmd_list =
  String.concat " " (List.map quote_arg cmd_list)

let format_entry (e : History.entry) =
  let time = Unix.localtime e.timestamp in
  let time_str = Printf.sprintf "%04d-%02d-%02d %02d:%02d" 
    (time.tm_year + 1900) (time.tm_mon + 1) time.tm_mday time.tm_hour time.tm_min 
  in
  (* Reconstruct command string with quoting *)
  let cmd_str = quote_command e.command in
  Printf.sprintf "[%s] %s (%d results)" time_str cmd_str e.results_count
 
let run_history exec =
  let history = History.load () in
  if history = [] then (
    Printf.printf "No history found.\n";
    `Ok ()
  ) else
    let candidates = List.map format_entry history in
    let candidates = List.rev candidates in
    let history_rev = List.rev history in
    
    if exec then
      let config = Config.load () in
      let preview_cmd = Sys.executable_name ^ " history preview {}" in
      match Interactive.select ~finder:config.fuzzy_finder ~preview_cmd candidates with
      | Some selection ->
          let rec find_idx idx = function
            | [] -> None
            | c :: cs -> if c = selection then Some idx else find_idx (idx + 1) cs
          in
          (match find_idx 0 candidates with
           | Some idx ->
               let entry = List.nth history_rev idx in
               let cmd_str = quote_command entry.command in
               Printf.printf "%s\n" cmd_str;
               `Ok ()
           | None -> 
               Printf.eprintf "Error: Could not find selected entry in history list.\n%!";
               `Ok ()
          )
      | None -> `Ok ()
    else (
      List.iter (fun c -> Printf.printf "%s\n" c) candidates;
      `Ok ()
    )

(* History preview: display results for a given formatted history line *)
let run_history_preview line =
  let history = History.load () in
  let history_rev = List.rev history in
  let candidates = List.map format_entry history in
  let candidates = List.rev candidates in
  
  let rec find_idx idx = function
    | [] -> None
    | c :: cs -> if c = line then Some idx else find_idx (idx + 1) cs
  in
  match find_idx 0 candidates with
  | Some idx ->
      let entry = List.nth history_rev idx in
      (match entry.full_results_path with
       | Some path when Sys.file_exists path ->
           let ic = open_in path in
           (try
             while true do
               Printf.printf "%s\n" (input_line ic)
             done
           with End_of_file -> close_in ic);
           `Ok ()
       | Some _ -> 
           Printf.printf "(Results file not found)\n";
           `Ok ()
       | None ->
           Printf.printf "(No results saved for this entry)\n";
           `Ok ()
      )
  | None ->
      Printf.eprintf "Entry not found in history.\n";
      `Ok ()

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
let exclude = Arg.(value & opt_all string [] & info ["exclude"; "E"] ~docv:"PATTERN" ~doc:"Exclude files matching pattern (glob). Can be specified multiple times.")
let profile_name = Arg.(value & opt (some string) None & info ["profile"; "p"] ~docv:"NAME" ~doc:"Load a saved profile by name.")
let save_profile_name = Arg.(value & opt (some string) None & info ["save-profile"] ~docv:"NAME" ~doc:"Save current search options as a profile.")
let watch_mode = Arg.(value & flag & info ["watch"; "w"] ~doc:"Watch mode: monitor filesystem for changes.")
let watch_interval = Arg.(value & opt (some int) None & info ["interval"] ~docv:"SECONDS" ~doc:"Watch interval in seconds (default: 2).")
let watch_log = Arg.(value & opt (some string) None & info ["log"] ~docv:"FILE" ~doc:"Log file for watch events.")
let webhook_url = Arg.(value & opt (some string) None & info ["notify-url"] ~docv:"URL" ~doc:"Webhook URL for notifications (HTTP POST with JSON).")
let email_addr = Arg.(value & opt (some string) None & info ["notify-email"] ~docv:"EMAIL" ~doc:"Email address for notifications (requires mail command).")
let slack_url = Arg.(value & opt (some string) None & info ["slack-webhook"] ~docv:"URL" ~doc:"Slack incoming webhook URL.")
let stealth_mode = Arg.(value & flag & info ["stealth"] ~doc:"Stealth mode: mask process name from system tools.")
let suspicious_mode = Arg.(value & flag & info ["suspicious"] ~doc:"Suspicious mode: search for potentially dangerous files using built-in rules.")
let update_rules = Arg.(value & flag & info ["update-rules"] ~doc:"Download and update heuristic rules from trusted source.")
let check_ghost = Arg.(value & flag & info ["check-ghost"] ~doc:"Detect deleted files that are still open.")
let reset_config = Arg.(value & flag & info ["reset-config"] ~doc:"Reset configuration file to default.")
let reset_rules = Arg.(value & flag & info ["reset-rules"] ~doc:"Reset heuristic rules to default.")
let help_short = Arg.(value & flag & info ["h"] ~doc:"Show this help.")

let search_t = Term.(ret (const search $ root_dir $ expr_str $ max_depth $ follow_symlinks $ include_hidden $ jobs $ exec_command $ exec_batch_command $ exclude $ profile_name $ save_profile_name $ watch_mode $ watch_interval $ watch_log $ webhook_url $ email_addr $ slack_url $ stealth_mode $ suspicious_mode $ update_rules $ check_ghost $ reset_config $ reset_rules $ help_short))

let search_info = Cmd.info "quasifind" ~doc:"Quasi-find: a typed, find-like filesystem query tool" ~version:"0.1.0"

(* History args *)
let history_exec = Arg.(value & flag & info ["exec"; "e"] ~doc:"Select and output a command from history to stdout.")
let history_t = Term.(ret (const run_history $ history_exec))
let history_info = Cmd.info "quasifind history" ~doc:"Show or execute command history"

(* History preview args *)
let history_preview_line = Arg.(required & pos 0 (some string) None & info [] ~docv:"LINE" ~doc:"The formatted history line to preview.")
let history_preview_t = Term.(ret (const run_history_preview $ history_preview_line))
let history_preview_info = Cmd.info "quasifind history preview" ~doc:"Preview results for a history entry"

let () = 
  let argv = Sys.argv in
  let n = Array.length argv in
  if n > 2 && argv.(1) = "history" && argv.(2) = "preview" then
    (* Shift argv for history preview: PROGRAM history preview args... *)
    let new_argv = Array.init (n - 2) (fun i -> if i = 0 then argv.(0) else argv.(i+2)) in
    exit (Cmd.eval ~argv:new_argv (Cmd.v history_preview_info history_preview_t))
  else if n > 1 && argv.(1) = "history" then
    let new_argv = Array.init (n - 1) (fun i -> if i = 0 then argv.(0) else argv.(i+1)) in
    exit (Cmd.eval ~argv:new_argv (Cmd.v history_info history_t))
  else if n > 1 && argv.(1) = "search" then
    let new_argv = Array.init (n - 1) (fun i -> if i = 0 then argv.(0) else argv.(i+1)) in
    exit (Cmd.eval ~argv:new_argv (Cmd.v search_info search_t))
  else
    exit (Cmd.eval (Cmd.v search_info search_t))
