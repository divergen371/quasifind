open Alcotest
open Quasifind

let test_default_rules_typecheck () =
  (* Default rules from Suspicious module should type-check successfully *)
  let untyped_ast = Suspicious.default_rules () in
  match Typecheck.check untyped_ast with
  | Ok _ -> ()
  | Error e -> fail ("Default suspicious rules failed typecheck: " ^ Typecheck.string_of_error e)

let test_rules_combine () =
  (* Test that rules() returns a valid AST even when rule_loader is empty or has invalid rules *)
  let combined_ast = Suspicious.rules () in
  match Typecheck.check combined_ast with
  | Ok _ -> ()
  | Error e -> fail ("Combined suspicious rules failed typecheck: " ^ Typecheck.string_of_error e)

let test_hidden_exec_detection () =
  (* Test that hidden executable pattern matches correctly *)
  (* Pattern: name starts with dot AND contains .sh/.py/.exe extension *)
  (* Use simpler regex to avoid double-escaping complexity *)
  let expr_str = "name =~ /^\\..+\\.sh$/" in
  match Parser.parse expr_str with
  | Ok untyped_ast ->
      (match Typecheck.check untyped_ast with
       | Ok typed_ast ->
           let entry = { Eval.name = ".malware.sh"; path = "/tmp/.malware.sh"; kind = Ast.File; size = 100L; mtime = 0.0; perm = 0 } in
           check bool "hidden shell script detected" true (Eval.eval 0.0 typed_ast entry)
       | Error e -> fail ("Typecheck error: " ^ Typecheck.string_of_error e))
  | Error msg -> fail ("Parse error: " ^ msg)

let test_dangerous_perm_detection () =
  (* Test 777 permission detection *)
  let expr_str = "perm == 0o777" in
  match Parser.parse expr_str with
  | Ok untyped_ast ->
      (match Typecheck.check untyped_ast with
       | Ok typed_ast ->
           let dangerous_entry = { Eval.name = "file.txt"; path = "/tmp/file.txt"; kind = Ast.File; size = 0L; mtime = 0.0; perm = 0o777 } in
           check bool "777 perm detected" true (Eval.eval 0.0 typed_ast dangerous_entry);
           let safe_entry = { Eval.name = "file.txt"; path = "/tmp/file.txt"; kind = Ast.File; size = 0L; mtime = 0.0; perm = 0o644 } in
           check bool "644 perm NOT detected" false (Eval.eval 0.0 typed_ast safe_entry)
       | Error e -> fail ("Typecheck error: " ^ Typecheck.string_of_error e))
  | Error msg -> fail ("Parse error: " ^ msg)

let suite = [
  "Suspicious", [
    test_case "Default Rules Typecheck" `Quick test_default_rules_typecheck;
    test_case "Rules Combine" `Quick test_rules_combine;
    test_case "Hidden Exec Detection" `Quick test_hidden_exec_detection;
    test_case "Dangerous Perm Detection" `Quick test_dangerous_perm_detection;
  ]
]

let () = run "Quasifind Suspicious" suite
