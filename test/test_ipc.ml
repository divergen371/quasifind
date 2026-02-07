(* Tests for IPC module *)
open Alcotest
open Quasifind

(* Test expr_to_json and json_to_expr round-trip *)
let test_ipc_roundtrip_simple () =
  let expr = Ast.Typed.Name (Ast.Typed.StrEq "test.ml") in
  let json = Ipc.expr_to_json expr in
  match Ipc.json_to_expr json with
  | Some expr' -> 
      (* Check that the expressions are functionally equivalent *)
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

(* Test request serialization *)
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

(* Test response serialization *)
let test_ipc_response () =
  let resp = Ipc.Success (`Assoc [("test", `String "value")]) in
  let json = Ipc.response_to_json resp in
  match Ipc.json_to_response json with
  | Ok (Ipc.Success _) -> ()
  | Ok (Ipc.Failure _) -> fail "Got Failure instead of Success"
  | Error msg -> fail msg

let suite = [
  "IPC", [
    test_case "Roundtrip simple expr" `Quick test_ipc_roundtrip_simple;
    test_case "Roundtrip complex expr" `Quick test_ipc_roundtrip_complex;
    test_case "Request Stats" `Quick test_ipc_request_stats;
    test_case "Request Shutdown" `Quick test_ipc_request_shutdown;
    test_case "Response" `Quick test_ipc_response;
  ];
]

let () = run "IPC" suite
