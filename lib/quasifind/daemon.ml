(* Daemon Logic *)
open Eio.Std

module Vfs = Vfs

let run ~root =
  Printf.printf "Starting Quasifind Daemon (Experimental)...\n";
  Printf.printf "Root Scope: %s\n" root;

  (* Initialize VFS *)
  let vfs = ref Vfs.empty in
  
  (* Initial Scan - Using `find` command for simplicity in PoC phase *)
  (* Phase 2 will use native recursive traversal *)
  Printf.printf "Scanning filesystem...\n%!";
  let start_time = Unix.gettimeofday () in
  
  (* Scan using `find` to get paths, then stat in OCaml for portability *)
  let cmd = Printf.sprintf "find '%s'" root in
  let ic = Unix.open_process_in cmd in
  
  try
    while true do
      let path = input_line ic in
      if path <> root then (
        try
          let stats = Unix.lstat path in
          let kind = 
            match stats.st_kind with
            | Unix.S_REG -> `File
            | Unix.S_DIR -> `Dir
            | _ -> `File (* Treat others as file for now *)
          in
          let size = Int64.of_int stats.st_size in
          let mtime = stats.st_mtime in
          let perm = stats.st_perm in
          vfs := Vfs.insert !vfs path kind size mtime perm
        with Unix.Unix_error _ -> ()
      )
    done
  with End_of_file ->
    ignore (Unix.close_process_in ic);
    
    let duration = Unix.gettimeofday () -. start_time in
    let count = Vfs.count_nodes !vfs in
    Printf.printf "Scan complete in %.2fs. Loaded %d nodes.\n%!" duration count;
    
    (* Enter Event Loop *)
    Eio_main.run @@ fun env ->
    Eio.Switch.run @@ fun sw ->
      Printf.printf "Daemon is running. Press Ctrl+C to stop.\n%!";
      (* Placeholder for IPC server and Watcher *)
      while true do
        Eio.Time.sleep env#clock 10.0;
        Printf.printf "Daemon heartbeat (Nodes: %d)\n%!" (Vfs.count_nodes !vfs);
        (* For debug, print tree occasionally *)
        (* Vfs.print_tree ~max_depth:2 !vfs *)
      done
