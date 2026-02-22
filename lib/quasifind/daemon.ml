(* Daemon Logic *)
open Eio.Std

module Vfs = Vfs

let run ~root =
  Printf.printf "Starting Quasifind Daemon (Experimental)...\n";
  Printf.printf "Root Scope: %s\n" root;

    let cfg = Config.load () in
    let cache_dir = 
      match cfg.daemon.cache_path with
      | Some p -> p
      | None ->
        let home = try Sys.getenv "HOME" with Not_found -> "/tmp" in
        let dir = Filename.concat home ".cache" in
        let qf_dir = Filename.concat dir "quasifind" in
        if not (Sys.file_exists qf_dir) then Unix.mkdir qf_dir 0o700;
        qf_dir
    in
    let dump_path = Filename.concat cache_dir "daemon.dump" in

    let save_vfs vfs =
      Printf.printf "Saving VFS to %s...\n%!" dump_path;
      Vfs.save vfs dump_path
    in

    (* Initialize VFS - Load if exists *)
    let vfs = ref (
      match Vfs.load dump_path with 
      | Some t -> Printf.printf "Loaded VFS from cache.\n%!"; t 
      | None -> Vfs.empty
    ) in

    (* Timing refs for stats *)
    let start_time = Unix.gettimeofday () in
    let last_scan_time = ref start_time in

    (* Shutdown flag - declared outside Eio_main.run for signal handler access *)
    let shutdown_requested = ref false in

    (* Graceful Shutdown: Register signal handlers *)
    Sys.set_signal Sys.sigterm (Sys.Signal_handle (fun _ ->
      Printf.eprintf "\n[Signal] SIGTERM received, initiating graceful shutdown...\n%!";
      shutdown_requested := true));
    Sys.set_signal Sys.sigint (Sys.Signal_handle (fun _ ->
      Printf.eprintf "\n[Signal] SIGINT received, initiating graceful shutdown...\n%!";
      shutdown_requested := true));

    (* Enter Event Loop *)
    try
      Eio_main.run @@ fun env ->
      Eio.Switch.run @@ fun sw ->

      (* We need a mutex, but `vfs` is `t ref`. *)
      let vfs_mutex = Eio.Mutex.create () in
    
    let update_vfs_insert entry =
      let entry_kind = match entry.Eval.kind with Ast.Dir -> `Dir | _ -> `File in
      Eio.Mutex.use_rw ~protect:true vfs_mutex (fun () ->
        vfs := Vfs.insert !vfs entry.Eval.path entry_kind entry.Eval.size entry.Eval.mtime entry.Eval.perm
      )
    in
    
    let update_vfs_remove entry =
      Eio.Mutex.use_rw ~protect:true vfs_mutex (fun () ->
        vfs := Vfs.remove !vfs entry.Eval.path
      )
    in

    let on_new entry = update_vfs_insert entry in
    let on_modified entry = update_vfs_insert entry in
    let on_deleted entry = update_vfs_remove entry in

    let config : Traversal.config = {
      strategy = Parallel (Domain.recommended_domain_count ());
      max_depth = None;
      follow_symlinks = false; 
      include_hidden = true;
      ignore = cfg.daemon.exclude;
      ignore_re = [];
      preserve_timestamps = false;
      spawn = None;
    } in

    Printf.printf "Perform Initial VFS Scan...\n%!";
    Traversal.traverse config root Ast.Typed.True (fun entry -> on_new entry);
    last_scan_time := Unix.gettimeofday ();

    Printf.printf "Daemon running with Watcher (Interval: %.1fs)...\n%!" cfg.daemon.watch_interval;

    (* Start Watcher Fibers *)
    Watcher.watch_fibers 
      ~sw 
      ~clock:env#clock 
      ~interval:cfg.daemon.watch_interval 
      ~root 
      ~cfg:config 
      ~expr:Ast.Typed.True
      ~on_new ~on_modified ~on_deleted
      ~shutdown_flag:shutdown_requested
      ();

    (* Start IPC Server *)

    Eio.Fiber.fork ~sw (fun () ->
      let handler request =
        match request with
        | Ipc.Stats ->
            let count = Vfs.count_nodes !vfs in
            let mem = Gc.stat () in
            let heap_mb = float_of_int mem.Gc.heap_words *. (float_of_int Sys.word_size /. 8.0) /. 1_048_576.0 in
            let heap_mb_rounded = Float.round (heap_mb *. 100.0) /. 100.0 in
            Ipc.Success (`Assoc [
              ("nodes", `Int count);
              ("root", `String root);
              ("heap_mb", `Float heap_mb_rounded);
              ("uptime_sec", `Float (Unix.gettimeofday () -. start_time));
              ("last_scan", `Float !last_scan_time);
            ])
        | Ipc.Shutdown ->
            shutdown_requested := true;
            Ipc.Success (`String "Daemon shutting down...")
        | Ipc.Query expr ->
            let start_t = Unix.gettimeofday () in
            let current_vfs = !vfs in
            let results = 
              Vfs.fold_with_query (fun acc entry ->
                if Eval.eval start_t expr entry then
                  let json_entry = `Assoc [
                    ("path", `String entry.Eval.path);
                    ("name", `String entry.Eval.name);
                    ("size", `Int (Int64.to_int entry.Eval.size));
                    ("mtime", `Float entry.Eval.mtime);
                  ] in
                  json_entry :: acc
                else 
                  acc
              ) [] current_vfs expr
            in
            Ipc.Success (`List results)
      in
      try Ipc.run ~sw ~net:env#net ~clock:env#clock ~shutdown_flag:shutdown_requested handler
      with e -> Printf.eprintf "IPC Server Error: %s\n%!" (Printexc.to_string e)
    );

    (* Daemon Status Loop *)
    while not !shutdown_requested do
      Eio.Time.sleep env#clock 2.0;
      if not !shutdown_requested then
        Printf.printf "Daemon heartbeat (Nodes: %d)\n%!" (Vfs.count_nodes !vfs);
    done;
    
    Printf.printf "Daemon shutdown complete.\n%!";
    save_vfs !vfs
    with e -> 
      Printf.eprintf "Daemon crash/exit: %s\n%!" (Printexc.to_string e);
      save_vfs !vfs
