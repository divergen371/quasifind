open Alcotest
open Quasifind
open Eio.Std

let setup_test_dir () =
  let temp_dir = Filename.temp_file "test_traverse" "" in
  Unix.unlink temp_dir;
  Unix.mkdir temp_dir 0o755;
  let write_file name content =
    let path = Filename.concat temp_dir name in
    let oc = open_out path in
    output_string oc content;
    close_out oc
  in
  write_file "a.txt" "hello";
  Unix.mkdir (Filename.concat temp_dir "sub") 0o755;
  let sub_file = Filename.concat (Filename.concat temp_dir "sub") "b.txt" in
  let oc = open_out sub_file in
  output_string oc "world";
  close_out oc;
  temp_dir

let teardown_test_dir p =
  ignore (Sys.command ("rm -rf " ^ p))

let collect_paths cfg root_path_str =
  let paths = ref [] in
  let emit (entry : Eval.entry) =
    paths := entry.path :: !paths
  in
  let expr = Ast.Typed.True in
  
  Eio_main.run (fun _env ->
      Traversal.traverse cfg root_path_str expr emit
  );
  List.sort String.compare !paths

let test_dfs () =
  let root = setup_test_dir () in
  try
    let cfg = {
      Traversal.strategy = Traversal.DFS;
      max_depth = None;
      follow_symlinks = false;
      include_hidden = false;
    } in
    let paths = collect_paths cfg root in
    let contains s = List.exists (fun p -> String.ends_with ~suffix:s p) paths in
    check bool "find a.txt" true (contains "a.txt");
    check bool "find b.txt" true (contains "b.txt");
    teardown_test_dir root
  with e ->
    teardown_test_dir root;
    raise e

let test_parallel () =
  let root = setup_test_dir () in
  try
    let cfg = {
      Traversal.strategy = Traversal.Parallel 4;
      max_depth = None;
      follow_symlinks = false;
      include_hidden = false;
    } in
    let paths = collect_paths cfg root in
    let contains s = List.exists (fun p -> String.ends_with ~suffix:s p) paths in
    check bool "find a.txt in parallel" true (contains "a.txt");
    check bool "find b.txt in parallel" true (contains "b.txt");
    teardown_test_dir root
  with e ->
    teardown_test_dir root;
    raise e

let test_filtering () =
  let root = setup_test_dir () in
  try
    let cfg = {
      Traversal.strategy = Traversal.DFS;
      max_depth = None;
      follow_symlinks = false;
      include_hidden = false;
    } in
    (* Custom collect function with filtering enabled, mimicking main.ml *)
    let paths = ref [] in
    let emit (entry : Eval.entry) =
      (* Filter: size > 0 (both a.txt and b.txt have content) AND name == "a.txt" *)
      let expr = Ast.Typed.(And (
        Size (SizeGt 0L),
        Name (StrEq "a.txt")
      )) in
      if Eval.eval (Unix.gettimeofday ()) expr entry then
        paths := entry.path :: !paths
    in
    (* We pass True to traverse, but filter in separate emit *)
    (* Wait, traverse signature takes expr but doesn't apply it for output. *)
    (* So we can test Eval logic integration here. *)
    
    Eio_main.run (fun _env ->
        Traversal.traverse cfg root Ast.Typed.True emit
    );
    
    let result = !paths in
    let contains s = List.exists (fun p -> String.ends_with ~suffix:s p) result in
    check bool "find a.txt" true (contains "a.txt");
    check bool "exclude b.txt" false (contains "b.txt");
    
    teardown_test_dir root
  with e ->
    teardown_test_dir root;
    raise e

let test_hidden_flag () =
  let root = setup_test_dir () in
  (* Create hidden file *)
  let oc = open_out (Filename.concat root ".hidden") in
  output_string oc "secret";
  close_out oc;
  
  try
    (* Default: include_hidden = false (should exclude) *)
    let cfg_default = {
      Traversal.strategy = Traversal.DFS;
      max_depth = None;
      follow_symlinks = false;
      include_hidden = false;
    } in
    let paths_def = collect_paths cfg_default root in
    let contains s paths = List.exists (fun p -> String.ends_with ~suffix:s p) paths in
    
    check bool "default finds a.txt" true (contains "a.txt" paths_def);
    check bool "default excludes .hidden" false (contains ".hidden" paths_def);

    (* Explicit: include_hidden = true (should include) *)
    let cfg_include = {
      Traversal.strategy = Traversal.DFS;
      max_depth = None;
      follow_symlinks = false;
      include_hidden = true;
    } in
    let paths_inc = collect_paths cfg_include root in
    
    check bool "explicit finds .hidden" true (contains ".hidden" paths_inc);
    
    teardown_test_dir root
  with e ->
    teardown_test_dir root;
    raise e

let suite = [
  "Traversal", [
    test_case "DFS" `Quick test_dfs;
    test_case "Parallel" `Quick test_parallel;
    test_case "Filtering" `Quick test_filtering;
    test_case "Hidden Flag" `Quick test_hidden_flag;
  ]
]

let () = run "Quasifind Traversal" suite
