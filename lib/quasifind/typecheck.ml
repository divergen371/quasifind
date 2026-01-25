open Ast
open Ast.Untyped
open Ast.Typed

type error = 
  | UnknownField of string
  | TypeMismatch of { field: string; expected: string; got: string }
  | InvalidOp of { field: string; op: cmp_op; reason: string }
  | RegexError of string

let ( >>= ) = Result.bind

exception TypeError of error

let pp_error ppf = function
  | UnknownField f -> Format.fprintf ppf "Unknown field: %s" f
  | TypeMismatch { field; expected; got } ->
      Format.fprintf ppf "Type mismatch for field '%s': expected %s, got %s" field expected got
  | InvalidOp { field; op; reason } ->
      Format.fprintf ppf "Invalid operator '%s' for field '%s': %s" (show_cmp_op op) field reason
  | RegexError msg -> Format.fprintf ppf "Regex error: %s" msg

let string_of_error e = Format.asprintf "%a" pp_error e

(* Helper to normalized size to bytes *)
let normalize_size n unit =
  let m = match unit with
    | B -> 1L
    | KB -> 1000L
    | MB -> 1000000L
    | GB -> 1000000000L
    | KiB -> 1024L
    | MiB -> 1048576L
    | GiB -> 1073741824L
  in
  Int64.mul n m

(* Helper to normalize duration to seconds *)
let normalize_dur n unit =
  let m = match unit with
    | S -> 1L
    | M -> 60L
    | H -> 3600L
    | D -> 86400L
  in
  Int64.mul n m |> Int64.to_float

let compile_regex s : (Re.re, error) result =
  try Ok (Re.compile (Re.Pcre.re s))
  with Re.Pcre.Parse_error | Failure _ -> Error (RegexError s)

let check_value_string f = function
  | VString s -> Ok s
  | v -> Error (TypeMismatch { field = f; expected = "string"; got = show_value v })

let check_value_regex f = function
  | VRegex s -> compile_regex s
  | VString s -> compile_regex s (* Allow string as regex if operator is =~ *)
  | v -> Error (TypeMismatch { field = f; expected = "regex"; got = show_value v })

let check_value_float f = function
  | VFloat f -> Ok f
  | VInt n -> Ok (Float.of_int (Int64.to_int n))
  | v -> Error (TypeMismatch { field = f; expected = "float"; got = show_value v })

let check_value_size f = function
  | VSize (n, u) -> Ok (normalize_size n u)
  | VInt n -> Ok n (* Interpret raw int as bytes *)
  | v -> Error (TypeMismatch { field = f; expected = "size"; got = show_value v })

let check_value_time f = function
  | VDur (n, u) -> Ok (normalize_dur n u)
  | VInt n -> Ok (Int64.to_float n) (* Interpret raw int as seconds *)
  | v -> Error (TypeMismatch { field = f; expected = "duration"; got = show_value v })

let check_value_type f = function
  | VType t -> Ok t
  | v -> Error (TypeMismatch { field = f; expected = "file type"; got = show_value v })

let check_value_perm f = function
  | VInt n -> Ok (Int64.to_int n)
  | v -> Error (TypeMismatch { field = f; expected = "permission (int)"; got = show_value v })

let rec check (expr : Untyped.expr) : (Typed.expr, error) result =
  let open Result in
  match expr with
  | True -> Ok True
  | False -> Ok False
  | Not e -> check e |> map (fun e' -> Not e')
  | And (e1, e2) ->
      check e1 >>= fun e1' ->
      check e2 >>= fun e2' ->
      Ok (And (e1', e2'))
  | Or (e1, e2) ->
      check e1 >>= fun e1' ->
      check e2 >>= fun e2' ->
      Ok (Or (e1', e2'))
  | Cmp (field, op, value) ->
      check_cmp field op value

and check_cmp field op value =
  match field with
  | "name" -> check_name op value
  | "path" -> check_path op value
  | "content" -> check_content op value
  | "entropy" -> check_entropy op value
  | "type" -> check_type op value
  | "size" -> check_size op value
  | "mtime" -> check_mtime op value
  | "perm" -> check_perm op value
  | s -> Error (UnknownField s)

and check_name op value =
  match op with
  | Eq -> check_value_string "name" value |> Result.map (fun s -> Name (StrEq s))
  | Ne -> check_value_string "name" value |> Result.map (fun s -> Name (StrNe s))
  | RegexMatch -> check_value_regex "name" value |> Result.map (fun re -> Name (StrRe re))
  | _ -> Error (InvalidOp { field = "name"; op; reason = "only ==, !=, =~ supported" })

and check_path op value =
  match op with
  | Eq -> check_value_string "path" value |> Result.map (fun s -> Path (StrEq s))
  | Ne -> check_value_string "path" value |> Result.map (fun s -> Path (StrNe s))
  | RegexMatch -> check_value_regex "path" value |> Result.map (fun re -> Path (StrRe re))
  | _ -> Error (InvalidOp { field = "path"; op; reason = "only ==, !=, =~ supported" })

and check_content op value =
  match op with
  | Eq -> check_value_string "content" value |> Result.map (fun s -> Content (StrEq s))
  | Ne -> check_value_string "content" value |> Result.map (fun s -> Content (StrNe s))
  | RegexMatch -> check_value_regex "content" value |> Result.map (fun re -> Content (StrRe re))
  | _ -> Error (InvalidOp { field = "content"; op; reason = "only ==, !=, =~ supported" })

and check_type op value =
  match op with
  | Eq -> check_value_type "type" value |> Result.map (fun t -> Type (TypeEq t))
  | Ne -> check_value_type "type" value |> Result.map (fun t -> Type (TypeNe t))
  | _ -> Error (InvalidOp { field = "type"; op; reason = "only ==, != supported" })

and check_size op value =
  let mk_size v = 
    match op with
    | Eq -> Size (SizeEq v)
    | Ne -> Size (SizeNe v)
    | Lt -> Size (SizeLt v)
    | Le -> Size (SizeLe v)
    | Gt -> Size (SizeGt v)
    | Ge -> Size (SizeGe v)
    | RegexMatch -> failwith "unreachable" (* handled below *)
  in
  match op with
  | RegexMatch -> Error (InvalidOp { field = "size"; op; reason = "regex not supported" })
  | _ -> check_value_size "size" value |> Result.map mk_size

and check_mtime op value =
  let mk_time v =
    match op with
    | Eq -> MTime (TimeEq v)
    | Ne -> MTime (TimeNe v)
    | Lt -> MTime (TimeLt v)
    | Le -> MTime (TimeLe v)
    | Gt -> MTime (TimeGt v)
    | Ge -> MTime (TimeGe v)
    | RegexMatch -> failwith "unreachable"
  in
  match op with
  | RegexMatch -> Error (InvalidOp { field = "mtime"; op; reason = "regex not supported" })
  | _ -> check_value_time "mtime" value |> Result.map mk_time

and check_entropy op value =
  let mk_float v =
    match op with
    | Eq -> Entropy (FloatEq v)
    | Ne -> Entropy (FloatNe v)
    | Lt -> Entropy (FloatLt v)
    | Le -> Entropy (FloatLe v)
    | Gt -> Entropy (FloatGt v)
    | Ge -> Entropy (FloatGe v)
    | RegexMatch -> failwith "unreachable"
  in
  match op with
  | RegexMatch -> Error (InvalidOp { field = "entropy"; op; reason = "regex not supported" })
  | _ -> check_value_float "entropy" value |> Result.map mk_float

and check_perm op value =
  let mk_perm v =
    match op with
    | Eq -> Perm (PermEq v)
    | Ne -> Perm (PermNe v)
    | Lt -> Perm (PermLt v)
    | Le -> Perm (PermLe v)
    | Gt -> Perm (PermGt v)
    | Ge -> Perm (PermGe v)
    | RegexMatch -> failwith "unreachable"
  in
  match op with
  | RegexMatch -> Error (InvalidOp { field = "perm"; op; reason = "regex not supported" })
  | _ -> check_value_perm "perm" value |> Result.map mk_perm
