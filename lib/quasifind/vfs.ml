(* Virtual File System (VFS) for Daemon Mode *)
(* Provides an in-memory representation of the filesystem using a Trie *)

type inode = {
  size : int64;
  mtime : float;
  perm : int;
}

module StringMap = Map.Make(String)

type node = 
  | File of inode
  | Dir of inode * node StringMap.t

type t = node

let empty = Dir ({ size = 0L; mtime = 0.0; perm = 0o755 }, StringMap.empty)

(* Helper to split path into components *)
let split_path path =
  String.split_on_char '/' path
  |> List.filter (fun s -> s <> "" && s <> ".")

(* Insert a file/dir into the VFS *)
let insert t path kind size mtime perm =
  let rec insert_node node parts =
    match node, parts with
    | Dir (inode, children), [] ->
        (* Exact match: update inode or replace if kind changed *)
        (* For now, just update inode, assuming kind is same or we overwrite *)
        (match kind with
         | `File -> File { size; mtime; perm }
         | `Dir -> Dir ({ size; mtime; perm }, children)) (* Preserve children *)
    
    | Dir (inode, children), part :: rest ->
        let child = 
          match StringMap.find_opt part children with
          | Some c -> c
          | None -> Dir ({ size = 0L; mtime = 0.0; perm = 0o755 }, StringMap.empty) (* Default intermediate dir *)
        in
        let new_child = insert_node child rest in
        Dir (inode, StringMap.add part new_child children)

    | File _, _ ->
        (* Conflict: path treats a file as a directory *)
        (* In a real FS, this is impossible unless the file was deleted/replaced. *)
        (* For PoC, we mimic `mkdir -p` behavior by overwriting file with dir if needed? *)
        (* Or just fail/log. Let's overwrite for now. *)
        let new_dir = Dir ({ size = 0L; mtime = 0.0; perm = 0o755 }, StringMap.empty) in
        insert_node new_dir parts
  in
  insert_node t (split_path path)

(* Lookup a node by path *)
let find_opt t path =
  let rec find_node node parts =
    match node, parts with
    | _, [] -> Some node
    | Dir (_, children), part :: rest ->
        (match StringMap.find_opt part children with
         | Some child -> find_node child rest
         | None -> None)
    | File _, _ -> None
  in
  find_node t (split_path path)

(* Calculate total nodes (for stats) *)
let rec count_nodes = function
  | File _ -> 1
  | Dir (_, children) -> 
      1 + (StringMap.fold (fun _ child acc -> acc + count_nodes child) children 0)

(* Debug: Print tree structure (limited depth) *)
let print_tree ?(max_depth=2) t =
  let rec print_node indent depth name node =
    if depth > max_depth then () else
    match node with
    | File inode -> Printf.printf "%s- %s (size=%Ld)\n" indent name inode.size
    | Dir (inode, children) ->
        Printf.printf "%s+ %s/\n" indent name;
        StringMap.iter (fun n c -> print_node (indent ^ "  ") (depth + 1) n c) children
  in
  print_node "" 0 "." t
