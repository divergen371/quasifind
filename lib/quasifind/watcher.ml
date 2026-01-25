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
    if Eval.eval now config.expr entry then
      files := StringMap.add entry.path { path = entry.path; mtime = entry.mtime } !files
  );
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

let watch ~interval ~root ~cfg ~expr ~on_new ~on_modified ~on_deleted ?log_file ?webhook_url () =
  Printf.eprintf "[Watch] Monitoring %s (interval: %.1fs, Ctrl+C to stop)\n%!" root interval;
  
  (* Open log file if specified *)
  let log_channel = match log_file with
    | Some path ->
        Printf.eprintf "[Watch] Logging to %s\n%!" path;
        Some (open_out_gen [Open_wronly; Open_append; Open_creat] 0o644 path)
    | None -> None
  in
  
  (match webhook_url with
   | Some url -> Printf.eprintf "[Watch] Webhook notifications to %s\n%!" url
   | None -> ());
  
  let config = { interval; root; traversal_config = cfg; expr } in
  let state = ref (scan_files config) in
  
  Printf.eprintf "[Watch] Initial scan: %d files matching\n%!" (StringMap.cardinal !state);
  
  try
    while true do
      Unix.sleepf interval;
      let new_state = scan_files config in
      
      (* Detect new and modified files *)
      StringMap.iter (fun path file ->
        match StringMap.find_opt path !state with
        | None ->
            on_new { Eval.name = Filename.basename path; path; kind = Ast.File; size = 0L; mtime = file.mtime };
            log_event ?log_channel New path;
            send_webhook ?webhook_url New path
        | Some old_file ->
            if file.mtime > old_file.mtime then begin
              on_modified { Eval.name = Filename.basename path; path; kind = Ast.File; size = 0L; mtime = file.mtime };
              log_event ?log_channel Modified path;
              send_webhook ?webhook_url Modified path
            end
      ) new_state;
      
      (* Detect deleted files *)
      StringMap.iter (fun path _ ->
        if not (StringMap.mem path new_state) then begin
          on_deleted { Eval.name = Filename.basename path; path; kind = Ast.File; size = 0L; mtime = 0.0 };
          log_event ?log_channel Deleted path;
          send_webhook ?webhook_url Deleted path
        end
      ) !state;
      
      state := new_state
    done
  with e ->
    (match log_channel with Some oc -> close_out oc | None -> ());
    raise e

let watch_with_output ~interval ~root ~cfg ~expr ?log_file ?webhook_url () =
  let on_new entry = Printf.printf "[NEW] %s\n%!" entry.Eval.path in
  let on_modified entry = Printf.printf "[MODIFIED] %s\n%!" entry.Eval.path in
  let on_deleted entry = Printf.printf "[DELETED] %s\n%!" entry.Eval.path in
  watch ~interval ~root ~cfg ~expr ~on_new ~on_modified ~on_deleted ?log_file ?webhook_url ()
