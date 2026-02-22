(* Tests for Qerror module *)
open Alcotest
open Quasifind

let test_parse_error_to_string () =
  let e = Qerror.ParseError "unexpected token" in
  let s = Qerror.to_string e in
  check bool "contains Parse" true (String.length s > 0);
  check bool "contains message" true (try ignore (Str.search_forward (Str.regexp_string "unexpected token") s 0); true with Not_found -> false)

let test_type_error_to_string () =
  let e = Qerror.TypeError "size expects int" in
  let s = Qerror.to_string e in
  check bool "non-empty" true (String.length s > 0)

let test_file_error_to_string () =
  let e = Qerror.FileError ("/tmp/missing.txt", "No such file") in
  let s = Qerror.to_string e in
  check bool "contains path" true (try ignore (Str.search_forward (Str.regexp_string "/tmp/missing.txt") s 0); true with Not_found -> false)

let test_daemon_error_to_string () =
  let e = Qerror.DaemonError "connection refused" in
  let s = Qerror.to_string e in
  check bool "non-empty" true (String.length s > 0)

let test_permission_denied_to_string () =
  let e = Qerror.PermissionDenied "/root/secret" in
  let s = Qerror.to_string e in
  check bool "contains path" true (try ignore (Str.search_forward (Str.regexp_string "/root/secret") s 0); true with Not_found -> false)

let test_general_error_to_string () =
  let e = Qerror.GeneralError "something broke" in
  let s = Qerror.to_string e in
  check bool "non-empty" true (String.length s > 0)

let test_exit_codes () =
  (* All errors should return a non-zero exit code *)
  let errors = [
    Qerror.ParseError "x";
    Qerror.TypeError "x";
    Qerror.FileError ("x", "x");
    Qerror.DaemonError "x";
    Qerror.PermissionDenied "x";
    Qerror.GeneralError "x";
  ] in
  List.iter (fun e ->
    check bool "non-zero exit" true (Qerror.to_exit_code e > 0)
  ) errors

let test_parser_returns_qerror () =
  match Parser.parse "" with
  | Ok _ -> fail "empty should fail"
  | Error (Qerror.ParseError _) -> ()
  | Error e -> fail ("Expected ParseError, got: " ^ Qerror.to_string e)

let test_typecheck_returns_qerror () =
  let input = Ast.Untyped.Cmp ("size", Ast.Eq, Ast.Untyped.VString "bad") in
  match Typecheck.check input with
  | Ok _ -> fail "should fail"
  | Error (Qerror.TypeError _) -> ()
  | Error e -> fail ("Expected TypeError, got: " ^ Qerror.to_string e)

let suite = [
  "Qerror to_string", [
    test_case "ParseError" `Quick test_parse_error_to_string;
    test_case "TypeError" `Quick test_type_error_to_string;
    test_case "FileError" `Quick test_file_error_to_string;
    test_case "DaemonError" `Quick test_daemon_error_to_string;
    test_case "PermissionDenied" `Quick test_permission_denied_to_string;
    test_case "GeneralError" `Quick test_general_error_to_string;
  ];
  "Qerror exit codes", [
    test_case "All non-zero" `Quick test_exit_codes;
  ];
  "Qerror integration", [
    test_case "Parser returns ParseError" `Quick test_parser_returns_qerror;
    test_case "Typecheck returns TypeError" `Quick test_typecheck_returns_qerror;
  ];
]

let () = run "Qerror" suite
