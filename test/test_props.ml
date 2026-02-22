(* QCheck property-based tests for Quasifind *)
open Quasifind

(* === ART property tests === *)

type test_entry = { size : int64; name : string }

(* Generator: list of path segments *)
let gen_path_segments =
  QCheck.Gen.(list_size (int_range 1 6) (string_size ~gen:printable (int_range 1 10)))

let gen_entry =
  QCheck.Gen.(map (fun s -> { size = Int64.of_int s; name = "f" }) (int_range 0 10000))

(* Property: insert then find_opt always succeeds *)
let prop_insert_find =
  QCheck.Test.make ~count:200 ~name:"insert then find_opt returns Some"
    QCheck.(pair (make gen_path_segments) (make gen_entry))
    (fun (key, value) ->
       let t = Art.insert Art.empty key value in
       match Art.find_opt t key with
       | Some v -> v.size = value.size
       | None -> false)

(* Property: remove after insert makes find_opt return None *)
let prop_remove_after_insert =
  QCheck.Test.make ~count:200 ~name:"remove after insert returns None"
    QCheck.(pair (make gen_path_segments) (make gen_entry))
    (fun (key, value) ->
       let t = Art.insert Art.empty key value in
       let t = Art.remove t key in
       Option.is_none (Art.find_opt t key))

(* Property: count_nodes increases or stays same after insert *)
let prop_count_insert =
  QCheck.Test.make ~count:200 ~name:"count_nodes non-decreasing on insert"
    QCheck.(pair (make gen_path_segments) (make gen_entry))
    (fun (key, value) ->
       let t = Art.empty in
       let before = Art.count_nodes t in
       let t = Art.insert t key value in
       Art.count_nodes t >= before)

(* Property: multiple inserts, all findable *)
let prop_multi_insert =
  QCheck.Test.make ~count:100 ~name:"all inserted keys findable"
    QCheck.(make QCheck.Gen.(list_size (int_range 1 20) (pair gen_path_segments gen_entry)))
    (fun entries ->
       let t = List.fold_left (fun t (k, v) -> Art.insert t k v) Art.empty entries in
       List.for_all (fun (k, _) -> Option.is_some (Art.find_opt t k)) entries)

(* Property: count_nodes matches fold count *)
let prop_count_vs_fold =
  QCheck.Test.make ~count:100 ~name:"count_nodes equals fold count"
    QCheck.(make QCheck.Gen.(list_size (int_range 0 20) (pair gen_path_segments gen_entry)))
    (fun entries ->
       let t = List.fold_left (fun t (k, v) -> Art.insert t k v) Art.empty entries in
       let fold_count = Art.fold (fun acc _ -> acc + 1) 0 t in
       Art.count_nodes t = fold_count)

(* === IPC JSON roundtrip tests === *)

(* Generator for simple typed AST expressions *)
let gen_string_op =
  QCheck.Gen.(map (fun s -> Ast.Typed.StrEq s) (string_size ~gen:printable (int_range 1 8)))

let gen_simple_expr =
  QCheck.Gen.(oneof [
    return Ast.Typed.True;
    return Ast.Typed.False;
    map (fun op -> Ast.Typed.Name op) gen_string_op;
    map (fun s -> Ast.Typed.Size (Ast.Typed.SizeGt (Int64.of_int s))) (int_range 0 100000);
  ])

let prop_ipc_expr_roundtrip =
  QCheck.Test.make ~count:100 ~name:"IPC expr JSON roundtrip"
    QCheck.(make gen_simple_expr)
    (fun expr ->
       let json = Ipc.expr_to_json expr in
       match Ipc.json_to_expr json with
       | Some _ -> true  (* Successfully parsed back *)
       | None -> false)

(* Property: request roundtrip *)
let prop_ipc_request_roundtrip =
  QCheck.Test.make ~count:50 ~name:"IPC request JSON roundtrip"
    QCheck.(make gen_simple_expr)
    (fun expr ->
       let req = Ipc.Query expr in
       let json = Ipc.request_to_json req in
       match Ipc.json_to_request json with
       | Ok (Ipc.Query _) -> true
       | _ -> false)

(* === Parser property tests === *)

(* Known-good expressions that should always parse *)
let gen_parseable_expr =
  QCheck.Gen.(oneof [
    return "true";
    return "false";
    map (fun n -> Printf.sprintf "name == \"%s\"" n) (string_size ~gen:(char_range 'a' 'z') (int_range 1 5));
    map (fun s -> Printf.sprintf "size > %d" s) (int_range 0 10000);
    return "type == file";
    return "type == dir";
  ])

let prop_parser_no_exception =
  QCheck.Test.make ~count:200 ~name:"Parser.parse never raises exceptions"
    QCheck.(make gen_parseable_expr)
    (fun input ->
       match Parser.parse input with
       | Ok _ -> true
       | Error _ -> true  (* Error is fine, exceptions are not *))

let () =
  let suite = List.map QCheck_alcotest.to_alcotest [
    prop_insert_find;
    prop_remove_after_insert;
    prop_count_insert;
    prop_multi_insert;
    prop_count_vs_fold;
    prop_ipc_expr_roundtrip;
    prop_ipc_request_roundtrip;
    prop_parser_no_exception;
  ] in
  Alcotest.run "Quasifind Properties" [
    "ART properties", suite;
  ]
