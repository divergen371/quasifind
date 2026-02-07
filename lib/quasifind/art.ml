(* Adaptive Radix Tree (ART) for VFS *)
(* 
   Implementation details:
   - Keys are path segments (strings).
   - Nodes adapt based on number of children:
     - Node4: <= 4 children (linear scan)
     - Node16: <= 16 children (sorted array + binary search or SIMD if avail)
     - Node48: <= 48 children (indirect index array)
     - Node256: <= 256 children (direct array)
   - Path Compression (Prefix Compression)
*)

module PathMap = Map.Make(String)

(* Adaptive Radix Tree (ART) - Functional Implementation *)

type 'a children =
  | Small of (string * 'a t) list (* Sorted, max 4 elements *)
  | Large of 'a t PathMap.t

and 'a t = {
  value : 'a option;
  children : 'a children;
}

let empty = { value = None; children = Small [] }

let is_empty n = Option.is_none n.value && match n.children with Small [] -> true | Large m -> PathMap.is_empty m | _ -> false

(* Constants *)
let small_limit = 4

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

(* Helper: remove child (adaptive? maybe lazy demotion) *)
let remove_child key children =
  match children with
  | Small list ->
      Small (List.remove_assoc key list)
  | Large map ->
      let new_map = PathMap.remove key map in
      (* Optional: Demote if small enough? For now, stick to Large to avoid thrashing *)
      if PathMap.is_empty new_map then Small [] else Large new_map

let rec insert node path_parts value =
  match path_parts with
  | [] -> { node with value = Some value }
  | part :: rest ->
      let child = 
        match find_child part node.children with
        | Some c -> c
        | None -> empty
      in
      let new_child = insert child rest value in
      { node with children = add_child part new_child node.children }

let rec find_opt node path_parts =
  match path_parts with
  | [] -> node.value
  | part :: rest ->
      match find_child part node.children with
      | Some child -> find_opt child rest
      | None -> None

let rec remove node path_parts =
  match path_parts with
  | [] -> { node with value = None }
  | part :: rest ->
      match find_child part node.children with
      | None -> node
      | Some child ->
          let new_child = remove child rest in
          if is_empty new_child then
            { node with children = remove_child part node.children }
          else
            { node with children = add_child part new_child node.children }

(* Fold *)
let rec fold f acc node =
  let acc = match node.value with Some v -> f acc v | None -> acc in
  match node.children with
  | Small list -> List.fold_left (fun acc (_, child) -> fold f acc child) acc list
  | Large map -> PathMap.fold (fun _ child acc -> fold f acc child) map acc

let count_nodes node = fold (fun acc _ -> acc + 1) 0 node

