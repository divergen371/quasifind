open Cmdliner
open Quasifind

(* --- Search Command --- *)

let rec search root_dir expr_str_opt max_depth follow_symlinks include_hidden parallel_mode exec_command exec_batch_command exclude profile_name save_profile_name watch_mode watch_interval watch_log webhook_url email_addr slack_url suspicious_mode update_rules check_ghost reset_config reset_rules integrity daemon_mode help_short output_format color_mode interactive_mode ls_mode name_opt iname_opt ext_opt type_opt size_opt mtime_opt content_opt =
  if help_short then `Help (`Auto, None)
  else (
  
  (* Self Integrity Check *)
  if ls_mode then (
    let bulk_res = Dirent.readdir_bulk root_dir in
    Array.sort (fun (n1, _, _, _, _, _, _) (n2, _, _, _, _, _, _) ->
      String.compare (String.lowercase_ascii n1) (String.lowercase_ascii n2)
    ) bulk_res;
    
    let format_mode mode kind =
      let rwxrwxrwx = [
        (0o400, 'r'); (0o200, 'w'); (0o100, 'x');
        (0o040, 'r'); (0o020, 'w'); (0o010, 'x');
        (0o004, 'r'); (0o002, 'w'); (0o001, 'x');
      ] in
      let chars = List.map (fun (mask, ch) -> if mode land mask <> 0 then ch else '-') rwxrwxrwx in
      let kind_ch = match kind with
        | Dirent.Dir -> 'd'
        | Dirent.Symlink -> 'l'
        | _ -> '.'
      in
      String.make 1 kind_ch ^ String.of_seq (List.to_seq chars)
    in
    
    let format_size size =
      if size < 0 then "? B"
      else if size < 1024 then Printf.sprintf "%d B" size
      else if size < 1024 * 1024 then Printf.sprintf "%.1f KB" (float_of_int size /. 1024.)
      else if size < 1024 * 1024 * 1024 then Printf.sprintf "%.1f MB" (float_of_int size /. 1048576.)
      else Printf.sprintf "%.1f GB" (float_of_int size /. 1073741824.)
    in

    let get_user_name uid = try (Unix.getpwuid uid).pw_name with Not_found -> string_of_int uid in
    let get_group_name gid = try (Unix.getgrgid gid).gr_name with Not_found -> string_of_int gid in

    let format_time mtime =
      if mtime < 0 then "Unknown date"
      else
        let tm = Unix.localtime (float_of_int mtime) in
        let months = [|"Jan"; "Feb"; "Mar"; "Apr"; "May"; "Jun"; "Jul"; "Aug"; "Sep"; "Oct"; "Nov"; "Dec"|] in
        let wdays = [|"Sun"; "Mon"; "Tue"; "Wed"; "Thu"; "Fri"; "Sat"|] in
        Printf.sprintf "%s %s %2d %02d:%02d:%02d %d" 
          wdays.(tm.tm_wday) months.(tm.tm_mon) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec (tm.tm_year + 1900)
    in

    let len = Array.length bulk_res in
    for i = 0 to len - 1 do
      let (name, kind, size, mtime, mode, uid, gid) = Array.unsafe_get bulk_res i in
      let mode_str = format_mode mode kind in
      let size_str = format_size size in
      let time_str = format_time mtime in
      let user = get_user_name uid in
      let group = get_group_name gid in
      Printf.printf "%s %-8s %-8s %7s  %s  %s\n" mode_str user group size_str time_str name
    done;
    `Ok ()
  ) else if integrity then (
    let my_path = Sys.executable_name in
    let cmd = Printf.sprintf "shasum -a 256 '%s' 2>/dev/null | awk '{print $1}'" my_path in
    let ic = Unix.open_process_in cmd in
    let hash = try input_line ic with End_of_file -> "unknown" in
    ignore (Unix.close_process_in ic);
    Printf.printf "%s  %s\n" hash my_path;
    `Ok ()
  ) else (
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
           search actual_root (Some actual_expr) actual_depth actual_follow actual_hidden parallel_mode exec_command exec_batch_command actual_exclude None None watch_mode watch_interval watch_log webhook_url email_addr slack_url suspicious_mode update_rules check_ghost reset_config reset_rules false false false output_format color_mode interactive_mode ls_mode None None None None None None None
      )
  | None ->
      (* Prepare configuration and runner *)
      let config = Config.load () in
      (* cfg construction moved inside run_logic to access domain_mgr *)

      (* Common execution logic *)
      let run_logic typed_ast =
        Eio_main.run @@ fun env ->
        Eio.Switch.run @@ fun sw ->
        let now = Unix.gettimeofday () in
        let mgr = Eio.Stdenv.process_mgr env in
        let domain_mgr = Eio.Stdenv.domain_mgr env in
        let spawn_fn = fun f -> Eio.Domain_manager.run domain_mgr f in
        
        let is_macos = 
          let ic = Unix.open_process_in "uname -s" in
          let os = try input_line ic with End_of_file -> "" in
          ignore (Unix.close_process_in ic);
          String.trim os = "Darwin"
        in
        
        let concurrency = 
          if not parallel_mode then 1
          else
            let num_cores = Domain.recommended_domain_count () in
            if is_macos then min num_cores 4 (* Cap at 4 on macOS to prevent VFS lock contention *)
            else num_cores
        in
        let strategy = if concurrency > 1 then Traversal.Parallel concurrency else Traversal.DFS in
        let ignore_patterns = config.ignore @ exclude in
        let ignore_re = List.map (fun p -> Re.Glob.glob p |> Re.compile) ignore_patterns in
        
        let cfg = { Traversal.strategy; max_depth; follow_symlinks; include_hidden; ignore = ignore_patterns; ignore_re; preserve_timestamps = false; spawn = Some spawn_fn } in
        
        let batch_paths = ref [] in
        let all_found_paths = ref [] in
        let fmt = match Formatter.parse_format output_format with Some f -> f | None -> Formatter.Default in
        let clr = match Formatter.parse_color color_mode with Some c -> c | None -> Formatter.Auto in
        let is_first_json = ref true in
        
        (* Print header if needed *)
        (match Formatter.format_header ~format:fmt with
         | Some h -> Printf.printf "%s\n" h
         | None -> ());
        (if fmt = Formatter.Json then Printf.printf "%s\n" (Formatter.format_json_start ()));
        
        (* Thread-safe result collection: Use a Stream with termination signal *)
        let results_stream = Eio.Stream.create 4096 in
        
        let interactive_candidates = ref [] in

        Eio.Fiber.both
          (fun () ->
             (* Consumer Fiber *)
             let rec loop () =
               match Eio.Stream.take results_stream with
               | None -> () (* End of stream *)
               | Some (entry : Eval.entry) ->
                   all_found_paths := entry.path :: !all_found_paths;
                   
                   if interactive_mode then (
                     interactive_candidates := entry.path :: !interactive_candidates
                   ) else (
                     (match exec_command with
                     | Some cmd_tmpl -> Exec.run_one ~mgr ~sw:() cmd_tmpl entry.path
                     | None -> ());
                     
                     (match exec_batch_command with
                     | Some _ -> batch_paths := entry.path :: !batch_paths
                     | None -> ());
                     
                     if Option.is_none exec_command && Option.is_none exec_batch_command then (
                       let line = Formatter.format_entry ~format:fmt ~color:clr entry in
                       (match fmt with
                        | Formatter.Json ->
                            if !is_first_json then is_first_json := false
                            else Printf.printf ",\n";
                            Printf.printf "%s%!" line
                        | Formatter.Null ->
                            Printf.printf "%s\000%!" line
                        | _ ->
                            Printf.printf "%s\n%!" line)
                     )
                   );
                   loop ()
             in
             loop ()
          )
          (fun () ->
             (* Producer Fiber: Traversal or Daemon Query *)
             let use_daemon = 
               watch_mode = false && daemon_mode
             in

             let used_daemon = ref false in
             
             if use_daemon then (
               (* Warn about ignored options in daemon mode *)
               if parallel_mode then
                 Printf.eprintf "[Warning] -j/--parallel is ignored in daemon mode (daemon uses its own parallelism)\n%!";
               if Option.is_some max_depth then
                 Printf.eprintf "[Warning] -d/--max-depth is ignored in daemon mode\n%!";
               if follow_symlinks then
                 Printf.eprintf "[Warning] -L/--follow is ignored in daemon mode\n%!";
               if include_hidden then
                 Printf.eprintf "[Info] --hidden enabled. Fetching hidden records from daemon.\n%!"
               else
                 Printf.eprintf "[Info] Hiding dotfiles from daemon results (--hidden not supplied).\n%!";
               if exclude <> [] then
                 Printf.eprintf "[Warning] -E/--exclude is ignored in daemon mode (use daemon config)\n%!";
               
               let socket = Ipc.socket_path () in
               if Sys.file_exists socket then (
                 Printf.eprintf "[Info] Querying daemon...\n%!";
                 
                 let daemon_ast = 
                   if include_hidden then typed_ast
                   else
                     let hidden_re = Re.compile (Re.Pcre.re "(^|/)\\.") in
                     Ast.Typed.And (Ast.Typed.Not (Ast.Typed.Path (Ast.Typed.StrRe ("(^|/)\\.", hidden_re))), typed_ast)
                 in

                 match Ipc.Client.query ~sw ~net:env#net daemon_ast with
                 | Ok entries ->
                     List.iter (fun e -> 
                       (* Support --exec in daemon client mode *)
                       if not interactive_mode then (
                         (match exec_command with
                         | Some cmd_tmpl -> Exec.run_one ~mgr ~sw:() cmd_tmpl e.Eval.path
                         | None -> ());
                       );
                       Eio.Stream.add results_stream (Some e)
                     ) entries;
                     used_daemon := true
                 | Error msg ->
                     Printf.eprintf "[Warning] Daemon query failed: %s. Falling back to local search.\n%!" msg
               ) else (
                 Printf.eprintf "[Warning] Daemon socket not found. Falling back to local search.\n%!"
               )
             );

             if not !used_daemon then (
               Traversal.traverse cfg root_dir typed_ast (fun entry ->
                 if Eval.eval ~preserve_timestamps:false now typed_ast entry then (
                   Eio.Stream.add results_stream (Some entry)
                 )
               )
             );
             Eio.Stream.add results_stream None
          );
        
        (* Print JSON footer if needed *)
        (if fmt = Formatter.Json && not interactive_mode then (
          if not !is_first_json then Printf.printf "\n";
          Printf.printf "%s\n" (Formatter.format_json_end ())
        ));
         
        if interactive_mode then (
          let candidates = List.rev !interactive_candidates in
          if candidates = [] then (
            Printf.eprintf "No results found.\n"
          ) else (
             let preview_cmd = match exec_command, exec_batch_command with
               | None, None -> Some "head -n 100 {} 2>/dev/null || echo \"Not a readable file\""
               | Some _, _ | None, Some _ -> None
             in
            match Interactive.select ~finder:Config.Builtin ?preview_cmd candidates with
            | Some selection ->
                (match exec_command with
                 | Some cmd_tmpl -> Exec.run_one ~mgr ~sw:() cmd_tmpl selection
                 | None ->
                     (match exec_batch_command with
                      | Some cmd_tmpl -> Exec.run_batch ~mgr ~sw:() cmd_tmpl [selection]
                      | None -> Printf.printf "%s\n%!" selection)
                )
            | None -> ()
          )
        ) else (
          (match exec_batch_command with
          | Some cmd_tmpl ->
              if !batch_paths <> [] then
                Exec.run_batch ~mgr ~sw:() cmd_tmpl (List.rev !batch_paths)
          | None -> ());
        );
        
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

      let final_expr_str_opt = 
        let components = ref [] in
        let escape_regex s =
          let buf = Buffer.create (String.length s * 2) in
          String.iter (function
            | '*' -> Buffer.add_string buf ".*"
            | '?' -> Buffer.add_char buf '.'
            | '.' | '+' | '(' | ')' | '[' | ']' | '^' | '$' | '\\' | '|' as c -> 
                Buffer.add_char buf '\\'; Buffer.add_char buf c
            | c -> Buffer.add_char buf c) s;
          Buffer.contents buf
        in
        
        (match name_opt with
         | Some p -> components := Printf.sprintf "name =~ /^%s$/" (escape_regex p) :: !components
         | None -> ());
         
        (match iname_opt with
         | Some p -> components := Printf.sprintf "name =~ /(?i)^%s$/" (escape_regex p) :: !components
         | None -> ());
         
        (match ext_opt with
         | Some e ->
             let e_clean = if String.starts_with ~prefix:"." e then String.sub e 1 (String.length e - 1) else e in
             (* Use RegexLiteral to bypass quoted_string's backslash stripping issues *)
             components := Printf.sprintf "name =~ /.*\\.%s$/" (escape_regex e_clean) :: !components
         | None -> ());
         
        (match type_opt with
         | Some "f" | Some "file" -> components := "type == file" :: !components
         | Some "d" | Some "dir" -> components := "type == dir" :: !components
         | Some "l" | Some "symlink" -> components := "type == symlink" :: !components
         | Some t -> Printf.eprintf "[Warning] unknown type '%s' (use f, d, or l)\n%!" t
         | None -> ());
         
        let needs_type_file = ref false in
        
        (match size_opt with
         | Some s ->
             needs_type_file := true;
             if String.starts_with ~prefix:"+" s then
               components := Printf.sprintf "size > %s" (String.sub s 1 (String.length s - 1)) :: !components
             else if String.starts_with ~prefix:"-" s then
               components := Printf.sprintf "size < %s" (String.sub s 1 (String.length s - 1)) :: !components
             else
               components := Printf.sprintf "size == %s" s :: !components
         | None -> ());

        (match mtime_opt with
         | Some m ->
             if String.starts_with ~prefix:"+" m then
               components := Printf.sprintf "mtime > %s" (String.sub m 1 (String.length m - 1)) :: !components
             else if String.starts_with ~prefix:"-" m then
               components := Printf.sprintf "mtime < %s" (String.sub m 1 (String.length m - 1)) :: !components
             else
               components := Printf.sprintf "mtime == %s" m :: !components
         | None -> ());

        (match content_opt with
         | Some c ->
             needs_type_file := true;
             components := Printf.sprintf "content =~ \"%s\"" c :: !components
         | None -> ());

        if !needs_type_file && type_opt = None then
          components := "type == file" :: !components;
          
        match List.rev !components, expr_str_opt with
        | [], None -> None
        | [], Some e -> Some e
        | cs, None -> Some (String.concat " && " cs)
        | cs, Some e -> Some ("(" ^ String.concat " && " cs ^ ") && (" ^ e ^ ")")
      in

      match final_expr_str_opt with
      | None -> 
          if check_ghost && not suspicious_mode then
             run_logic Ast.Typed.False
          else if not suspicious_mode then `Help (`Auto, None) 
          else
             let untyped_ast = Suspicious.rules () in
             (match Typecheck.check untyped_ast with
              | Error err -> `Error (false, "Type Error (Suspicious Rules): " ^ Qerror.to_string err)
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
          | Error msg -> `Error (false, "Parse Error: " ^ Qerror.to_string msg)
          | Ok user_ast ->
              let final_ast = 
                if suspicious_mode then Ast.Untyped.And (user_ast, Suspicious.rules ())
                else user_ast
              in
              match Typecheck.check final_ast with
              | Error err -> `Error (false, "Type Error: " ^ Qerror.to_string err)
              | Ok typed_ast -> run_logic typed_ast
  )
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
let expr_str = Arg.(value & pos 1 (some string) None & info [] ~docv:"EXPR" ~doc:"DSL expression. Optional if flags like -n or -s are used.")

(* Syntax sugar flags *)
let name_opt = Arg.(value & opt (some string) None & info ["name"; "n"] ~docv:"PATTERN" ~doc:"Search by filename glob pattern.")
let iname_opt = Arg.(value & opt (some string) None & info ["iname"] ~docv:"PATTERN" ~doc:"Case-insensitive search by filename glob pattern.")
let ext_opt = Arg.(value & opt (some string) None & info ["ext"; "e"] ~docv:"EXT" ~doc:"Search by extension (e.g., txt or .txt).")
let type_opt = Arg.(value & opt (some string) None & info ["type"; "t"] ~docv:"TYPE" ~doc:"File type: f (file), d (dir), l (symlink).")
let size_opt = Arg.(value & opt (some string) None & info ["size"; "s"] ~docv:"SIZE" ~doc:"Search by size (+1MB, -1KB). Implicitly filters for files.")
let mtime_opt = Arg.(value & opt (some string) None & info ["mtime"; "m"] ~docv:"TIME" ~doc:"Search by modification time (-7d, +1M).")
let content_opt = Arg.(value & opt (some string) None & info ["content"; "c"] ~docv:"REGEX" ~doc:"Search file content matches regex. Implicitly filters for files.")
let max_depth = Arg.(value & opt (some int) None & info ["max-depth"; "d"] ~docv:"DEPTH" ~doc:"Maximum depth to traverse.")
let follow_symlinks = Arg.(value & flag & info ["follow"; "L"] ~doc:"Follow symbolic links.")
let include_hidden = Arg.(value & flag & info ["hidden"; "H"] ~doc:"Include hidden files and directories.")
let parallel_mode = Arg.(value & flag & info ["parallel"; "j"] ~doc:"Enable parallel search mode (automatically scales threads optimally).")
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

let suspicious_mode = Arg.(value & flag & info ["suspicious"] ~doc:"Suspicious mode: search for potentially dangerous files using built-in rules.")
let update_rules = Arg.(value & flag & info ["update-rules"] ~doc:"Download and update heuristic rules from trusted source.")
let check_ghost = Arg.(value & flag & info ["check-ghost"] ~doc:"Detect deleted files that are still open.")
let reset_config = Arg.(value & flag & info ["reset-config"] ~doc:"Reset configuration file to default.")
let reset_rules = Arg.(value & flag & info ["reset-rules"] ~doc:"Reset heuristic rules to default.")
let integrity = Arg.(value & flag & info ["integrity"; "I"] ~doc:"Print the SHA256 hash of this executable for verification.")
let daemon_mode = Arg.(value & flag & info ["daemon"] ~doc:"Query the running daemon instead of scanning disk. Requires 'quasifind daemon' to be running. Much faster for repeated queries.")
let help_short = Arg.(value & flag & info ["h"] ~doc:"Show this help.")
let output_format = Arg.(value & opt string "default" & info ["format"; "f"] ~docv:"FORMAT" ~doc:"Output format: default, json, csv, table, null.")
let color_mode = Arg.(value & opt string "auto" & info ["color"] ~docv:"MODE" ~doc:"Color mode: always, auto, never.")
let interactive_mode = Arg.(value & flag & info ["interactive"; "i"] ~doc:"Interactive mode: use fuzzy finder to select a single result.")
let ls_mode = Arg.(value & flag & info ["ls"; "list"] ~doc:"Bulk list directory contents rapidly (file manager mode).")

(* --- Daemon Command (Experimental) --- *)
let daemon_info = Cmd.info "daemon" 
  ~doc:"Start the Quasifind daemon."
  ~man:[`S "DESCRIPTION";
        `P "Start a background daemon that maintains a VFS (Virtual File System) in memory for fast queries.";
        `P "The daemon uses an Adaptive Radix Tree (ART) for efficient path lookups and watches for file system changes in real-time.";
        `S "FEATURES";
        `P "- Persistent cache: VFS is saved to ~/.cache/quasifind/daemon.dump on shutdown";
        `P "- Query-based pruning: Skips irrelevant directories during search";
        `P "- Hybrid search: Metadata from VFS, content/entropy from disk";
        `S "USAGE";
        `P "Start: quasifind daemon &";
        `P "Query: quasifind . 'name =~ /[.]ml/' --daemon";
        `P "Stop: pkill -f 'quasifind daemon' or send shutdown via IPC"]

let daemon_t = Term.(const (fun () -> Daemon.run ~root:".") $ const ())

let search_t = Term.(ret (const search $ root_dir $ expr_str $ max_depth $ follow_symlinks $ include_hidden $ parallel_mode $ exec_command $ exec_batch_command $ exclude $ profile_name $ save_profile_name $ watch_mode $ watch_interval $ watch_log $ webhook_url $ email_addr $ slack_url $ suspicious_mode $ update_rules $ check_ghost $ reset_config $ reset_rules $ integrity $ daemon_mode $ help_short $ output_format $ color_mode $ interactive_mode $ ls_mode $ name_opt $ iname_opt $ ext_opt $ type_opt $ size_opt $ mtime_opt $ content_opt))

let search_info = Cmd.info "quasifind" ~doc:"Quasi-find: a typed, find-like filesystem query tool" ~version:"1.1.0"

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
  else if n > 2 && argv.(1) = "daemon" && argv.(2) = "stop" then
    (* Daemon stop command *)
    Eio_main.run @@ fun env ->
    Eio.Switch.run @@ fun sw ->
      (match Ipc.Client.shutdown ~sw ~net:env#net with
      | Ok msg -> Printf.printf "%s\n" msg; exit 0
      | Error msg -> 
          if String.length msg > 0 && (String.sub msg 0 (min 7 (String.length msg)) = "Eio.Io " || String.sub msg 0 (min 14 (String.length msg)) = "Unix.Unix_error") then
            Printf.eprintf "Error: Daemon is not running. Start it with: quasifind daemon\n"
          else
            Printf.eprintf "Error: %s\n" msg;
          exit 1)
  else if n > 2 && argv.(1) = "daemon" && argv.(2) = "stats" then
    (* Daemon stats command *)
    Eio_main.run @@ fun env ->
    Eio.Switch.run @@ fun sw ->
      (match Ipc.Client.stats ~sw ~net:env#net with
      | Ok json ->
          let open Yojson.Safe.Util in
          let nodes = json |> member "nodes" |> to_int_option |> Option.value ~default:0 in
          let root = json |> member "root" |> to_string_option |> Option.value ~default:"?" in
          let heap_mb = json |> member "heap_mb" |> to_float_option |> Option.value ~default:0.0 in
          let uptime = json |> member "uptime_sec" |> to_float_option |> Option.value ~default:0.0 in
          let last_scan = json |> member "last_scan" |> to_float_option |> Option.value ~default:0.0 in
          let uptime_h = int_of_float (uptime /. 3600.0) in
          let uptime_m = int_of_float (mod_float (uptime /. 60.0) 60.0) in
          let uptime_s = int_of_float (mod_float uptime 60.0) in
          Printf.printf "Quasifind Daemon Status\n";
          Printf.printf "  Root:       %s\n" root;
          Printf.printf "  Nodes:      %d\n" nodes;
          Printf.printf "  Heap:       %.2f MB\n" heap_mb;
          Printf.printf "  Uptime:     %02d:%02d:%02d\n" uptime_h uptime_m uptime_s;
          Printf.printf "  Last Scan:  %s\n" (let t = Unix.localtime last_scan in Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d" (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec);
          exit 0
      | Error msg ->
          if String.length msg > 0 && (String.sub msg 0 (min 7 (String.length msg)) = "Eio.Io " || String.sub msg 0 (min 14 (String.length msg)) = "Unix.Unix_error") then
            Printf.eprintf "Error: Daemon is not running. Start it with: quasifind daemon\n"
          else
            Printf.eprintf "Error: %s\n" msg;
          exit 1)
  else if n > 1 && (argv.(1) = "daemon" || argv.(1) = "--daemon") then
    let new_argv = Array.init (n - 1) (fun i -> if i = 0 then argv.(0) else argv.(i+1)) in
    exit (Cmd.eval ~argv:new_argv (Cmd.v daemon_info daemon_t))
  else if n > 1 && argv.(1) = "search" then
    let new_argv = Array.init (n - 1) (fun i -> if i = 0 then argv.(0) else argv.(i+1)) in
    exit (Cmd.eval ~argv:new_argv (Cmd.v search_info search_t))
  else
    exit (Cmd.eval (Cmd.v search_info search_t))
