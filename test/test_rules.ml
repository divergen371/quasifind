open Alcotest
open Quasifind

let test_valid_rule_parsing () =
  let expr_str = "name =~ /\\.php$/ && size > 10KB" in
  match Parser.parse expr_str with
  | Ok _ -> ()
  | Error msg -> fail ("Failed to parse valid rule: " ^ msg)

let test_invalid_rule_parsing () =
  let expr_str = "name =~ /unclosed_paren" in
  match Parser.parse expr_str with
  | Ok _ -> fail "Should fail on invalid regex syntax"
  | Error _ -> ()

let test_regex_escaping () =
  (* Test the specific case that caused the bug: escaped parens in regex *)
  let expr_str = "content =~ /eval\\(base64/" in 
  match Parser.parse expr_str with
  | Ok _ -> ()
  | Error msg -> fail ("Failed to parse escaped regex: " ^ msg)

let test_validation_valid () =
  let valid_ast = match Parser.parse "name =~ /foo/" with
    | Ok ast -> ast
    | Error e -> fail ("Failed to parse valid AST: " ^ e)
  in
  match Typecheck.check valid_ast with
  | Ok _ -> ()
  | Error e -> fail ("Valid AST failed typecheck: " ^ Typecheck.string_of_error e)

let test_validation_invalid () =
  (* Invalid regex in AST *)
  let invalid_ast = Ast.Untyped.Cmp ("name", Ast.RegexMatch, Ast.Untyped.VRegex "(") in
  match Typecheck.check invalid_ast with
  | Ok _ -> fail "Invalid regex should fail typecheck"
  | Error _ -> ()

let suite = [
  "Rules", [
    test_case "Valid Parsing" `Quick test_valid_rule_parsing;
    test_case "Invalid Parsing" `Quick test_invalid_rule_parsing;
    test_case "Regex Escaping" `Quick test_regex_escaping;
    test_case "Validation Valid" `Quick test_validation_valid;
    test_case "Validation Invalid" `Quick test_validation_invalid;
  ]
]

let () = run "Quasifind Rules" suite
