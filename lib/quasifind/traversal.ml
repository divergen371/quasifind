open Eio.Std
open Ast
open Ast.Typed

type strategy =
  | DFS
  | Parallel of int (* concurrency *)

type config = {
  strategy : strategy;
  max_depth : int option;
  follow_symlinks : bool;
  include_hidden : bool;
  ignore : string list;
  preserve_timestamps : bool;
  spawn : ((unit -> unit) -> unit) option;
}

type plan = {
  start_path : string;
  name_filter : (string -> bool) option;
}

module Planner = struct
  let extract_start_path (expr : Typed.expr) : string =
    let rec aux acc = function
      | And (e1, e2) ->
          let p1 = aux acc e1 in
          if String.length p1 > String.length acc then p1 else aux acc e2
      | Path (StrEq s) -> s
      | Path (StrRe _) -> "."
      | _ -> acc
    in
    let p = aux "." expr in
    if p = "." then "." else p

  let extract_name_filter (expr : Typed.expr) : (string -> bool) option =
    let rec aux = function
      | And (e1, e2) ->
          (match aux e1, aux e2 with
           | Some f1, Some f2 -> Some (fun s -> f1 s && f2 s)
           | Some f, None | None, Some f -> Some f
           | None, None -> None)
      | Or (e1, e2) ->
          (match aux e1, aux e2 with
           | Some f1, Some f2 -> Some (fun s -> f1 s || f2 s)
           | _ -> None) (* Conservative: if one side unfilterable, can't filter *)
      | Name (StrEq s) -> Some (String.equal s)
      | Name (StrNe s) -> Some (fun n -> not (String.equal s n))
      | Name (StrRe re) -> Some (Re.execp re)
      | _ -> None
    in
    aux expr

  let plan expr =
    { start_path = extract_start_path expr;
      name_filter = extract_name_filter expr }
end

(* Check if we should process this entry based on name filter.
   NOTE: This is pre-stat filtering. We must be careful not to prune directories
   that we need to traverse, unless we are sure.
   Since strictly speaking we don't know it's a directory without stat or readdir type,
   and readdir only gives d_type on some systems (not portable in pure OCaml Sys.readdir), 
   we can't easily skip non-matching names if they might be directories we need to enter.
   
   However, we *can* apply the filter if it's a pure name match that *should* apply to everything including directories
   (e.g. name == "foo"). But for "name =~ /.../", if the regex doesn't match directory names, we stop traversal!
   
   Fix: We should only apply filter to restrict *emission* or *processing*, but for traversal (visiting subdirs), 
   we generally must descend unless we implement pruning logic (e.g. prune path).
   
   Actually, the current logic is in `visit` loop. 
   If we filter out "dir_1" because it doesn't match "*.jpg", we typically skip entering it.
   
   Correct logic for 'name' filter is:
   1. It applies to the entry itself (whether to yield it).
   2. It does NOT necessarily apply to whether we traverse into it (unless it's a prune rule).
   
   Wait, `find . -name "*.jpg"` DOES descend into directories that don't match *.jpg.
   So applying name filter at `readdir` stage to decide what to *inspect* is wrong if that inspection determines traversal.
   
   BUT, we want to avoid `stat`.
   
   If we can't distiguish Dir/File without stat, we CANNOT prune based on name filter unless we know the filter *also* excludes the directory we want to traverse (which is rare).
   
   So, the optimization "Pre-stat Filtering" is only safe if:
   A) We have `d_type` (requires generic readdir with type, e.g. Eio or Unix.readdir + non-portable).
   B) Or we blindly stat everything *except* what we know matches? No.
   
   Correction: we cannot simply filter `readdir` results by query name filter if that prevents recursion.
   
   However, we can separate "matching" from "traversing".
   
   If we filter here, we skip `make_entry`. `make_entry` triggers `stat`. 
   If we skip `make_entry`, we don't get `kind`, so we don't know if it's a dir, so we don't recurse.
   
   So this optimization (filtering before stat) is implicitly broken for recursive search unless we use `d_type`.
   
   Let's check if we can use Eio or a better readdir that gives types.
   Standard `Sys.readdir` returns `string array`. `Unix.readdir` returns string.
   
   If we cannot get d_type without stat, we MUST stat directories.
   
   Can we guess? No.
   
   Partial fix: If the name filter is a negation (e.g. name != ".git"), we can safely skip if we assume we don't want to traverse ignored stuff.
   But for positive match (name == "*.jpg"), we cannot skip "subdir".
   
   So, we need a separate "Prune" filter vs "Match" filter? 
   Or, we accept we can't optimize this without `d_type`.
   
   Wait, `Eio.Path.read_dir` returns names.
   
   Let's fallback to: always stat, OR (better) use `d_type` if available? 
   OCaml stdlib doesn't expose `d_type` easily in a cross-platform way without libraries like `dirent` or `ctypes`.
   
   Alternative strategy:
   - We are currently in `Traversal`.
   - We must call `stat` to check for Directory.
   - OPTIMIZATION: If we stat and it is a FILE, *then* we check name filter?
     - `make_entry` does stat.
     - `eval` checks name filter.
     - Is `eval` efficient? `eval` checks all fields.
   
   If we move name check *inside* `make_entry`? 
   Or checking name *before* `stat`?
   
   If `name` doesn't match filter:
     - If it's a file -> we can ignore it (save stat? no, we need stat to know it is a file).
     - If it's a dir -> we must traverse it (need stat to know it is a dir).
     
   Conclusion: Without `d_type`, we CANNOT save `stat` calls for entries that might be directories. 
   
   However, we *can* save `stat` if we enable the optimization ONLY when we are sure we don't need to traverse? 
   No, we always search deeper.
   
   Wait, does `fd` use `getdents` / `readdir` with type? Yes. Rust's `std::fs::read_dir` or `walkdir` uses it.
   
   Does OCaml have this? OCaml 5.1/Eio? 
   `Eio.Path.read_dir` returns `string list`.
   
   Let's look at `uv` (used by Eio_posix)? 
   
   If we can't avoid stat for everything, maybe we can avoid `eval` overhead? 
   `eval` is fast. `stat` is the bottleneck.
   
   For now, to fix the BUG (0 files found), I must revert the aggressive filtering for "should_visit" unless I can distinguish directories.
   
   But wait! `should_visit` is called for *recursion* candidates too?
   Yes, `visit` loops over `readdir_seq |> filter should_visit`.
   
   So if `should_visit "subdir" == false` (because "subdir" != "*.jpg"), we skip it.
   
   FIX: `should_visit` should ONLY filter if we are sure it's not a traversal target. 
   The `Planner` extracts "name match". This matching is for *selecting* results, not for *pruning* search tree.
   
   We should NOT use `planner.name_filter` to filter `readdir` stream for traversal.
   We should use it to filter *what we emit* or *what we fully stat*?
   
   If we don't know it's a directory, we have to stat it.
   
   So the optimization attempted (Pre-stat filtering) is invalid for recursive search without `d_type`.
   
   I will revert the usage of `planner.name_filter` in `should_visit`, effectively disabling that part of optimization, but keeping the Adaptive Scheduling.
   
   However, we can keep `should_visit` for `cfg.ignore` (which implies pruning).
*)

let should_visit (cfg : config) (planner : plan) (name : string) : bool =
  (* Base ignores (hidden, .git, etc) -> These are PRUNING rules *)
  if (not cfg.include_hidden) && String.starts_with ~prefix:"." name then false
  else
    let is_ignored = List.exists (fun pattern ->
        let re = Re.Glob.glob pattern |> Re.compile in
        Re.execp re name
      ) cfg.ignore
    in
    not is_ignored

(* Helper to restore timestamps if needed *)
let with_timestamps_preserved path preserve f =
  if preserve then
    match Unix.lstat path with
    | stats ->
        let atime = stats.st_atime in
        let mtime = stats.st_mtime in
        let res = f () in
        (* Restore atime, mtime *)
        (try Unix.utimes path atime mtime
         with Unix.Unix_error (e, _, _) -> 
           Printf.eprintf "[Warning] Could not restore timestamps for %s: %s\n%!" path (Unix.error_message e));
        res
    | exception Unix.Unix_error (e, _, _) ->
        Printf.eprintf "[Warning] Could not stat %s for preserving timestamps: %s\n%!" path (Unix.error_message e);
        f ()
  else
    f ()

(* Helper to read directory entries with type *)
let readdir_typed dir_path preserve : (string * Dirent.kind) list =
  with_timestamps_preserved dir_path preserve (fun () ->
    try Dirent.readdir dir_path
    with Unix.Unix_error (e, _, _) ->
        Printf.eprintf "[Warning] Cannot read directory %s: %s\n%!" dir_path (Unix.error_message e);
        []
  )

(* Optimization Logic: Returns TRUE if we can skip processing this entry *)
let can_skip_stat (planner : plan) (name : string) (kind : Dirent.kind) =
  match kind with
  | Dir -> false (* Always check directories (traversal) *)
  | Unknown -> false (* Must stat to know what it is *)
  | Reg | Symlink | Other ->
      match planner.name_filter with
      | Some f -> not (f name) (* Skip if name filter implies no match *)
      | None -> false

(* Create entry from path, returning Option for error handling *)
let make_entry path : Eval.entry option =
  match Unix.lstat path with
  | stats ->
      let kind = match stats.st_kind with
        | Unix.S_REG -> File
        | Unix.S_DIR -> Dir
        | Unix.S_LNK -> Symlink
        | _ -> File
      in
      let size = Int64.of_int stats.st_size in
      let name = Filename.basename path in
      Some { Eval.name; path; kind; size; mtime = stats.st_mtime; perm = stats.st_perm }
  | exception Unix.Unix_error (err, _, _) ->
      Printf.eprintf "[Warning] Cannot stat %s: %s\n%!" path (Unix.error_message err);
      None

let visit (cfg : config) (planner : plan) depth emit dir_path =
  let rec aux depth dir_path =
    match cfg.max_depth with
    | Some max_d when depth >= max_d -> ()
    | _ ->
        let entries = readdir_typed dir_path cfg.preserve_timestamps in
        entries
        |> List.iter (fun (name, kind) ->
             if name <> "." && name <> ".." && should_visit cfg planner name then
               if can_skip_stat planner name kind then () (* OPTIMIZATION: Skip lstat *)
               else
                 let full_path = Filename.concat dir_path name in
                 match make_entry full_path with
                 | None -> ()
                 | Some entry ->
                     emit entry;
                     match entry.kind with
                     | Dir -> aux (depth + 1) full_path
                     | Symlink when cfg.follow_symlinks ->
                         (match Unix.stat full_path with
                          | { st_kind = S_DIR; _ } -> aux (depth + 1) full_path
                          | _ -> ()
                          | exception _ -> ())
                     | _ -> ()
           )
  in
  aux depth dir_path

(* Dynamic Work Pool Strategy *)
module Work_pool = struct
  type t = {
    queue : string Queue.t;
    lock : Eio.Mutex.t;
    cond : Eio.Condition.t;
    mutable active_workers : int;
    mutable total_workers : int;
    mutable shutdown : bool;
  }

  let create () = {
    queue = Queue.create ();
    lock = Eio.Mutex.create ();
    cond = Eio.Condition.create ();
    active_workers = 0;
    total_workers = 0;
    shutdown = false;
  }

  let push t item =
    Eio.Mutex.use_rw ~protect:true t.lock (fun () ->
      Queue.push item t.queue;
      Eio.Condition.broadcast t.cond
    )

  (* Try to pop an item. If empty, wait until item available or termination. *)
  let rec pop t =
    Eio.Mutex.use_rw ~protect:true t.lock (fun () ->
      if not (Queue.is_empty t.queue) then
        Some (Queue.pop t.queue)
      else if t.shutdown then
        None
      else if t.active_workers = 0 then (
        (* No active workers and queue empty -> Termination *)
        t.shutdown <- true;
        Eio.Condition.broadcast t.cond;
        None
      ) else (
        (* Wait for work *)
        Eio.Condition.await t.cond t.lock;
        (* Retry after wake up *)
        (* Note: The recursive call here is inside the lock, but Eio.Mutex allows it? 
           NO. await releases lock. Recursive call needs to re-acquire.
           Actually, simply returning a special value to retry is safer, or constructing loop outside.
           Let's return `Retry` or `Done`. *)
        (* Better: loop inside the lock? No, await releases lock. *)
        (* Eio.Condition.await releases lock and re-acquires.
           So we CAN loop here. *)
        None (* Placeholder, will be retried by caller wrapper if needed, but let's do it properly *)
      )
    )
    
  (* Correct Pop implementation with loop *)
  let pop_blocking t =
    Eio.Mutex.use_rw ~protect:true t.lock (fun () ->
      let rec loop () =
        if not (Queue.is_empty t.queue) then
          Some (Queue.pop t.queue)
        else if t.shutdown then
          None
        else if t.active_workers = 0 then (
          t.shutdown <- true;
          Eio.Condition.broadcast t.cond;
          None
        ) else (
          Eio.Condition.await t.cond t.lock;
          loop ()
        )
      in
      loop ()
    )
end

let traverse_parallel ~concurrency (cfg : config) (planner : plan) emit start_path =
  let run_in_switch f = Eio.Switch.run f in
  
  run_in_switch @@ fun sw ->
  
  let pool = Work_pool.create () in
  Work_pool.push pool start_path;
  pool.total_workers <- concurrency;
  
  let rec worker_loop () =
    match Work_pool.pop_blocking pool with
    | None -> () (* Done *)
    | Some dir_path ->
        (* Mark as active *)
        Eio.Mutex.use_rw ~protect:true pool.lock (fun () -> pool.active_workers <- pool.active_workers + 1);
        
        (* Process directory *)
        (try
           let entries = readdir_typed dir_path cfg.preserve_timestamps in
           entries |> List.iter (fun (name, kind) ->
             if name <> "." && name <> ".." && should_visit cfg planner name then
               if can_skip_stat planner name kind then ()
               else
                 let full_path = Filename.concat dir_path name in
                 match make_entry full_path with
                 | None -> ()
                 | Some entry ->
                     emit entry;
                     match entry.kind with
                     | Dir -> Work_pool.push pool full_path
                     | Symlink when cfg.follow_symlinks ->
                         (match Unix.stat full_path with
                          | { st_kind = S_DIR; _ } -> Work_pool.push pool full_path
                          | _ -> ()
                          | exception _ -> ())
                     | _ -> ()
           )
         with exn -> 
           Printf.eprintf "Error processing %s: %s\n%!" dir_path (Printexc.to_string exn)
        );

        (* Mark as inactive *)
        Eio.Mutex.use_rw ~protect:true pool.lock (fun () -> 
           pool.active_workers <- pool.active_workers - 1;
           if pool.active_workers = 0 && Queue.is_empty pool.queue then (
             pool.shutdown <- true;
             Eio.Condition.broadcast pool.cond
           )
        );
        worker_loop ()
  in

  (* Spawn domains *)
  (* Using Atomic for domain counting not strictly needed since pool tracks it, but Eio needs forks *)
  
  (* We spawn (concurrency - 1) domains + 1 fiber on current domain *)
  let spawn_workers () =
    for i = 1 to concurrency - 1 do
       Fiber.fork ~sw (fun () ->
         match cfg.spawn with
         | Some spawn_fn -> spawn_fn (fun () -> 
             (* Need a Switch in new domain? Parallel strategy usually implies independent switches 
                or just running pure code. Readdir is blocking syscall. *)
             (* Eio functions inside spawn_fn might need switch? 
                Work_pool uses Eio.Mutex. *)
             (* CRITICAL: Eio.Mutex and Condition must be used within Eio. 
                If spawn_fn uses `Eio.Domain_manager.run`, it creates a new domain. 
                Eio primitives are thread-safe across domains IF specific backends support it.
                Eio_posix usually supports sharing via domains. *)
             
             (* However, `Eio.Domain_manager.run` expects the function to just run. 
                If we use Eio mutex inside, we need an Eio environment? 
                Actually, `spawn_fn` provided by `main.ml` uses `Eio.Domain_manager.run env`. 
                This runs the function in a new domain.
                Does that domain have a Switch? `run` does NOT create a switch. 
                So we should create one. *)
             Eio.Switch.run @@ fun _sw -> worker_loop ()
         )
         | None -> worker_loop ()
       )
    done;
    (* Run one worker on current domain *)
    worker_loop ()
  in
  
  spawn_workers ()

let traverse (cfg : config) (root_path : string) (expr : Typed.expr) (emit : Eval.entry -> unit) =
  let p = Planner.plan expr in
  
  let effective_start_path =
    if p.start_path = "." then root_path
    else Filename.concat root_path p.start_path
  in
  
  match cfg.strategy with
  | DFS -> visit cfg p 0 emit effective_start_path
  | Parallel n -> traverse_parallel ~concurrency:n cfg p emit effective_start_path
