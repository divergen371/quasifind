(* Tests for ART (Adaptive Radix Tree) module with Patricia Trie compression *)
open Alcotest
open Quasifind

type test_entry = { size : int64; name : string }

let mk n s = { size = s; name = n }

(* === Basic operations === *)

let test_art_empty () =
  let t : test_entry Art.t = Art.empty in
  check bool "empty has no value" true (Option.is_none t.Art.value);
  check int "empty count" 0 (Art.count_nodes t)

let test_art_insert_find () =
  let t : test_entry Art.t = Art.empty in
  let entry = mk "test.ml" 100L in
  let t = Art.insert t ["lib"; "test.ml"] entry in
  match Art.find_opt t ["lib"; "test.ml"] with
  | Some e -> check int64 "size match" 100L e.size
  | None -> fail "Entry not found"

let test_art_remove () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["lib"; "test.ml"] (mk "test.ml" 100L) in
  let t = Art.remove t ["lib"; "test.ml"] in
  check bool "removed" true (Option.is_none (Art.find_opt t ["lib"; "test.ml"]));
  check int "count after remove" 0 (Art.count_nodes t)

let test_art_multiple () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"; "b"; "c"] (mk "c" 1L) in
  let t = Art.insert t ["a"; "b"; "d"] (mk "d" 2L) in
  let t = Art.insert t ["a"; "e"] (mk "e" 3L) in
  check bool "find abc" true (Option.is_some (Art.find_opt t ["a"; "b"; "c"]));
  check bool "find abd" true (Option.is_some (Art.find_opt t ["a"; "b"; "d"]));
  check bool "find ae" true (Option.is_some (Art.find_opt t ["a"; "e"]));
  check int "count" 3 (Art.count_nodes t)

let test_art_transition () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"] (mk "a" 1L) in
  let t = Art.insert t ["b"] (mk "b" 1L) in
  let t = Art.insert t ["c"] (mk "c" 1L) in
  let t = Art.insert t ["d"] (mk "d" 1L) in
  let t = Art.insert t ["e"] (mk "e" 1L) in
  let t = Art.insert t ["f"] (mk "f" 1L) in
  check bool "find a" true (Option.is_some (Art.find_opt t ["a"]));
  check bool "find f" true (Option.is_some (Art.find_opt t ["f"]));
  check int "count" 6 (Art.count_nodes t)

(* === Patricia Trie prefix compression tests === *)

let test_prefix_compression () =
  (* Deep path with no branching should get compressed *)
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"; "b"; "c"; "d"; "e"] (mk "e" 1L) in
  check bool "find deep" true (Option.is_some (Art.find_opt t ["a"; "b"; "c"; "d"; "e"]));
  check bool "intermediate absent" true (Option.is_none (Art.find_opt t ["a"; "b"; "c"]));
  check int "count" 1 (Art.count_nodes t)

let test_prefix_split () =
  (* Insert along a compressed path should split the prefix *)
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"; "b"; "c"; "d"] (mk "d" 1L) in
  let t = Art.insert t ["a"; "b"; "x"; "y"] (mk "y" 2L) in
  check bool "find abcd" true (Option.is_some (Art.find_opt t ["a"; "b"; "c"; "d"]));
  check bool "find abxy" true (Option.is_some (Art.find_opt t ["a"; "b"; "x"; "y"]));
  check int "count" 2 (Art.count_nodes t)

let test_prefix_split_at_value () =
  (* Insert a value at a point that's inside an existing compressed prefix *)
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"; "b"; "c"; "d"] (mk "d" 1L) in
  let t = Art.insert t ["a"; "b"] (mk "b" 2L) in
  check bool "find abcd" true (Option.is_some (Art.find_opt t ["a"; "b"; "c"; "d"]));
  check bool "find ab" true (Option.is_some (Art.find_opt t ["a"; "b"]));
  check int "count" 2 (Art.count_nodes t)

let test_prefix_recompress_on_remove () =
  (* After removing a branch, remaining single-child path should recompress *)
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"; "b"; "c"] (mk "c" 1L) in
  let t = Art.insert t ["a"; "b"; "d"] (mk "d" 2L) in
  let t = Art.remove t ["a"; "b"; "d"] in
  check bool "find abc" true (Option.is_some (Art.find_opt t ["a"; "b"; "c"]));
  check bool "abd removed" true (Option.is_none (Art.find_opt t ["a"; "b"; "d"]));
  check int "count" 1 (Art.count_nodes t)

(* === Bulk operations === *)

let test_bulk_insert_find () =
  let t : test_entry Art.t = Art.empty in
  let n = 1000 in
  let t = ref t in
  for i = 0 to n - 1 do
    let key = ["dir"; Printf.sprintf "file_%04d.ml" i] in
    t := Art.insert !t key (mk (Printf.sprintf "file_%04d.ml" i) (Int64.of_int i))
  done;
  check int "count" n (Art.count_nodes !t);
  for i = 0 to n - 1 do
    let key = ["dir"; Printf.sprintf "file_%04d.ml" i] in
    check bool (Printf.sprintf "find %d" i) true (Option.is_some (Art.find_opt !t key))
  done

let test_bulk_remove () =
  let t : test_entry Art.t = Art.empty in
  let n = 100 in
  let t = ref t in
  for i = 0 to n - 1 do
    t := Art.insert !t ["d"; string_of_int i] (mk (string_of_int i) (Int64.of_int i))
  done;
  check int "count before" n (Art.count_nodes !t);
  for i = 0 to n - 1 do
    t := Art.remove !t ["d"; string_of_int i]
  done;
  check int "count after" 0 (Art.count_nodes !t)

(* === fold_path === *)

let test_fold_path () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["src"; "lib"; "main.ml"] (mk "main.ml" 100L) in
  let t = Art.insert t ["src"; "bin"; "cli.ml"] (mk "cli.ml" 200L) in
  let paths = Art.fold_path (fun acc p _ -> p :: acc) [] t in
  check int "2 paths" 2 (List.length paths);
  check bool "has main" true (List.exists (fun p -> String.length p > 0 && Filename.basename p = "main.ml") paths);
  check bool "has cli" true (List.exists (fun p -> String.length p > 0 && Filename.basename p = "cli.ml") paths)

(* === fold_with_prune === *)

let test_fold_with_prune () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["keep"; "a.ml"] (mk "a.ml" 1L) in
  let t = Art.insert t ["skip"; "b.ml"] (mk "b.ml" 2L) in
  let t = Art.insert t ["keep"; "c.ml"] (mk "c.ml" 3L) in
  let can_prune path = 
    try String.sub path 0 4 = "skip" with _ -> false
  in
  let entries = Art.fold_with_prune can_prune (fun acc _ v -> v :: acc) [] t in
  check int "pruned to 2" 2 (List.length entries);
  check bool "no skip entries" true
    (List.for_all (fun e -> e.name <> "b.ml") entries)

(* === UTF-8 paths === *)

let test_utf8_paths () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["ドキュメント"; "レポート.pdf"] (mk "レポート.pdf" 50L) in
  let t = Art.insert t ["📁"; "🎉.txt"] (mk "🎉.txt" 10L) in
  check bool "find japanese" true (Option.is_some (Art.find_opt t ["ドキュメント"; "レポート.pdf"]));
  check bool "find emoji" true (Option.is_some (Art.find_opt t ["📁"; "🎉.txt"]));
  check int "count" 2 (Art.count_nodes t)

(* === Edge cases === *)

let test_empty_path () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t [] (mk "root" 0L) in
  check bool "find root" true (Option.is_some (Art.find_opt t []));
  let t = Art.remove t [] in
  check bool "root removed" true (Option.is_none (Art.find_opt t []))

let test_single_segment () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["only"] (mk "only" 1L) in
  check bool "find single" true (Option.is_some (Art.find_opt t ["only"]));
  check int "count" 1 (Art.count_nodes t)

let test_overwrite () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"; "b"] (mk "old" 1L) in
  let t = Art.insert t ["a"; "b"] (mk "new" 2L) in
  (match Art.find_opt t ["a"; "b"] with
   | Some e -> check string "overwritten" "new" e.name
   | None -> fail "Entry not found after overwrite");
  check int "count still 1" 1 (Art.count_nodes t)

let test_find_nonexistent () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"; "b"] (mk "b" 1L) in
  check bool "partial path" true (Option.is_none (Art.find_opt t ["a"]));
  check bool "wrong path" true (Option.is_none (Art.find_opt t ["x"; "y"]));
  check bool "longer path" true (Option.is_none (Art.find_opt t ["a"; "b"; "c"]))

let test_remove_nonexistent () =
  let t : test_entry Art.t = Art.empty in
  let t = Art.insert t ["a"; "b"] (mk "b" 1L) in
  let t' = Art.remove t ["x"; "y"] in
  check int "unchanged count" 1 (Art.count_nodes t');
  check bool "original still there" true (Option.is_some (Art.find_opt t' ["a"; "b"]))

let test_deep_path () =
  let t : test_entry Art.t = Art.empty in
  let depth = 50 in
  let key = List.init depth (fun i -> Printf.sprintf "d%d" i) in
  let t = Art.insert t key (mk "deep" 1L) in
  check bool "find deep" true (Option.is_some (Art.find_opt t key));
  check int "count" 1 (Art.count_nodes t)

let suite = [
  "ART Basic", [
    test_case "Empty tree" `Quick test_art_empty;
    test_case "Insert and find" `Quick test_art_insert_find;
    test_case "Remove" `Quick test_art_remove;
    test_case "Multiple entries" `Quick test_art_multiple;
    test_case "Small to Large transition" `Quick test_art_transition;
  ];
  "ART Prefix Compression", [
    test_case "Compression" `Quick test_prefix_compression;
    test_case "Split on divergence" `Quick test_prefix_split;
    test_case "Split at value point" `Quick test_prefix_split_at_value;
    test_case "Recompress on remove" `Quick test_prefix_recompress_on_remove;
  ];
  "ART Bulk", [
    test_case "1000 inserts" `Quick test_bulk_insert_find;
    test_case "100 inserts then remove all" `Quick test_bulk_remove;
  ];
  "ART Fold", [
    test_case "fold_path" `Quick test_fold_path;
    test_case "fold_with_prune" `Quick test_fold_with_prune;
  ];
  "ART Edge Cases", [
    test_case "UTF-8 paths" `Quick test_utf8_paths;
    test_case "Empty path" `Quick test_empty_path;
    test_case "Single segment" `Quick test_single_segment;
    test_case "Overwrite" `Quick test_overwrite;
    test_case "Find nonexistent" `Quick test_find_nonexistent;
    test_case "Remove nonexistent" `Quick test_remove_nonexistent;
    test_case "50-level deep path" `Quick test_deep_path;
  ];
]

let () = run "ART" suite
