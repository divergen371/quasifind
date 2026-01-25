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

let check_string op s =
  match op with
  | StrEq target -> String.equal s target
  | StrNe target -> not (String.equal s target)
  | StrRe re -> Re.execp re s

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

let rec eval (now : float) (expr : Typed.expr) (ent : entry) : bool =
  match expr with
  | True -> true
  | False -> false
  | Not e -> not (eval now e ent)
  | And (e1, e2) -> (eval now e1 ent) && (eval now e2 ent)
  | Or (e1, e2) -> (eval now e1 ent) || (eval now e2 ent)
  | Name op -> check_string op ent.name
  | Path op -> check_string op ent.path
  | Type op -> check_type op ent.kind
  | Size op -> check_size op ent.size
  | MTime op -> check_time now op ent.mtime
  | Perm op -> check_perm op ent.perm
