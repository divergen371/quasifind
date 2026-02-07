open Angstrom
open Ast
open Ast.Untyped

let is_space = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false
let ws = skip_while is_space
let lex p = p <* ws
let sym s = lex (string s)

let ident =
  let is1 = function 'a' .. 'z' | 'A' .. 'Z' | '_' -> true | _ -> false in
  let is2 = function
    | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> true
    | _ -> false
  in
  lex (lift2 (fun c cs -> String.make 1 c ^ cs) (satisfy is1) (take_while is2))

let int64_p =
  lex (
    choice [
      (string "0x" *> take_while1 (function '0'..'9' | 'a'..'f' | 'A'..'F' -> true | _ -> false) >>| fun s -> "0x" ^ s);
      (string "0o" *> take_while1 (function '0'..'7' -> true | _ -> false) >>| fun s -> "0o" ^ s);
      (string "0b" *> take_while1 (function '0'..'1' -> true | _ -> false) >>| fun s -> "0b" ^ s);
      take_while1 (function '0' .. '9' -> true | _ -> false)
    ]
  ) >>= fun s ->
  try return (Int64.of_string s)
  with Failure _ -> fail "Invalid integer"

let float_p =
  lex (
    take_while1 (function '0'..'9' -> true | _ -> false) >>= fun whole ->
    char '.' *>
    take_while (function '0'..'9' -> true | _ -> false) >>= fun frac ->
    return (whole ^ "." ^ frac)
  ) >>= fun s ->
  try return (Float.of_string s)
  with Failure _ -> fail "Invalid float"

let quoted_string =
  let escaped =
    char '\\' *> any_char >>| function
    | 'n' -> '\n'
    | 't' -> '\t'
    | 'r' -> '\r'
    | c -> c
  in
  let normal = satisfy (fun c -> c <> '"' && c <> '\\') in
  lex
    ( char '"' *> many (escaped <|> normal) <* char '"' >>| fun cs ->
      String.of_seq (List.to_seq cs) )

let regex_literal =
  (* /.../ ; supports escaped \/ *)
  let escaped = char '\\' *> any_char >>| fun c -> Some c in
  let normal = satisfy (fun c -> c <> '/' && c <> '\\') >>| fun c -> Some c in
  let piece =
    many (escaped <|> normal) >>| fun xs ->
    let buf = Buffer.create 32 in
    List.iter (function None -> () | Some c -> Buffer.add_char buf c) xs;
    Buffer.contents buf
  in
  lex (char '/' *> piece <* char '/')

let file_type_p =
  ident >>= function
  | "file" | "f" -> return File
  | "dir" | "d" -> return Dir
  | "symlink" | "l" -> return Symlink
  | _ -> fail "Expected file type"

let size_unit_p =
  ident >>= function
  | "B" -> return B
  | "KB" -> return KB
  | "MB" -> return MB
  | "GB" -> return GB
  | "KiB" -> return KiB
  | "MiB" -> return MiB
  | "GiB" -> return GiB
  | _ -> fail "Expected size unit"

let dur_unit_p =
  ident >>= function
  | "s" -> return S
  | "m" -> return M
  | "h" -> return H
  | "d" -> return D
  | _ -> fail "Expected duration unit"

let value_p =
  choice [
    (regex_literal >>| fun s -> VRegex s);
    (file_type_p >>| fun t -> VType t);
    (quoted_string >>| fun s -> VString s);
    (float_p >>| fun f -> VFloat f);
    (int64_p >>= fun n ->
      choice [
        (size_unit_p >>| fun u -> VSize (n, u));
        (dur_unit_p >>| fun u -> VDur (n, u));
        (return (VInt n))
      ]
    )
  ]

let cmp_op_p =
  choice
    [
      sym "==" *> return Eq;
      sym "!=" *> return Ne;
      sym "<=" *> return Le;
      sym ">=" *> return Ge;
      sym "<" *> return Lt;
      sym ">" *> return Gt;
      sym "=~" *> return RegexMatch;
    ]

let parens p = sym "(" *> p <* sym ")"

let chainl1 e op =
  let rec go acc =
    (lift2 (fun f x -> f acc x) op e >>= go) <|> return acc
  in
  e >>= go

let expr_p =
  fix (fun expr ->
    let atom =
      choice [
        sym "true" *> return True;
        sym "false" *> return False;
        parens expr;
        (ident >>= fun f ->
           cmp_op_p >>= fun op ->
           value_p >>| fun v -> Cmp (f, op, v)
        )
      ]
    in
    
    let not_op = sym "!" *> return (fun e -> Not e) in
    let rec not_expr () = 
        (not_op >>= fun f -> not_expr () >>| f) <|> atom
    in

    let and_op = sym "&&" *> return (fun a b -> And (a, b)) in
    let and_expr = chainl1 (not_expr ()) and_op in
    
    let or_op = sym "||" *> return (fun a b -> Or (a, b)) in
    chainl1 and_expr or_op
  )

let parse (s : string) : (Ast.Untyped.expr, string) result =
  match
    parse_string ~consume:Consume.All (ws *> expr_p <* end_of_input) s
  with
  | Ok e -> Ok e
  | Error msg -> Error msg
