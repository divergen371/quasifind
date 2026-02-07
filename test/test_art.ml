(* Tests for ART (Adaptive Radix Tree) module *)
open Alcotest
open Quasifind

(* Define a test entry type *)
type test_entry = { size : int64; name : string }

(* Test ART empty *)
let test_art_empty () =
  let t : test_entry Art.t = Art.empty in
  check bool "empty has no value" true (Option.is_none t.Art.value)

(* Test ART insert and find *)
let test_art_insert_find () =
  let t : test_entry Art.t = Art.empty in
  let entry = { size = 100L; name = "test.ml" } in
  let t = Art.insert t ["lib"; "test.ml"] entry in
  match Art.find_opt t ["lib"; "test.ml"] with
  | Some e -> check int64 "size match" 100L e.size
  | None -> fail "Entry not found"

(* Test ART remove *)
let test_art_remove () =
  let t : test_entry Art.t = Art.empty in
  let entry = { size = 100L; name = "test.ml" } in
  let t = Art.insert t ["lib"; "test.ml"] entry in
  let t = Art.remove t ["lib"; "test.ml"] in
  match Art.find_opt t ["lib"; "test.ml"] with
  | Some _ -> fail "Entry should be removed"
  | None -> ()

(* Test ART multiple entries *)
let test_art_multiple () =
  let t : test_entry Art.t = Art.empty in
  let mk_entry size = { size; name = "file" } in
  let t = Art.insert t ["a"; "b"; "c"] (mk_entry 1L) in
  let t = Art.insert t ["a"; "b"; "d"] (mk_entry 2L) in
  let t = Art.insert t ["a"; "e"] (mk_entry 3L) in
  (* All three should be findable *)
  check bool "find abc" true (Option.is_some (Art.find_opt t ["a"; "b"; "c"]));
  check bool "find abd" true (Option.is_some (Art.find_opt t ["a"; "b"; "d"]));
  check bool "find ae" true (Option.is_some (Art.find_opt t ["a"; "e"]))

(* Test Small to Large transition *)
let test_art_transition () =
  let t : test_entry Art.t = Art.empty in
  let mk_entry () = { size = 1L; name = "file" } in
  (* Insert more than 4 children to trigger Small -> Large transition *)
  let t = Art.insert t ["a"] (mk_entry ()) in
  let t = Art.insert t ["b"] (mk_entry ()) in
  let t = Art.insert t ["c"] (mk_entry ()) in
  let t = Art.insert t ["d"] (mk_entry ()) in
  let t = Art.insert t ["e"] (mk_entry ()) in (* This should trigger Large *)
  let t = Art.insert t ["f"] (mk_entry ()) in
  check bool "find a" true (Option.is_some (Art.find_opt t ["a"]));
  check bool "find f" true (Option.is_some (Art.find_opt t ["f"]))

let suite = [
  "ART", [
    test_case "Empty tree" `Quick test_art_empty;
    test_case "Insert and find" `Quick test_art_insert_find;
    test_case "Remove" `Quick test_art_remove;
    test_case "Multiple entries" `Quick test_art_multiple;
    test_case "Small to Large transition" `Quick test_art_transition;
  ];
]

let () = run "ART" suite
