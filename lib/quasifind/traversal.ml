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
}

type plan = {
  start_path : string;
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

  let plan expr =
    { start_path = extract_start_path expr }
end

let should_ignore cfg name =
  if (not cfg.include_hidden) && String.starts_with ~prefix:"." name then true
  else
    List.exists (fun pattern ->
      let re = Re.Glob.glob pattern |> Re.compile in
      Re.execp re name
    ) cfg.ignore

(* Helper to read directory entries as a Seq *)
let readdir_seq dir_path : string Seq.t =
  match Sys.readdir dir_path with
  | entries -> Array.to_seq entries
  | exception Sys_error msg ->
      Printf.eprintf "[Warning] Cannot read directory %s: %s\n%!" dir_path msg;
      Seq.empty

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

let rec visit (cfg : config) depth emit dir_path =
  match cfg.max_depth with
  | Some max_d when depth >= max_d -> ()
  | _ ->
      readdir_seq dir_path
      |> Seq.filter (fun name -> name <> "." && name <> "..")
      |> Seq.filter (fun name -> not (should_ignore cfg name))
      |> Seq.iter (fun name ->
           let full_path = Filename.concat dir_path name in
           match make_entry full_path with
           | None -> ()
           | Some entry ->
               emit entry;
               match entry.kind with
               | Dir -> visit cfg (depth + 1) emit full_path
               | Symlink when cfg.follow_symlinks ->
                   (match Unix.stat full_path with
                    | { st_kind = S_DIR; _ } -> visit cfg (depth + 1) emit full_path
                    | _ -> ()
                    | exception Unix.Unix_error (err, _, _) ->
                        Printf.eprintf "[Warning] Cannot follow symlink %s: %s\n%!" 
                          full_path (Unix.error_message err))
               | _ -> ()
         )

let traverse_parallel ~concurrency (cfg : config) emit start_path =
  Eio.Switch.run @@ fun sw ->
  let sem = Eio.Semaphore.make concurrency in

  let rec visit_parallel depth dir_path =
    match cfg.max_depth with
    | Some max_d when depth >= max_d -> ()
    | _ ->
        Eio.Semaphore.acquire sem;
        Fun.protect ~finally:(fun () -> Eio.Semaphore.release sem) (fun () ->
          readdir_seq dir_path
          |> Seq.filter (fun name -> name <> "." && name <> "..")
          |> Seq.filter (fun name -> not (should_ignore cfg name))
          |> Seq.iter (fun name ->
               let full_path = Filename.concat dir_path name in
               match make_entry full_path with
               | None -> ()
               | Some entry ->
                   emit entry;
                   match entry.kind with
                   | Dir -> Fiber.fork ~sw (fun () -> visit_parallel (depth + 1) full_path)
                   | Symlink when cfg.follow_symlinks ->
                       (match Unix.stat full_path with
                        | { st_kind = S_DIR; _ } -> 
                            Fiber.fork ~sw (fun () -> visit_parallel (depth + 1) full_path)
                        | _ -> ()
                        | exception Unix.Unix_error (err, _, _) ->
                            Printf.eprintf "[Warning] Cannot follow symlink %s: %s\n%!" 
                              full_path (Unix.error_message err))
                   | _ -> ()
             )
        )
  in
  visit_parallel 0 start_path

let traverse (cfg : config) (root_path : string) (expr : Typed.expr) (emit : Eval.entry -> unit) =
  let p = Planner.plan expr in
  
  let effective_start_path =
    if p.start_path = "." then root_path
    else Filename.concat root_path p.start_path
  in
  
  match cfg.strategy with
  | DFS -> visit cfg 0 emit effective_start_path
  | Parallel n -> traverse_parallel ~concurrency:n cfg emit effective_start_path
