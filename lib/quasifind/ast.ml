type file_type = File | Dir | Symlink
[@@deriving show, eq]

type size_unit = B | KB | MB | GB | KiB | MiB | GiB
[@@deriving show, eq]

type dur_unit = S | M | H | D
[@@deriving show, eq]

(* Common operators *)
type cmp_op = Eq | Ne | Lt | Le | Gt | Ge | RegexMatch
[@@deriving show, eq]

module Untyped = struct
  type value = 
    | VString of string
    | VRegex of string
    | VInt of int64
    | VSize of int64 * size_unit
    | VDur of int64 * dur_unit
    | VType of file_type
  [@@deriving show, eq]

  type expr =
    | True
    | False
    | Not of expr
    | And of expr * expr
    | Or of expr * expr
    | Cmp of string * cmp_op * value
  [@@deriving show, eq]
end

module Typed = struct
  (* Normalized values *)
  type size_bytes = int64
  type time_seconds = float (* age in seconds *)

  type expr =
    | True
    | False
    | Not of expr
    | And of expr * expr
    | Or of expr * expr
    (* Specific typed comparisons *)
    | Name of string_cmp
    | Path of string_cmp
    | Type of type_cmp
    | Size of size_cmp
    | MTime of time_cmp
  
  and string_cmp = 
    | StrEq of string
    | StrNe of string
    | StrRe of Re.re (* Compiled regex *)

  and type_cmp =
    | TypeEq of file_type
    | TypeNe of file_type

  and size_cmp =
    | SizeEq of size_bytes
    | SizeNe of size_bytes
    | SizeLt of size_bytes
    | SizeLe of size_bytes
    | SizeGt of size_bytes
    | SizeGe of size_bytes

  and time_cmp =
    | TimeEq of time_seconds
    | TimeNe of time_seconds
    | TimeLt of time_seconds
    | TimeLe of time_seconds
    | TimeGt of time_seconds
    | TimeGe of time_seconds
end
