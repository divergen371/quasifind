(* formatter.ml - Output formatting with color support *)

type format = Default | Json | Csv | Table | Null

type color_mode = Always | Auto | Never

let parse_format = function
  | "default" -> Some Default
  | "json" -> Some Json
  | "csv" -> Some Csv
  | "table" -> Some Table
  | "null" -> Some Null
  | _ -> None

let parse_color = function
  | "always" -> Some Always
  | "auto" -> Some Auto
  | "never" -> Some Never
  | _ -> None

(* ANSI color codes *)
let reset = "\027[0m"
let blue = "\027[34m"
let green = "\027[32m"
let cyan = "\027[36m"

let is_tty = lazy (Unix.isatty Unix.stdout)

let use_color = function
  | Always -> true
  | Never -> false
  | Auto -> Lazy.force is_tty

let kind_string (k : Ast.file_type) =
  match k with
  | Ast.File -> "file"
  | Ast.Dir -> "dir"
  | Ast.Symlink -> "symlink"

let is_executable perm = perm land 0o111 <> 0

let colorize color_mode (entry : Eval.entry) path =
  if not (use_color color_mode) then path
  else
    match entry.kind with
    | Ast.Dir -> blue ^ path ^ reset
    | Ast.Symlink -> cyan ^ path ^ reset
    | Ast.File when is_executable entry.perm -> green ^ path ^ reset
    | _ -> path

let escape_json s =
  let buf = Buffer.create (String.length s) in
  String.iter (fun c ->
    match c with
    | '"' -> Buffer.add_string buf "\\\""
    | '\\' -> Buffer.add_string buf "\\\\"
    | '\n' -> Buffer.add_string buf "\\n"
    | '\t' -> Buffer.add_string buf "\\t"
    | '\r' -> Buffer.add_string buf "\\r"
    | c when Char.code c < 0x20 ->
        Buffer.add_string buf (Printf.sprintf "\\u%04x" (Char.code c))
    | c -> Buffer.add_char buf c
  ) s;
  Buffer.contents buf

let format_mtime mtime =
  let t = Unix.localtime mtime in
  Printf.sprintf "%04d-%02d-%02d %02d:%02d:%02d"
    (t.tm_year + 1900) (t.tm_mon + 1) t.tm_mday
    t.tm_hour t.tm_min t.tm_sec

let format_size size =
  let s = Int64.to_float size in
  if s >= 1_073_741_824.0 then Printf.sprintf "%.1fG" (s /. 1_073_741_824.0)
  else if s >= 1_048_576.0 then Printf.sprintf "%.1fM" (s /. 1_048_576.0)
  else if s >= 1024.0 then Printf.sprintf "%.1fK" (s /. 1024.0)
  else Printf.sprintf "%Ld" size

let perm_string perm =
  let r f = if perm land f <> 0 then "r" else "-" in
  let w f = if perm land f <> 0 then "w" else "-" in
  let x f = if perm land f <> 0 then "x" else "-" in
  r 0o400 ^ w 0o200 ^ x 0o100 ^
  r 0o040 ^ w 0o020 ^ x 0o010 ^
  r 0o004 ^ w 0o002 ^ x 0o001

let format_entry ~format ~color (entry : Eval.entry) =
  match format with
  | Default ->
      colorize color entry entry.path
  | Json ->
      Printf.sprintf "  {\"path\": \"%s\", \"name\": \"%s\", \"size\": %Ld, \"type\": \"%s\", \"mtime\": \"%s\", \"perm\": \"%s\"}"
        (escape_json entry.path) (escape_json entry.name)
        entry.size (kind_string entry.kind)
        (format_mtime entry.mtime) (perm_string entry.perm)
  | Csv ->
      Printf.sprintf "%s,%s,%Ld,%s,%s,%s"
        entry.path entry.name entry.size
        (kind_string entry.kind) (format_mtime entry.mtime)
        (perm_string entry.perm)
  | Table ->
      Printf.sprintf "%-60s %8s  %-7s  %s  %s"
        (colorize color entry entry.path)
        (format_size entry.size) (kind_string entry.kind)
        (perm_string entry.perm) (format_mtime entry.mtime)
  | Null ->
      entry.path

let format_header ~format =
  match format with
  | Csv -> Some "path,name,size,type,mtime,perm"
  | Table -> Some (Printf.sprintf "%-60s %8s  %-7s  %s  %s"
      "PATH" "SIZE" "TYPE" "PERM" "MODIFIED")
  | _ -> None

let format_json_start () = "["
let format_json_end () = "]"
