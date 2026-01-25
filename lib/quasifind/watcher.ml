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

module StringMap = Map.Make(String)

let scan_files config =
  let files = ref StringMap.empty in
  let now = Unix.gettimeofday () in
  Traversal.traverse config.traversal_config config.root config.expr (fun entry ->
    if Eval.eval now config.expr entry then
      files := StringMap.add entry.path { path = entry.path; mtime = entry.mtime } !files
  );
  !files

let watch ~interval ~root ~cfg ~expr ~on_new ~on_modified =
  Printf.eprintf "[Watch] Monitoring %s (interval: %.1fs, Ctrl+C to stop)\n%!" root interval;
  
  let config = { interval; root; traversal_config = cfg; expr } in
  let state = ref (scan_files config) in
  
  (* Initial report *)
  Printf.eprintf "[Watch] Initial scan: %d files matching\n%!" (StringMap.cardinal !state);
  
  while true do
    Unix.sleepf interval;
    let new_state = scan_files config in
    
    (* Detect new and modified files *)
    StringMap.iter (fun path file ->
      match StringMap.find_opt path !state with
      | None ->
          (* New file *)
          on_new { Eval.name = Filename.basename path; path; kind = Ast.File; size = 0L; mtime = file.mtime }
      | Some old_file ->
          if file.mtime > old_file.mtime then
            (* Modified file *)
            on_modified { Eval.name = Filename.basename path; path; kind = Ast.File; size = 0L; mtime = file.mtime }
    ) new_state;
    
    state := new_state
  done

let watch_with_output ~interval ~root ~cfg ~expr =
  let on_new entry =
    Printf.printf "[NEW] %s\n%!" entry.Eval.path
  in
  let on_modified entry =
    Printf.printf "[MODIFIED] %s\n%!" entry.Eval.path
  in
  watch ~interval ~root ~cfg ~expr ~on_new ~on_modified
