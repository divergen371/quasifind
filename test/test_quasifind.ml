open Alcotest
open Quasifind

let test_parse_simple () =
  let input = "true" in
  match Parser.parse input with
  | Ok _ -> ()
  | Error msg -> fail msg

let test_typecheck_valid () =
  let input = Ast.Untyped.Cmp ("name", Ast.Eq, Ast.Untyped.VString "foo") in
  match Typecheck.check input with
  | Ok _ -> ()
  | Error e -> fail (Typecheck.string_of_error e)

let test_typecheck_invalid () =
  let input = Ast.Untyped.Cmp ("size", Ast.Eq, Ast.Untyped.VString "big") in
  match Typecheck.check input with
  | Ok _ -> fail "Should verify type mismatch"
  | Error _ -> ()

let test_eval_simple () =
  let open Ast.Typed in
  let expr = Name (StrEq "test.ml") in
  let entry = {
    Eval.name = "test.ml";
    path = "/tmp/test.ml";
    kind = Ast.File; (* Ast.File *)
    size = 100L;
    mtime = 0.0;
  } in
  check bool "name match" true (Eval.eval 0.0 expr entry)

let test_parse_complex () =
  let input = "(name == \"*.ml\" && size > 10MB) || type == file" in
  match Parser.parse input with
  | Ok _ -> ()
  | Error msg -> fail msg

let test_parse_precedence () =
  let input = "true || false && true" in (* Should parse as true || (false && true) *)
  match Parser.parse input with
  | Ok (Ast.Untyped.Or (Ast.Untyped.True, Ast.Untyped.And (Ast.Untyped.False, Ast.Untyped.True))) -> ()
  | Ok e -> fail ("Wrong precedence: " ^ Ast.Untyped.show_expr e)
  | Error msg -> fail msg

let suite = [
  "Parser", [
    test_case "Simple true" `Quick test_parse_simple;
    test_case "Complex expr" `Quick test_parse_complex;
    test_case "Precedence" `Quick test_parse_precedence;
  ];
  "Typecheck", [
    test_case "Valid expr" `Quick test_typecheck_valid;
    test_case "Invalid expr" `Quick test_typecheck_invalid;
  ];
  "Eval", [
    test_case "Simple match" `Quick test_eval_simple;
  ];
]

let () = run "Quasifind" suite
