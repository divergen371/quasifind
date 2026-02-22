(* Adaptive Radix Tree (ART) with Patricia Trie Compression for VFS *)
(* 
   Implementation details:
   - Keys are path segments (strings).
   - Nodes adapt based on number of children:
     - Small: <= 4 children (sorted list)
     - Large: > 4 children (Map)
   - Path Compression (Patricia Trie):
     Single-child intermediate nodes are compressed into a prefix list,
     dramatically reducing memory for deep directory hierarchies.
*)

module PathMap = Map.Make(String)

type 'a children =
  | Small of (string * 'a t) list (* Sorted, max 4 elements *)
  | Large of 'a t PathMap.t

and 'a t = {
  prefix : string list;   (* Compressed path segments *)
  value : 'a option;
  children : 'a children;
}

let empty = { prefix = []; value = None; children = Small [] }

let is_empty n = 
  Option.is_none n.value && 
  n.prefix = [] &&
  match n.children with Small [] -> true | Large m -> PathMap.is_empty m | _ -> false

(* Constants *)
let small_limit = 4

(* Helper: count children *)
let children_count = function
  | Small list -> List.length list
  | Large map -> PathMap.cardinal map

(* Helper: get child *)
let find_child key children =
  match children with
  | Small list -> List.assoc_opt key list
  | Large map -> PathMap.find_opt key map

(* Helper: add child (adaptive) *)
let add_child key child children =
  match children with
  | Small list ->
      let rec loop = function
        | [] -> [(key, child)]
        | (k, v) :: rest ->
            if k = key then (key, child) :: rest
            else if k > key then (key, child) :: (k, v) :: rest
            else (k, v) :: loop rest
      in
      let new_list = loop list in
      if List.length new_list > small_limit then
        Large (List.fold_left (fun acc (k, v) -> PathMap.add k v acc) PathMap.empty new_list)
      else
        Small new_list
  | Large map ->
      Large (PathMap.add key child map)

(* Helper: remove child *)
let remove_child key children =
  match children with
  | Small list ->
      Small (List.remove_assoc key list)
  | Large map ->
      let new_map = PathMap.remove key map in
      if PathMap.is_empty new_map then Small [] else Large new_map

(* Compute the common prefix of two string lists.
   Returns (common_prefix, remaining_a, remaining_b) *)
let rec split_prefix a b =
  match a, b with
  | x :: xs, y :: ys when String.equal x y ->
      let (common, ra, rb) = split_prefix xs ys in
      (x :: common, ra, rb)
  | _ -> ([], a, b)

(* Try to compress: if node has no value and exactly 1 child, merge prefix *)
let try_compress node =
  match node.value, node.children with
  | None, Small [(key, child)] ->
      { child with prefix = node.prefix @ [key] @ child.prefix }
  | _ -> node

let rec insert node path_parts value =
  match node.prefix, path_parts with
  (* No prefix on this node — standard insert *)
  | [], [] -> 
      { node with value = Some value }
  | [], part :: rest ->
      let child = 
        match find_child part node.children with
        | Some c -> c
        | None -> empty
      in
      let new_child = insert child rest value in
      { node with children = add_child part new_child node.children }
  
  (* Node has prefix — must check against incoming path *)
  | _, [] ->
      (* Path is shorter than prefix: need to split *)
      (* Create a new node at this point with the value,
         and push the existing node down with remaining prefix *)
      let old_child = { node with prefix = List.tl node.prefix } in
      let new_node = {
        prefix = [];
        value = Some value;
        children = add_child (List.hd node.prefix) old_child (Small []);
      } in
      new_node
  
  | px :: prest, kx :: krest ->
      if String.equal px kx then
        (* Prefix matches so far, consume and continue *)
        let inner = { node with prefix = prest } in
        let result = insert inner krest value in
        { result with prefix = px :: result.prefix }
      else
        (* Prefix diverges: split at this point *)
        let old_child = { node with prefix = prest } in
        let new_leaf = insert empty krest value in
        let split_node = {
          prefix = [];
          value = None;
          children = add_child px old_child (add_child kx new_leaf (Small []));
        } in
        split_node

let rec find_opt node path_parts =
  match node.prefix, path_parts with
  | [], [] -> node.value
  | [], part :: rest ->
      (match find_child part node.children with
       | Some child -> find_opt child rest
       | None -> None)
  | px :: prest, kx :: krest when String.equal px kx ->
      find_opt { node with prefix = prest } krest
  | _ -> None   (* prefix mismatch *)

let rec remove node path_parts =
  match node.prefix, path_parts with
  | [], [] -> 
      let cleared = { node with value = None } in
      try_compress cleared
  | [], part :: rest ->
      (match find_child part node.children with
       | None -> node
       | Some child ->
           let new_child = remove child rest in
           if is_empty new_child then
             let new_children = remove_child part node.children in
             try_compress { node with children = new_children }
           else
             try_compress { node with children = add_child part new_child node.children })
  | px :: prest, kx :: krest when String.equal px kx ->
      let inner = { node with prefix = prest } in
      let result = remove inner krest in
      if is_empty result then empty
      else { result with prefix = px :: result.prefix }
  | _ -> node  (* prefix mismatch — key doesn't exist *)

(* Fold without path *)
let rec fold f acc node =
  let acc = match node.value with Some v -> f acc v | None -> acc in
  match node.children with
  | Small list -> List.fold_left (fun acc (_, child) -> fold f acc child) acc list
  | Large map -> PathMap.fold (fun _ child acc -> fold f acc child) map acc

(* Build path from prefix segments + child key *)
let join_path prefix key =
  let parts = prefix @ [key] in
  match parts with
  | [] -> ""
  | [p] -> p
  | _ -> String.concat Filename.dir_sep parts

let extend_prefix base segments =
  if base = "" then String.concat Filename.dir_sep segments
  else base ^ Filename.dir_sep ^ String.concat Filename.dir_sep segments

(* Fold with path parameter *)
let fold_path (f : 'acc -> string -> 'a -> 'acc) (acc : 'acc) (t : 'a t) : 'acc =
  let rec traverse acc path_prefix node =
    (* Extend path with this node's compressed prefix *)
    let current_path = 
      match node.prefix with
      | [] -> path_prefix
      | segs -> if path_prefix = "" then String.concat Filename.dir_sep segs
                else extend_prefix path_prefix segs
    in
    let acc = 
      match node.value with
      | None -> acc
      | Some v ->
          let full_path = if current_path = "" then "." else current_path in
          f acc full_path v
    in
    match node.children with
    | Small list ->
        List.fold_left (fun acc (key, child) ->
          let child_path = if current_path = "" then key else Filename.concat current_path key in
          traverse acc child_path child
        ) acc list
    | Large map ->
        PathMap.fold (fun key child acc ->
          let child_path = if current_path = "" then key else Filename.concat current_path key in
          traverse acc child_path child
        ) map acc
  in
  traverse acc "" t

let count_nodes node = fold (fun acc _ -> acc + 1) 0 node

let fold_with_prune (can_prune : string -> bool) (f : 'acc -> string -> 'a -> 'acc) (acc : 'acc) (t : 'a t) : 'acc =
  let rec traverse acc path_prefix node =
    let current_path = 
      match node.prefix with
      | [] -> path_prefix
      | segs -> if path_prefix = "" then String.concat Filename.dir_sep segs
                else extend_prefix path_prefix segs
    in
    if current_path <> "" && can_prune current_path then
      acc
    else begin
      let acc = 
        match node.value with
        | None -> acc
        | Some v ->
            let full_path = if current_path = "" then "." else current_path in
            f acc full_path v
      in
      match node.children with
      | Small list ->
          List.fold_left (fun acc (key, child) ->
            let child_path = if current_path = "" then key else Filename.concat current_path key in
            traverse acc child_path child
          ) acc list
      | Large map ->
          PathMap.fold (fun key child acc ->
            let child_path = if current_path = "" then key else Filename.concat current_path key in
            traverse acc child_path child
          ) map acc
    end
  in
  traverse acc "" t
