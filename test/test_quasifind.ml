open Alcotest
open Quasifind

(* === Parser Tests === *)

let test_parse_simple () =
  match Parser.parse "true" with
  | Ok _ -> ()
  | Error msg -> fail (Qerror.to_string msg)

let test_parse_complex () =
  match Parser.parse "(name == \"*.ml\" && size > 10MB) || type == file" with
  | Ok _ -> ()
  | Error msg -> fail (Qerror.to_string msg)

let test_parse_precedence () =
  match Parser.parse "true || false && true" with
  | Ok (Ast.Untyped.Or (Ast.Untyped.True, Ast.Untyped.And (Ast.Untyped.False, Ast.Untyped.True))) -> ()
  | Ok e -> fail ("Wrong precedence: " ^ Ast.Untyped.show_expr e)
  | Error msg -> fail (Qerror.to_string msg)

let test_parse_empty_string () =
  match Parser.parse "" with
  | Ok _ -> fail "Empty string should fail"
  | Error _ -> ()

let test_parse_whitespace_only () =
  match Parser.parse "   " with
  | Ok _ -> fail "Whitespace should fail"
  | Error _ -> ()

let test_parse_incomplete_expr () =
  match Parser.parse "name ==" with
  | Ok _ -> fail "Incomplete expr should fail"
  | Error _ -> ()

let test_parse_size_units () =
  let units = ["size > 1KB"; "size > 1MB"; "size > 1GB"; "size > 100B"] in
  List.iter (fun expr ->
    match Parser.parse expr with
    | Ok _ -> ()
    | Error msg -> fail (Printf.sprintf "Failed to parse '%s': %s" expr (Qerror.to_string msg))
  ) units

let test_parse_time_units () =
  let units = ["mtime < 7d"; "mtime < 2h"; "mtime < 30m"; "mtime < 60s"] in
  List.iter (fun expr ->
    match Parser.parse expr with
    | Ok _ -> ()
    | Error msg -> fail (Printf.sprintf "Failed to parse '%s': %s" expr (Qerror.to_string msg))
  ) units

let test_parse_regex () =
  match Parser.parse "name =~ /\\.ml$/" with
  | Ok _ -> ()
  | Error msg -> fail (Qerror.to_string msg)

let test_parse_nested_parens () =
  match Parser.parse "((true))" with
  | Ok _ -> ()
  | Error msg -> fail (Qerror.to_string msg)

let test_parse_long_chain () =
  let expr = String.concat " && " (List.init 10 (fun _ -> "true")) in
  match Parser.parse expr with
  | Ok _ -> ()
  | Error msg -> fail (Qerror.to_string msg)

let test_parse_not () =
  match Parser.parse "!true" with
  | Ok (Ast.Untyped.Not Ast.Untyped.True) -> ()
  | Ok e -> fail ("Wrong parse: " ^ Ast.Untyped.show_expr e)
  | Error msg -> fail (Qerror.to_string msg)

let test_parse_false () =
  match Parser.parse "false" with
  | Ok Ast.Untyped.False -> ()
  | Ok e -> fail ("Wrong parse: " ^ Ast.Untyped.show_expr e)
  | Error msg -> fail (Qerror.to_string msg)

let test_parse_garbage () =
  match Parser.parse "@#$%^&" with
  | Ok _ -> fail "Garbage should fail"
  | Error _ -> ()

(* === Typecheck Tests === *)

let test_typecheck_valid () =
  let input = Ast.Untyped.Cmp ("name", Ast.Eq, Ast.Untyped.VString "foo") in
  match Typecheck.check input with
  | Ok _ -> ()
  | Error e -> fail (Qerror.to_string e)

let test_typecheck_invalid () =
  let input = Ast.Untyped.Cmp ("size", Ast.Eq, Ast.Untyped.VString "big") in
  match Typecheck.check input with
  | Ok _ -> fail "Should reject type mismatch"
  | Error _ -> ()

let test_typecheck_name_gt_int () =
  (* name > 100 should fail: name expects string *)
  let input = Ast.Untyped.Cmp ("name", Ast.Gt, Ast.Untyped.VInt 100L) in
  match Typecheck.check input with
  | Ok _ -> fail "name > int should fail"
  | Error _ -> ()

let test_typecheck_size_valid () =
  let input = Ast.Untyped.Cmp ("size", Ast.Gt, Ast.Untyped.VSize (1024L, Ast.B)) in
  match Typecheck.check input with
  | Ok _ -> ()
  | Error e -> fail (Qerror.to_string e)

let test_typecheck_type_valid () =
  let input = Ast.Untyped.Cmp ("type", Ast.Eq, Ast.Untyped.VType Ast.File) in
  match Typecheck.check input with
  | Ok _ -> ()
  | Error e -> fail (Qerror.to_string e)

let test_typecheck_and_or () =
  let input = Ast.Untyped.And (
    Ast.Untyped.Cmp ("name", Ast.Eq, Ast.Untyped.VString "a"),
    Ast.Untyped.Or (
      Ast.Untyped.Cmp ("size", Ast.Gt, Ast.Untyped.VSize (0L, Ast.B)),
      Ast.Untyped.True
    )
  ) in
  match Typecheck.check input with
  | Ok _ -> ()
  | Error e -> fail (Qerror.to_string e)

let test_typecheck_not () =
  let input = Ast.Untyped.Not (Ast.Untyped.Cmp ("name", Ast.Eq, Ast.Untyped.VString "x")) in
  match Typecheck.check input with
  | Ok _ -> ()
  | Error e -> fail (Qerror.to_string e)

(* === Eval Tests === *)

let make_entry ?(name="test.ml") ?(path="/tmp/test.ml") ?(kind=Ast.File) ?(size=100L) ?(mtime=1000.0) ?(perm=0o644) () : Eval.entry =
  { Eval.name; path; kind; size; mtime; perm }

let test_eval_name_eq () =
  let expr = Ast.Typed.Name (Ast.Typed.StrEq "test.ml") in
  check bool "match" true (Eval.eval 0.0 expr (make_entry ()));
  check bool "no match" false (Eval.eval 0.0 expr (make_entry ~name:"other.ml" ()))

let test_eval_name_ne () =
  let expr = Ast.Typed.Name (Ast.Typed.StrNe "test.ml") in
  check bool "ne match" true (Eval.eval 0.0 expr (make_entry ~name:"other.ml" ()));
  check bool "ne no match" false (Eval.eval 0.0 expr (make_entry ()))

let test_eval_size_gt () =
  let expr = Ast.Typed.Size (Ast.Typed.SizeGt 50L) in
  check bool "100 > 50" true (Eval.eval 0.0 expr (make_entry ~size:100L ()));
  check bool "50 > 50" false (Eval.eval 0.0 expr (make_entry ~size:50L ()));
  check bool "0 > 50" false (Eval.eval 0.0 expr (make_entry ~size:0L ()))

let test_eval_size_lt () =
  let expr = Ast.Typed.Size (Ast.Typed.SizeLt 50L) in
  check bool "10 < 50" true (Eval.eval 0.0 expr (make_entry ~size:10L ()));
  check bool "50 < 50" false (Eval.eval 0.0 expr (make_entry ~size:50L ()))

let test_eval_size_eq () =
  let expr = Ast.Typed.Size (Ast.Typed.SizeEq 100L) in
  check bool "eq" true (Eval.eval 0.0 expr (make_entry ~size:100L ()));
  check bool "ne" false (Eval.eval 0.0 expr (make_entry ~size:99L ()))

let test_eval_type_file () =
  let expr = Ast.Typed.Type (Ast.Typed.TypeEq Ast.File) in
  check bool "file" true (Eval.eval 0.0 expr (make_entry ~kind:Ast.File ()));
  check bool "dir" false (Eval.eval 0.0 expr (make_entry ~kind:Ast.Dir ()))

let test_eval_type_dir () =
  let expr = Ast.Typed.Type (Ast.Typed.TypeEq Ast.Dir) in
  check bool "dir" true (Eval.eval 0.0 expr (make_entry ~kind:Ast.Dir ()));
  check bool "file" false (Eval.eval 0.0 expr (make_entry ~kind:Ast.File ()))

let test_eval_and () =
  let expr = Ast.Typed.And (
    Ast.Typed.Name (Ast.Typed.StrEq "test.ml"),
    Ast.Typed.Size (Ast.Typed.SizeGt 50L)
  ) in
  check bool "both true" true (Eval.eval 0.0 expr (make_entry ()));
  check bool "name wrong" false (Eval.eval 0.0 expr (make_entry ~name:"x" ()));
  check bool "size wrong" false (Eval.eval 0.0 expr (make_entry ~size:10L ()))

let test_eval_or () =
  let expr = Ast.Typed.Or (
    Ast.Typed.Name (Ast.Typed.StrEq "test.ml"),
    Ast.Typed.Size (Ast.Typed.SizeGt 1000L)
  ) in
  check bool "name true" true (Eval.eval 0.0 expr (make_entry ()));
  check bool "size true" true (Eval.eval 0.0 expr (make_entry ~name:"x" ~size:2000L ()));
  check bool "neither" false (Eval.eval 0.0 expr (make_entry ~name:"x" ~size:10L ()))

let test_eval_not () =
  let expr = Ast.Typed.Not (Ast.Typed.Name (Ast.Typed.StrEq "test.ml")) in
  check bool "not match" true (Eval.eval 0.0 expr (make_entry ~name:"other.ml" ()));
  check bool "not no match" false (Eval.eval 0.0 expr (make_entry ()))

let test_eval_true_false () =
  check bool "true" true (Eval.eval 0.0 Ast.Typed.True (make_entry ()));
  check bool "false" false (Eval.eval 0.0 Ast.Typed.False (make_entry ()))

let test_eval_perm () =
  let expr = Ast.Typed.Perm (Ast.Typed.PermEq 0o644) in
  check bool "eq" true (Eval.eval 0.0 expr (make_entry ~perm:0o644 ()));
  check bool "ne" false (Eval.eval 0.0 expr (make_entry ~perm:0o755 ()))

let test_eval_size_zero () =
  let expr = Ast.Typed.Size (Ast.Typed.SizeEq 0L) in
  check bool "zero" true (Eval.eval 0.0 expr (make_entry ~size:0L ()));
  check bool "nonzero" false (Eval.eval 0.0 expr (make_entry ~size:1L ()))

let suite = [
  "Parser", [
    test_case "Simple true" `Quick test_parse_simple;
    test_case "Complex expr" `Quick test_parse_complex;
    test_case "Precedence" `Quick test_parse_precedence;
    test_case "Empty string" `Quick test_parse_empty_string;
    test_case "Whitespace only" `Quick test_parse_whitespace_only;
    test_case "Incomplete expr" `Quick test_parse_incomplete_expr;
    test_case "Size units" `Quick test_parse_size_units;
    test_case "Time units" `Quick test_parse_time_units;
    test_case "Regex" `Quick test_parse_regex;
    test_case "Nested parens" `Quick test_parse_nested_parens;
    test_case "Long AND chain" `Quick test_parse_long_chain;
    test_case "Not" `Quick test_parse_not;
    test_case "False" `Quick test_parse_false;
    test_case "Garbage input" `Quick test_parse_garbage;
  ];
  "Typecheck", [
    test_case "Valid name expr" `Quick test_typecheck_valid;
    test_case "Invalid size=string" `Quick test_typecheck_invalid;
    test_case "name > int mismatch" `Quick test_typecheck_name_gt_int;
    test_case "Valid size expr" `Quick test_typecheck_size_valid;
    test_case "Valid type expr" `Quick test_typecheck_type_valid;
    test_case "And/Or composite" `Quick test_typecheck_and_or;
    test_case "Not" `Quick test_typecheck_not;
  ];
  "Eval", [
    test_case "Name StrEq" `Quick test_eval_name_eq;
    test_case "Name StrNe" `Quick test_eval_name_ne;
    test_case "Size Gt" `Quick test_eval_size_gt;
    test_case "Size Lt" `Quick test_eval_size_lt;
    test_case "Size Eq" `Quick test_eval_size_eq;
    test_case "Type file" `Quick test_eval_type_file;
    test_case "Type dir" `Quick test_eval_type_dir;
    test_case "And" `Quick test_eval_and;
    test_case "Or" `Quick test_eval_or;
    test_case "Not" `Quick test_eval_not;
    test_case "True/False" `Quick test_eval_true_false;
    test_case "Perm" `Quick test_eval_perm;
    test_case "Size zero" `Quick test_eval_size_zero;
  ];
]

let () = run "Quasifind" suite
