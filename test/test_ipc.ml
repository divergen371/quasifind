(* Tests for IPC module *)
open Alcotest
open Quasifind

(* === Roundtrip tests === *)

let test_ipc_roundtrip_simple () =
  let expr = Ast.Typed.Name (Ast.Typed.StrEq "test.ml") in
  let json = Ipc.expr_to_json expr in
  match Ipc.json_to_expr json with
  | Some expr' -> 
      let entry = {
        Eval.name = "test.ml"; path = "/test.ml";
        kind = Ast.File; size = 0L; mtime = 0.0; perm = 0
      } in
      check bool "roundtrip match" 
        (Eval.eval 0.0 expr entry) 
        (Eval.eval 0.0 expr' entry)
  | None -> fail "Failed to parse JSON back to expr"

let test_ipc_roundtrip_complex () =
  let expr = Ast.Typed.And (
    Ast.Typed.Name (Ast.Typed.StrEq "main.ml"),
    Ast.Typed.Size (Ast.Typed.SizeGt 1000L)
  ) in
  let json = Ipc.expr_to_json expr in
  match Ipc.json_to_expr json with
  | Some _ -> ()
  | None -> fail "Failed to parse complex expr"

let test_ipc_roundtrip_or () =
  let expr = Ast.Typed.Or (
    Ast.Typed.Name (Ast.Typed.StrEq "a.ml"),
    Ast.Typed.Name (Ast.Typed.StrEq "b.ml")
  ) in
  let json = Ipc.expr_to_json expr in
  match Ipc.json_to_expr json with
  | Some _ -> ()
  | None -> fail "Failed to parse Or expr"

let test_ipc_roundtrip_not () =
  let expr = Ast.Typed.Not (Ast.Typed.Name (Ast.Typed.StrEq "skip.ml")) in
  let json = Ipc.expr_to_json expr in
  match Ipc.json_to_expr json with
  | Some _ -> ()
  | None -> fail "Failed to parse Not expr"

let test_ipc_roundtrip_true_false () =
  let check_rt name e =
    let json = Ipc.expr_to_json e in
    match Ipc.json_to_expr json with
    | Some _ -> ()
    | None -> fail (name ^ " roundtrip failed")
  in
  check_rt "True" Ast.Typed.True;
  check_rt "False" Ast.Typed.False

let test_ipc_roundtrip_size () =
  let exprs = [
    Ast.Typed.Size (Ast.Typed.SizeGt 100L);
    Ast.Typed.Size (Ast.Typed.SizeLt 200L);
    Ast.Typed.Size (Ast.Typed.SizeEq 300L);
  ] in
  List.iter (fun expr ->
    let json = Ipc.expr_to_json expr in
    match Ipc.json_to_expr json with
    | Some _ -> ()
    | None -> fail "Size roundtrip failed"
  ) exprs

let test_ipc_roundtrip_type () =
  let exprs = [
    Ast.Typed.Type (Ast.Typed.TypeEq Ast.File);
    Ast.Typed.Type (Ast.Typed.TypeEq Ast.Dir);
  ] in
  List.iter (fun expr ->
    let json = Ipc.expr_to_json expr in
    match Ipc.json_to_expr json with
    | Some _ -> ()
    | None -> fail "Type roundtrip failed"
  ) exprs

(* === Request serialization tests === *)

let test_ipc_request_stats () =
  let req = Ipc.Stats in
  let json = Ipc.request_to_json req in
  match Ipc.json_to_request json with
  | Ok Ipc.Stats -> ()
  | Ok _ -> fail "Wrong request type"
  | Error msg -> fail msg

let test_ipc_request_shutdown () =
  let req = Ipc.Shutdown in
  let json = Ipc.request_to_json req in
  match Ipc.json_to_request json with
  | Ok Ipc.Shutdown -> ()
  | Ok _ -> fail "Wrong request type"
  | Error msg -> fail msg

let test_ipc_request_query () =
  let expr = Ast.Typed.Name (Ast.Typed.StrEq "test.ml") in
  let req = Ipc.Query expr in
  let json = Ipc.request_to_json req in
  match Ipc.json_to_request json with
  | Ok (Ipc.Query _) -> ()
  | Ok _ -> fail "Wrong request type"
  | Error msg -> fail msg

(* === Response serialization tests === *)

let test_ipc_response_success () =
  let resp = Ipc.Success (`Assoc [("test", `String "value")]) in
  let json = Ipc.response_to_json resp in
  match Ipc.json_to_response json with
  | Ok (Ipc.Success _) -> ()
  | Ok (Ipc.Failure _) -> fail "Got Failure instead of Success"
  | Ok (Ipc.Stream _) -> fail "Got Stream instead of Success"
  | Error msg -> fail msg

let test_ipc_response_failure () =
  let resp = Ipc.Failure "something went wrong" in
  let json = Ipc.response_to_json resp in
  match Ipc.json_to_response json with
  | Ok (Ipc.Failure msg) -> check string "error msg" "something went wrong" msg
  | Ok (Ipc.Success _) -> fail "Got Success instead of Failure"
  | Ok (Ipc.Stream _) -> fail "Got Stream instead of Failure"
  | Error msg -> fail msg

(* === Error / invalid input tests === *)

let test_ipc_invalid_json_request () =
  let json = `Assoc [("type", `String "nonsense")] in
  match Ipc.json_to_request json with
  | Ok _ -> fail "Should reject unknown request type"
  | Error _ -> ()

let test_ipc_malformed_request () =
  let json = `String "not an object" in
  (* Yojson raises Type_error on non-object input *)
  match (try Ipc.json_to_request json with _ -> Error "exception") with
  | Ok _ -> fail "Should reject non-object"
  | Error _ -> ()

let test_ipc_invalid_expr_json () =
  let json = `Assoc [("type", `String "query"); ("expr", `String "not valid")] in
  match (try Ipc.json_to_request json with _ -> Error "exception") with
  | Ok (Ipc.Query _) -> fail "Should reject invalid expr"
  | Ok _ -> ()  (* parsed as different type = ok *)
  | Error _ -> ()

let test_ipc_invalid_response_json () =
  let json = `List [`Int 1; `Int 2] in
  match (try Ipc.json_to_response json with _ -> Error "exception") with
  | Ok _ -> fail "Should reject non-object response"
  | Error _ -> ()

let test_ipc_response_missing_fields () =
  let json = `Assoc [("status", `String "unknown")] in
  match Ipc.json_to_response json with
  | Ok _ -> fail "Should reject unknown status"
  | Error _ -> ()

let suite = [
  "IPC Roundtrip", [
    test_case "Simple expr" `Quick test_ipc_roundtrip_simple;
    test_case "Complex expr" `Quick test_ipc_roundtrip_complex;
    test_case "Or expr" `Quick test_ipc_roundtrip_or;
    test_case "Not expr" `Quick test_ipc_roundtrip_not;
    test_case "True/False" `Quick test_ipc_roundtrip_true_false;
    test_case "Size variants" `Quick test_ipc_roundtrip_size;
    test_case "Type variants" `Quick test_ipc_roundtrip_type;
  ];
  "IPC Request", [
    test_case "Stats" `Quick test_ipc_request_stats;
    test_case "Shutdown" `Quick test_ipc_request_shutdown;
    test_case "Query" `Quick test_ipc_request_query;
  ];
  "IPC Response", [
    test_case "Success" `Quick test_ipc_response_success;
    test_case "Failure" `Quick test_ipc_response_failure;
  ];
  "IPC Error Cases", [
    test_case "Invalid request type" `Quick test_ipc_invalid_json_request;
    test_case "Malformed request" `Quick test_ipc_malformed_request;
    test_case "Invalid expr JSON" `Quick test_ipc_invalid_expr_json;
    test_case "Invalid response JSON" `Quick test_ipc_invalid_response_json;
    test_case "Missing response fields" `Quick test_ipc_response_missing_fields;
  ];
]

let () = run "IPC" suite
