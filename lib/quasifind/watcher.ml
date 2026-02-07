(* Watcher module - polling-based filesystem monitoring *)

type watch_config = {
  interval : float;  (* seconds between scans *)
  root : string;
  traversal_config : Traversal.config;
  expr : Ast.Typed.expr;
}

(* State for tracking file modifications *)
type file_state = {
  path : string;
  mtime : float;
  perm : int;
}

(* Event types for logging/notifications *)
type event_type = New | Modified | Deleted

let string_of_event = function
  | New -> "NEW"
  | Modified -> "MODIFIED"
  | Deleted -> "DELETED"

module StringMap = Map.Make(String)

let scan_files config =
  let files = ref StringMap.empty in
  let now = Unix.gettimeofday () in
  Traversal.traverse config.traversal_config config.root config.expr (fun entry ->
    (* Check if mtime is absent (0.0) due to Traversal optimization.
       If so, we must stat it now to track changes properly. *)
    let entry_with_meta = 
       if entry.mtime = 0.0 then 
         match Unix.lstat entry.path with
         | s -> { entry with mtime = s.st_mtime; perm = s.st_perm; size = Int64.of_int s.st_size } 
         | exception _ -> entry (* If stat fails, rely on dummy (likely error or transient) *)
       else entry
    in

    if Eval.eval ~preserve_timestamps:config.traversal_config.preserve_timestamps now config.expr entry_with_meta then
      files := StringMap.add entry_with_meta.path { path = entry_with_meta.path; mtime = entry_with_meta.mtime; perm = entry_with_meta.perm } !files
  );
  (* Printf.eprintf "[DEBUG] Scan complete. Found %d files.\n%!" (StringMap.cardinal !files); *)
  !files

(* Log event to file if log_channel is provided *)
let log_event ?log_channel event_type path =
  let timestamp = 
    let t = Unix.localtime (Unix.gettimeofday ()) in
    Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
      (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec
  in
  let line = Printf.sprintf "[%s] [%s] %s\n" timestamp (string_of_event event_type) path in
  match log_channel with
  | Some oc -> output_string oc line; flush oc
  | None -> ()

(* Send webhook notification via curl (fire and forget) *)
let send_webhook ?webhook_url event_type path =
  match webhook_url with
  | None -> ()
  | Some url ->
      let timestamp = 
        let t = Unix.localtime (Unix.gettimeofday ()) in
        Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d"
          (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec
      in
      let json = Printf.sprintf {|{"event":"%s","path":"%s","timestamp":"%s"}|}
        (string_of_event event_type) path timestamp in
      let cmd = Printf.sprintf "curl -s -X POST -H 'Content-Type: application/json' -d '%s' '%s' > /dev/null 2>&1 &" 
        json url in
      ignore (Unix.system cmd)

(* Send email notification via mail command *)
let send_email ?email_addr event_type path =
  match email_addr with
  | None -> ()
  | Some addr ->
      let subject = Printf.sprintf "[quasifind] %s: %s" (string_of_event event_type) (Filename.basename path) in
      let body = Printf.sprintf "Event: %s\nPath: %s\nTime: %s"
        (string_of_event event_type) path 
        (let t = Unix.localtime (Unix.gettimeofday ()) in
         Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
           (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec) in
      let cmd = Printf.sprintf "echo '%s' | mail -s '%s' '%s' > /dev/null 2>&1 &" body subject addr in
      ignore (Unix.system cmd)

(* Send Slack notification via incoming webhook *)
let send_slack ?slack_url event_type path =
  match slack_url with
  | None -> ()
  | Some url ->
      let emoji = match event_type with New -> ":new:" | Modified -> ":pencil2:" | Deleted -> ":x:" in
      let text = Printf.sprintf "%s *[%s]* `%s`" emoji (string_of_event event_type) path in
      let json = Printf.sprintf {|{"text":"%s"}|} text in
      let cmd = Printf.sprintf "curl -s -X POST -H 'Content-Type: application/json' -d '%s' '%s' > /dev/null 2>&1 &" 
        json url in
      ignore (Unix.system cmd)

(* Send heartbeat signal *)
let send_heartbeat url =
  let timestamp = 
    let t = Unix.localtime (Unix.gettimeofday ()) in
    Printf.sprintf "%04d-%02d-%02dT%02d:%02d:%02d"
      (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday t.tm_hour t.tm_min t.tm_sec
  in
  let pid = Unix.getpid () in
  let hostname = try Unix.gethostname () with _ -> "unknown" in
  let json = Printf.sprintf {|{"type":"heartbeat","hostname":"%s","pid":%d,"timestamp":"%s"}|}
    hostname pid timestamp in
  let cmd = Printf.sprintf "curl -s -X POST -H 'Content-Type: application/json' -d '%s' '%s' > /dev/null 2>&1" 
    json url in
  
  match Unix.system cmd with
  | Unix.WEXITED 0 -> ()
  | _ -> Printf.eprintf "[Watch] Warning: Heartbeat failed\n%!"

let get_file_hash path =
  if not (Sys.file_exists path) then "" else
  let cmd = Printf.sprintf "shasum -a 256 '%s' 2>/dev/null | awk '{print $1}'" path in
  let ic = Unix.open_process_in cmd in
  let hash = try input_line ic with End_of_file -> "" in
  ignore (Unix.close_process_in ic);
  hash

let watch_fibers ~sw ~clock ~interval ~root ~cfg ~expr ~on_new ~on_modified ~on_deleted ?log_file ?webhook_url ?email_addr ?slack_url ?heartbeat_url ?(heartbeat_interval=60) () =
  Printf.eprintf "[Watch] Monitoring %s (interval: %.1fs, Ctrl+C to stop)\n%!" root interval;
  
  (* Open log file if specified *)
  let log_channel = match log_file with
    | Some path ->
        Printf.eprintf "[Watch] Logging to %s\n%!" path;
        Some (open_out_gen [Open_wronly; Open_append; Open_creat] 0o644 path)
    | None -> None
  in
  
  (match webhook_url with Some url -> Printf.eprintf "[Watch] Webhook: %s\n%!" url | None -> ());
  (match email_addr with Some addr -> Printf.eprintf "[Watch] Email: %s\n%!" addr | None -> ());
  (match slack_url with Some _ -> Printf.eprintf "[Watch] Slack enabled\n%!" | None -> ());
  (match heartbeat_url with Some url -> Printf.eprintf "[Watch] Heartbeat: %s (every %ds)\n%!" url heartbeat_interval | None -> ());
  
  (* Identify config files to watch for integrity *)
  let config_dir = Config.get_config_dir () in
  let config_file = Filename.concat config_dir "config.json" in
  let rules_file = Filename.concat config_dir "rules.json" in
  let watched_configs = [config_file; rules_file] in
  
  (* Initial hashes *)
  let config_hashes = Hashtbl.create 2 in
  List.iter (fun path -> 
    let h = get_file_hash path in
    if h <> "" then Hashtbl.add config_hashes path h
  ) watched_configs;
  Printf.eprintf "[Watch] Integrity check enabled for config files\n%!";

  let config = { interval; root; traversal_config = cfg; expr } in
  let state = ref (scan_files config) in
  
  Printf.eprintf "[Watch] Initial scan: %d files matching\n%!" (StringMap.cardinal !state);

      (* Fiber 1: Heartbeat (if enabled) *)
      (match heartbeat_url with
      | Some url ->
          Eio.Fiber.fork ~sw (fun () ->
            while true do
              send_heartbeat url;
              Eio.Time.sleep clock (float_of_int heartbeat_interval)
            done
          )
      | None -> ());

      (* Fiber 2: Integrity Check *)
      Eio.Fiber.fork ~sw (fun () ->
        while true do
          Eio.Time.sleep clock (interval *. 5.0); (* Check less frequently than main scan *)
          List.iter (fun path ->
            let current_hash = get_file_hash path in
            match Hashtbl.find_opt config_hashes path with
            | Some old_hash ->
                if current_hash <> old_hash && current_hash <> "" then begin
                  Printf.eprintf "\n[CRITICAL] INTEGRITY ALERT: %s has been modified!\n%!" path;
                  
                  (* Send alerts explicitly for integrity violation *)
                  let msg = Printf.sprintf "CRITICAL: Configuration file %s was modified! Old: %s, New: %s" 
                    path (String.sub old_hash 0 8) (String.sub current_hash 0 8) in
                  
                  (* Using the existing notification channels but with customized message if possible, 
                     or just reusing Modified event but logging special message *)
                  log_event ?log_channel Modified path;
                  
                  (* Special webhook payload for integrity *)
                  (match webhook_url with
                  | Some url -> 
                      let json = Printf.sprintf {|{"event":"INTEGRITY_VIOLATION","path":"%s","message":"%s"}|} path msg in
                      let cmd = Printf.sprintf "curl -s -X POST -H 'Content-Type: application/json' -d '%s' '%s' > /dev/null 2>&1 &" json url in
                      ignore (Unix.system cmd)
                  | None -> ());
                  
                  (match slack_url with
                  | Some url ->
                      let json = Printf.sprintf {|{"text":":rotating_light: *INTEGRITY ALERT* %s"}|} msg in
                      let cmd = Printf.sprintf "curl -s -X POST -H 'Content-Type: application/json' -d '%s' '%s' > /dev/null 2>&1 &" json url in
                      ignore (Unix.system cmd)
                  | None -> ());

                  (* Update hash to avoid spamming alerts? 
                     Better to spam until fixed or acked, but for now let's update to alert once per change *)
                  Hashtbl.replace config_hashes path current_hash
                end
            | None ->
                (* New config file appeared? *)
                if current_hash <> "" then Hashtbl.add config_hashes path current_hash
          ) watched_configs
        done
      );

      (* Fiber 3: File Scanning *)
      Eio.Fiber.fork ~sw (fun () ->
        try
          while true do
            Eio.Time.sleep clock interval;
            let new_state = scan_files config in
            
            (* Detect new and modified files *)
            StringMap.iter (fun path file ->
              match StringMap.find_opt path !state with
              | None ->
                  on_new { Eval.name = Filename.basename path; path; kind = Ast.File; size = 0L; mtime = file.mtime; perm = file.perm };
                  log_event ?log_channel New path;
                  send_webhook ?webhook_url New path;
                  send_email ?email_addr New path;
                  send_slack ?slack_url New path
              | Some old_file ->
                  if file.mtime > old_file.mtime then begin
                    on_modified { Eval.name = Filename.basename path; path; kind = Ast.File; size = 0L; mtime = file.mtime; perm = file.perm };
                    log_event ?log_channel Modified path;
                    send_webhook ?webhook_url Modified path;
                    send_email ?email_addr Modified path;
                    send_slack ?slack_url Modified path
                  end
            ) new_state;
            
            (* Detect deleted files *)
            StringMap.iter (fun path _ ->
              if not (StringMap.mem path new_state) then begin
                on_deleted { Eval.name = Filename.basename path; path; kind = Ast.File; size = 0L; mtime = 0.0; perm = 0 };
                log_event ?log_channel Deleted path;
                send_webhook ?webhook_url Deleted path;
                send_email ?email_addr Deleted path;
                send_slack ?slack_url Deleted path
              end
            ) !state;
            
            state := new_state
          done
        with e ->
          (match log_channel with Some oc -> close_out oc | None -> ());
          raise e
      )

let watch ~interval ~root ~cfg ~expr ~on_new ~on_modified ~on_deleted ?log_file ?webhook_url ?email_addr ?slack_url ?heartbeat_url ?(heartbeat_interval=60) () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
    watch_fibers ~sw ~clock:env#clock ~interval ~root ~cfg ~expr ~on_new ~on_modified ~on_deleted ?log_file ?webhook_url ?email_addr ?slack_url ?heartbeat_url ~heartbeat_interval ()

let watch_with_output ~interval ~root ~cfg ~expr ?log_file ?webhook_url ?email_addr ?slack_url ?heartbeat_url ?heartbeat_interval () =
  let on_new entry = Printf.printf "[NEW] %s\n%!" entry.Eval.path in
  let on_modified entry = Printf.printf "[MODIFIED] %s\n%!" entry.Eval.path in
  let on_deleted entry = Printf.printf "[DELETED] %s\n%!" entry.Eval.path in
  watch ~interval ~root ~cfg ~expr ~on_new ~on_modified ~on_deleted ?log_file ?webhook_url ?email_addr ?slack_url ?heartbeat_url ?heartbeat_interval ()
