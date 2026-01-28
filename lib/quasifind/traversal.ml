open Eio.Std
open Saturn
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
  ignore_re : Re.re list; (* Pre-compiled regexes *)
  preserve_timestamps : bool;
  spawn : ((unit -> unit) -> unit) option;
}

type plan = {
  start_path : string;
  name_filter : (string -> bool) option;
  needs_stat : bool;
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
      name_filter = extract_name_filter expr;
      needs_stat = Eval.requires_metadata expr }
end

let should_visit (cfg : config) (planner : plan) (name : string) : bool =
  (* Base ignores (hidden, .git, etc) -> These are PRUNING rules *)
  if (not cfg.include_hidden) && String.starts_with ~prefix:"." name then false
  else
    let is_ignored = List.exists (fun re ->
        Re.execp re name
      ) cfg.ignore_re
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

(* Helper to read directory entries with type using batch iterator *)
let iter_typed dir_path preserve f =
  with_timestamps_preserved dir_path preserve (fun () ->
    try Dirent.iter_batch dir_path f
    with Unix.Unix_error (e, _, _) ->
        Printf.eprintf "[Warning] Cannot read directory %s: %s\n%!" dir_path (Unix.error_message e)
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
let make_entry ?(needs_stat=true) path (kind_hint : Dirent.kind) : Eval.entry option =
  (* If metadata is not needed and kind is known, skip lstat *)
  if not needs_stat && kind_hint <> Dirent.Unknown then
    let kind = match kind_hint with
      | Dirent.Reg -> Ast.File
      | Dirent.Dir -> Ast.Dir
      | Dirent.Symlink -> Ast.Symlink
      | _ -> Ast.File
    in
    let name = Filename.basename path in
    (* Return dummy metadata. Queries relying on this must have set needs_stat=true *)
    Some { Eval.name; path; kind; size = 0L; mtime = 0.0; perm = 0 }
  else
    match Unix.lstat path with
    | stats ->
        let kind = match stats.st_kind with
          | Unix.S_REG -> Ast.File
          | Unix.S_DIR -> Ast.Dir
          | Unix.S_LNK -> Ast.Symlink
          | _ -> Ast.File
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
        iter_typed dir_path cfg.preserve_timestamps (fun name kind ->
             if name <> "." && name <> ".." && should_visit cfg planner name then
               if can_skip_stat planner name kind then () (* OPTIMIZATION: Skip lstat *)
               else
                 let full_path = Filename.concat dir_path name in
                 match make_entry ~needs_stat:planner.needs_stat full_path kind with
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

(* Lock-free Work Stealing Pool *)
module Work_pool = struct
  module WSD = Saturn.Work_stealing_deque

  type t = {
    queues : (string * int) WSD.t array;
    concurrency : int;
    active_count : int Atomic.t; (* Number of workers currently processing or looking for work *)
    idle_count : int Atomic.t;   (* Number of workers purely idle (failed to steal) *)
    shutdown : bool Atomic.t;
  }

  let create ~concurrency =
    let queues = Array.init concurrency (fun _ -> WSD.create ()) in
    {
      queues;
      concurrency;
      active_count = Atomic.make concurrency;
      idle_count = Atomic.make 0;
      shutdown = Atomic.make false;
    }

  let push t id item =
    WSD.push t.queues.(id) item

  let try_pop_local t id =
    WSD.pop_opt t.queues.(id)

  let try_steal t id =
    let victim = Random.int t.concurrency in
    if victim = id then None
    else WSD.steal_opt t.queues.(victim)

  (* Attempt experimental stealing approach: try multiple times valid victims *)
  let rec attempt_steal t id attempt =
    if attempt > 2 * t.concurrency then None
    else
      let victim = Random.int t.concurrency in
      if victim = id then attempt_steal t id (attempt + 1)
      else
        match WSD.steal_opt t.queues.(victim) with
        | Some _ as res -> res
        | None -> attempt_steal t id (attempt + 1)
end

let traverse_parallel ~concurrency (cfg : config) (planner : plan) emit start_path =
  let run_in_switch f = Eio.Switch.run f in
  
  run_in_switch @@ fun sw ->
  
  let pool = Work_pool.create ~concurrency in
  
  (* Initial task to worker 0 *)
  Work_pool.push pool 0 (start_path, 0);

  let rec worker_loop id =
    (* 1. Try local pop *)
    match Work_pool.try_pop_local pool id with
    | Some task -> process_task id task
    | None ->
        (* 2. Try steal *)
        match Work_pool.attempt_steal pool id 0 with
        | Some task -> process_task id task
        | None ->
            (* 3. Idle / Termination Detection *)
            Atomic.incr pool.idle_count;
            
            (* Check strictly: If all workers are idle, we are done. *)
            while not (Atomic.get pool.shutdown) do
               if Atomic.get pool.idle_count = pool.concurrency then (
                 Atomic.set pool.shutdown true
               ) else (
                 (* Busy wait / Yield. In Eio, yield. *)
                 Eio.Fiber.yield ();
                 (* Retry steal periodically just in case *)
                 match Work_pool.attempt_steal pool id 0 with
                 | Some task -> 
                     Atomic.decr pool.idle_count;
                     process_task id task
                     (* Break loop by recursion? No, process_task loops back. *)
                 | None -> ()
               )
            done;
            (* Shutdown check again to exit loop implies return unit *)
            ()

  and process_task id (dir_path, depth) =
    (try
       let should_process = 
         match cfg.max_depth with
         | Some max_d -> depth < max_d 
         | None -> true
       in


       if should_process then
         iter_typed dir_path cfg.preserve_timestamps (fun name kind ->
           if name <> "." && name <> ".." && should_visit cfg planner name then
             if can_skip_stat planner name kind then ()
             else
               let full_path = Filename.concat dir_path name in
               match make_entry ~needs_stat:planner.needs_stat full_path kind with
               | None -> ()
               | Some entry ->
                   emit entry;
                   let should_recurse = 
                     match cfg.max_depth with
                     | Some max_d -> depth + 1 < max_d
                     | None -> true
                   in
                   
                   if should_recurse then
                     match entry.kind with
                     | Dir -> Work_pool.push pool id (full_path, depth + 1)
                     | Symlink when cfg.follow_symlinks ->
                         (match Unix.stat full_path with
                          | { st_kind = S_DIR; _ } -> Work_pool.push pool id (full_path, depth + 1)
                          | _ -> ()
                          | exception _ -> ())
                     | _ -> ()
         )
     with exn -> 
       Printf.eprintf "Error processing %s: %s\n%!" dir_path (Printexc.to_string exn)
    );
    (* Continue loop *)
    worker_loop id
  in

  (* Spawn domains *)
  let spawn_workers () =
    for i = 1 to concurrency - 1 do
       Fiber.fork ~sw (fun () ->
         match cfg.spawn with
         | Some spawn_fn -> spawn_fn (fun () -> 
             Eio.Switch.run @@ fun _sw -> worker_loop i
         )
         | None -> worker_loop i
       )
    done;
    (* Run worker 0 on current domain *)
    worker_loop 0
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
