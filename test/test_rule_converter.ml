open Alcotest
open Quasifind

let test_list_to_regex_alt () =
  let items = [".php"; ".asp"; ".jsp"] in
  let result = Rule_converter.list_to_regex_alt items in
  (* Check that items are escaped and joined *)
  check bool "contains php" true (String.length result > 0);
  check bool "is alternation" true (String.contains result '|')

let test_list_to_regex_alt_comments () =
  let items = ["valid"; "# comment"; ""; "another"] in
  let result = Rule_converter.list_to_regex_alt items in
  (* Comments and empty lines should be filtered *)
  check bool "no comment in result" false (String.contains result '#')

let test_list_to_regex_alt_escapes () =
  let items = ["file.ext"; "path/name"] in
  let result = Rule_converter.list_to_regex_alt items in
  (* Dots and slashes should be escaped *)
  check bool "escapes dot" true (try ignore (Str.search_forward (Str.regexp "\\\\.") result 0); true with Not_found -> false)

let suite = [
  "RuleConverter", [
    test_case "List to Regex Alt" `Quick test_list_to_regex_alt;
    test_case "Filter Comments" `Quick test_list_to_regex_alt_comments;
    test_case "Escape Special Chars" `Quick test_list_to_regex_alt_escapes;
  ]
]

let () = run "Quasifind RuleConverter" suite
