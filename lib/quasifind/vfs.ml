(* Virtual File System (VFS) for Daemon Mode *)
(* Backed by Adaptive Radix Tree (ART) *)

type inode = {
  size : int64;
  mtime : float;
  perm : int;
}

type entry = {
  kind : Ast.file_type;
  inode : inode;
}

type t = entry Art.t

let empty = Art.empty

(* Helper to split path into components *)
let split_path path =
  String.split_on_char '/' path
  |> List.filter (fun s -> s <> "" && s <> ".")
  |> List.map Intern.intern

(* Insert a file/dir into the VFS *)
(* Note: Art.insert updates the node at path. *)
let insert t path kind size mtime perm =
  let parts = split_path path in
  (* Check if we need to map generic kind to specific Ast kind *)
  let entry_kind = match kind with 
    | `Dir -> Ast.Dir 
    | `File -> Ast.File 
  in
  
  let entry = {
    kind = entry_kind;
    inode = { size; mtime; perm }
  } in
  
  Art.insert t parts entry

(* Remove a node by path *)
let remove t path =
  let parts = split_path path in
  Art.remove t parts

(* Lookup *)
(* Original find_opt returned `node option`. Here we can just return `entry option`? 
   But external consumers like Daemon might not use find_opt directly?
   Daemon.ml ONLY uses `insert`, `remove`, `count_nodes`, `fold`.
   It does NOT use `find_opt`.
   So I can drop `find_opt` or adapt it if I want.
*)
let find_opt t path =
  let parts = split_path path in
  Art.find_opt t parts

(* Count nodes *)
let count_nodes t = Art.count_nodes t

(* Fold *)
(* Original fold: (f : 'a -> Eval.entry -> 'a) -> 'a -> t -> 'a *)
(* Art.fold: ('a -> 'b -> 'a) -> 'a -> 'b t -> 'a *)
(* So Art.fold passes `entry` (our value). We need to reconstruct full `Eval.entry`. *)
(* But `Art.fold` as implemented in `Art.ml` folds over values. *)
(* Does it provide the key/path? *)
(* `Art.fold` implementation: `let acc = match node.value ... in List.fold ... child` *)
(* It does NOT pass the path to the function. *)
(* `Vfs.fold` requires constructing full path for `Eval.entry`. *)
(* I need `Art.fold_path` or similar. *)

(* Let's add `fold_path` to Art.ml later or reimplement fold here by traversing Art manually? *)
(* Accessing `Art.t` structure requires `Art.children` types to be exposed. *)
(* I defined types in `Art.ml` but they are open. *)

(* Let's define `fold` here by recurring on Art structure if visible, or update Art.ml to export `fold_with_path`. *)
(* `Art.ml` types are visible. *)

let fold (f : 'a -> Eval.entry -> 'a) (acc : 'a) (t : t) : 'a =
  let rec traverse acc path_prefix node =
    let acc = 
      match node.Art.value with
      | None -> acc
      | Some entry ->
          let full_path = 
            if path_prefix = "" then "." 
            else path_prefix 
          in
          let eval_entry = {
            Eval.name = Filename.basename full_path;
            path = full_path;
            kind = entry.kind;
            size = entry.inode.size;
            mtime = entry.inode.mtime;
            perm = entry.inode.perm;
          } in
          f acc eval_entry
    in
    match node.Art.children with
    | Art.Small list ->
        List.fold_left (fun acc (key, child) ->
          let child_path = if path_prefix = "" then key else Filename.concat path_prefix key in
          traverse acc child_path child
        ) acc list
    | Art.Large map ->
        Art.PathMap.fold (fun key child acc ->
          let child_path = if path_prefix = "" then key else Filename.concat path_prefix key in
          traverse acc child_path child
        ) map acc
  in
  traverse acc "" t

(* Optimized fold with query-based pruning *)
let fold_with_query (f : 'a -> Eval.entry -> 'a) (acc : 'a) (t : t) (expr : Ast.Typed.expr) : 'a =
  let rec traverse acc path_prefix node =
    (* Check if we can prune this subtree *)
    if path_prefix <> "" && Eval.can_prune_path path_prefix expr then
      acc (* Skip this entire subtree *)
    else begin
      let acc = 
        match node.Art.value with
        | None -> acc
        | Some entry ->
            let full_path = 
              if path_prefix = "" then "." 
              else path_prefix 
            in
            let eval_entry = {
              Eval.name = Filename.basename full_path;
              path = full_path;
              kind = entry.kind;
              size = entry.inode.size;
              mtime = entry.inode.mtime;
              perm = entry.inode.perm;
            } in
            f acc eval_entry
      in
      match node.Art.children with
      | Art.Small list ->
          List.fold_left (fun acc (key, child) ->
            let child_path = if path_prefix = "" then key else Filename.concat path_prefix key in
            traverse acc child_path child
          ) acc list
      | Art.Large map ->
          Art.PathMap.fold (fun key child acc ->
            let child_path = if path_prefix = "" then key else Filename.concat path_prefix key in
            traverse acc child_path child
          ) map acc
    end
  in
  traverse acc "" t

(* Serialization *)
let save (t : t) (path : string) : unit =
  let oc = open_out_bin path in
  Marshal.to_channel oc t [];
  close_out oc

let load (path : string) : t option =
  try
    let ic = open_in_bin path in
    let t = Marshal.from_channel ic in
    close_in ic;
    Some t
  with _ -> None
