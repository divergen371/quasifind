open Ast
open Ast.Typed

type entry = {
  name : string;
  path : string;
  kind : Ast.file_type;
  size : int64;
  mtime : float; (* absolute usage time *)
  perm : int;
}

(* Helper functions defined in correct order *)

let check_string op s =
  match op with
  | StrEq target -> String.equal s target
  | StrNe target -> not (String.equal s target)
  | StrRe re -> Re.execp re s

(* Helper to read file content with optional timestamp preservation *)
let read_file_content path preserve =
  let read () =
    try
      let ic = open_in path in
      let len = in_channel_length ic in
      let buf = really_input_string ic len in
      close_in ic;
      Some buf
    with _ -> None
  in
  if preserve then
    match Unix.lstat path with
    | stats ->
        let atime = stats.st_atime in
        let mtime = stats.st_mtime in
        let res = read () in
        (try Unix.utimes path atime mtime with _ -> ());
        res
    | exception _ -> read ()
  else
    read ()

let check_content path preserve op =
  match read_file_content path preserve with
  | Some content -> check_string op content
  | None -> false

let calculate_entropy content =
  let len = String.length content in
  if len = 0 then 0.0
  else
    let counts = Array.make 256 0 in
    String.iter (fun c ->
      let code = Char.code c in
      counts.(code) <- counts.(code) + 1
    ) content;
    let total = float_of_int len in
    let entropy = ref 0.0 in
    Array.iter (fun count ->
      if count > 0 then
        let p = float_of_int count /. total in
        entropy := !entropy -. (p *. log p /. log 2.0)
    ) counts;
    !entropy

let check_float op f =
  match op with
  | FloatEq target -> Float.abs (f -. target) < epsilon_float
  | FloatNe target -> Float.abs (f -. target) >= epsilon_float
  | FloatLt target -> f < target
  | FloatLe target -> f <= target
  | FloatGt target -> f > target
  | FloatGe target -> f >= target

let check_entropy path preserve op =
  match read_file_content path preserve with
  | Some content -> check_float op (calculate_entropy content)
  | None -> false

let check_type op t =
  match op with
  | TypeEq target -> equal_file_type t target
  | TypeNe target -> not (equal_file_type t target)

let check_size op s =
  match op with
  | SizeEq target -> s = target
  | SizeNe target -> s <> target
  | SizeLt target -> s < target
  | SizeLe target -> s <= target
  | SizeGt target -> s > target
  | SizeGe target -> s >= target

let check_time now op mtime =
  let age = now -. mtime in
  match op with
  | TimeEq target -> age = target
  | TimeNe target -> age <> target
  | TimeLt target -> age < target
  | TimeLe target -> age <= target
  | TimeGt target -> age > target
  | TimeGe target -> age >= target

let check_perm op perm =
  match op with
  | PermEq target -> perm = target
  | PermNe target -> perm <> target
  | PermLt target -> perm < target
  | PermLe target -> perm <= target
  | PermGt target -> perm > target
  | PermGe target -> perm >= target

(* Main eval function with optional timestamp preservation *)
let rec eval ?(preserve_timestamps=false) (now : float) (expr : Typed.expr) (ent : entry) : bool =
  let recurse = eval ~preserve_timestamps now in
  match expr with
  | True -> true
  | False -> false
  | Not e -> not (recurse e ent)
  | And (e1, e2) -> (recurse e1 ent) && (recurse e2 ent)
  | Or (e1, e2) -> (recurse e1 ent) || (recurse e2 ent)
  | Name op -> check_string op ent.name
  | Path op -> check_string op ent.path
  | Content op -> check_content ent.path preserve_timestamps op
  | Type op -> check_type op ent.kind
  | Size op -> check_size op ent.size
  | MTime op -> check_time now op ent.mtime
  | Perm op -> check_perm op ent.perm
  | Entropy op -> check_entropy ent.path preserve_timestamps op
