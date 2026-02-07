(* Tests for VFS module *)
open Alcotest
open Quasifind

(* Test VFS empty *)
let test_vfs_empty () =
  let t = Vfs.empty in
  check int "empty count" 0 (Vfs.count_nodes t)

(* Test VFS insert and fold *)
let test_vfs_insert_fold () =
  let t = Vfs.empty in
  let t = Vfs.insert t "lib/test.ml" `File 100L 1234567890.0 0o644 in
  let t = Vfs.insert t "lib/main.ml" `File 200L 1234567890.0 0o644 in
  let entries = Vfs.fold (fun acc e -> e :: acc) [] t in
  check int "two entries" 2 (List.length entries)

(* Test VFS remove *)
let test_vfs_remove () =
  let t = Vfs.empty in
  let t = Vfs.insert t "lib/test.ml" `File 100L 1234567890.0 0o644 in
  let t = Vfs.remove t "lib/test.ml" in
  let entries = Vfs.fold (fun acc e -> e :: acc) [] t in
  check int "zero entries after remove" 0 (List.length entries)

(* Test VFS save and load *)
let test_vfs_persistence () =
  let t = Vfs.empty in
  let t = Vfs.insert t "lib/test.ml" `File 100L 1234567890.0 0o644 in
  let path = Filename.temp_file "vfs_test" ".dump" in
  Vfs.save t path;
  match Vfs.load path with
  | Some loaded_t -> 
      let entries = Vfs.fold (fun acc e -> e :: acc) [] loaded_t in
      check int "one entry after load" 1 (List.length entries);
      Sys.remove path
  | None -> 
      Sys.remove path;
      fail "Failed to load VFS"

(* Test fold_with_query pruning *)
let test_vfs_fold_with_query () =
  let t = Vfs.empty in
  let t = Vfs.insert t "lib/a.ml" `File 100L 0.0 0o644 in
  let t = Vfs.insert t "lib/b.ml" `File 200L 0.0 0o644 in
  let t = Vfs.insert t "bin/c.ml" `File 300L 0.0 0o644 in
  (* Query for exact path - pruning should work *)
  let expr = Ast.Typed.Path (Ast.Typed.StrEq "lib/a.ml") in
  let entries = Vfs.fold_with_query (fun acc e -> e :: acc) [] t expr in
  (* We still visit entries because pruning is at directory level *)
  check bool "found lib/a.ml" true 
    (List.exists (fun e -> e.Eval.path = "lib/a.ml") entries)

let suite = [
  "VFS", [
    test_case "Empty VFS" `Quick test_vfs_empty;
    test_case "Insert and fold" `Quick test_vfs_insert_fold;
    test_case "Remove" `Quick test_vfs_remove;
    test_case "Persistence" `Quick test_vfs_persistence;
    test_case "Fold with query" `Quick test_vfs_fold_with_query;
  ];
]

let () = run "VFS" suite
