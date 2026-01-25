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
}

type plan = {
  start_path : string;
  (* In future: ignore lists, etc *)
}

module Planner = struct
  (* Minimal A: Extract distinct static path prefix if possible *)
  let extract_start_path (expr : Typed.expr) : string =
    let rec aux acc = function
      | And (e1, e2) ->
          let p1 = aux acc e1 in
          if String.length p1 > String.length acc then p1 else aux acc e2
      (* Handle specific path equality or regex slightly carefully *)
      | Path (StrEq s) -> s (* Exact path match is a great start path *)
      | Path (StrRe re) -> "." (* Regex is hard to optimize statically without prefix analysis, for now fallback *)
      (* Simple containment check for "starts with" could be done here if we had a dedicated Op, 
         but for now we look for exact matches or assume root *)
      | _ -> acc
    in
    let p = aux "." expr in
    if p = "." then "." else p

  let plan expr =
    { start_path = extract_start_path expr }
end

(* Helper to get stat and create entry *)
let stat_entry path name kind =
  try
    let stats = Unix.lstat path in
    let size = Int64.of_int stats.st_size in
    let mtime = stats.st_mtime in
    Some { Eval.name; path; kind; size; mtime }
  with Unix.Unix_error (code, op, arg) ->
    (* trace error? *)
    None

let rec visit (cfg : config) depth emit dir_path =
  (* Check depth limit *)
  match cfg.max_depth with
  | Some max_d when depth > max_d -> ()
  | _ ->
    (* Read directory entries *)
    match Sys.readdir dir_path with
    | entries ->
      Array.iter (fun name ->
        if name <> "." && name <> ".." then
          let full_path = Filename.concat dir_path name in
          (* lstat to check kind *)
          try
             let stats = Unix.lstat full_path in
             let kind = match stats.st_kind with
               | Unix.S_REG -> File
               | Unix.S_DIR -> Dir
               | Unix.S_LNK -> Symlink
               | _ -> File (* fallback or ignore? *)
             in
             
             (* Create entry and emit *)
             (* Note: mtime from stats is sufficient here, no need to call stat_entry again strictly
                but let's reuse logic or keep it simple. *)
             let size = Int64.of_int stats.st_size in
             let entry = { Eval.name; path = full_path; kind; size; mtime = stats.st_mtime } in
             emit entry;

             (* Recurse if directory *)
             if kind = Dir then
               visit cfg (depth + 1) emit full_path
             else if kind = Symlink && cfg.follow_symlinks then
               (* TODO: loop detection *)
               (* For now naive follow *)
               match Unix.stat full_path with
               | { st_kind = S_DIR; _ } -> visit cfg (depth + 1) emit full_path
               | _ -> () (* It's a file symlink, already emitted *)
               | exception _ -> () (* broken link *)
          with _ -> () (* permission denied etc *)
      ) entries
    | exception _ -> () (* permission denied *)

(* Parallel traversal using Eio *)
let traverse_parallel ~concurrency (cfg : config) emit start_path =
  Eio.Switch.run @@ fun sw ->
  let sem = Eio.Semaphore.make concurrency in

  let rec visit_parallel depth dir_path =
    match cfg.max_depth with
    | Some max_d when depth > max_d -> ()
    | _ ->
      Eio.Semaphore.acquire sem;
      Fun.protect ~finally:(fun () -> Eio.Semaphore.release sem) (fun () ->
        match Sys.readdir dir_path with
        | entries ->
          Array.iter (fun name ->
            if name <> "." && name <> ".." then
              let full_path = Filename.concat dir_path name in
              try
                 let stats = Unix.lstat full_path in
                 let kind = match stats.st_kind with
                   | Unix.S_REG -> File
                   | Unix.S_DIR -> Dir
                   | Unix.S_LNK -> Symlink
                   | _ -> File
                 in
                 let entry = { Eval.name; path = full_path; kind; size = Int64.of_int stats.st_size; mtime = stats.st_mtime } in
                 emit entry;

                 if kind = Dir then
                   Fiber.fork ~sw (fun () -> visit_parallel (depth + 1) full_path)
                 else if kind = Symlink && cfg.follow_symlinks then
                   match Unix.stat full_path with
                   | { st_kind = S_DIR; _ } -> Fiber.fork ~sw (fun () -> visit_parallel (depth + 1) full_path)
                   | _ -> ()
                   | exception _ -> ()
              with _ -> ()
          ) entries
        | exception _ -> ()
      )
  in
  visit_parallel 0 start_path

let traverse (cfg : config) (root_path : string) (expr : Typed.expr) (emit : Eval.entry -> unit) =
  let p = Planner.plan expr in
  (* traceln "Planned start path: %s" p.start_path; *)
  
  let effective_start_path =
    if p.start_path = "." then root_path
    else Filename.concat root_path p.start_path
  in
  
  match cfg.strategy with
  | DFS -> visit cfg 0 emit effective_start_path
  | Parallel n -> traverse_parallel ~concurrency:n cfg emit effective_start_path
