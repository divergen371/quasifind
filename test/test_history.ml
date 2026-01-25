open Alcotest
open Quasifind

let test_entry_json_roundtrip () =
  let entry : History.entry = {
    timestamp = 1234567890.0;
    command = ["quasifind"; "."; "name =~ /test/"];
    results_count = 10;
    results_sample = ["/tmp/a"; "/tmp/b"];
    full_results_path = Some "/data/results/123.txt";
  } in
  let json = History.entry_to_json entry in
  match History.entry_of_json json with
  | Some e ->
      check (float 0.001) "timestamp" 1234567890.0 e.timestamp;
      check int "command length" 3 (List.length e.command);
      check int "results_count" 10 e.results_count;
      check int "sample length" 2 (List.length e.results_sample);
      check bool "full_results_path" true (Option.is_some e.full_results_path)
  | None -> fail "Failed to parse history entry JSON"

let test_entry_minimal () =
  let entry : History.entry = {
    timestamp = 0.0;
    command = ["quasifind"];
    results_count = 0;
    results_sample = [];
    full_results_path = None;
  } in
  let json = History.entry_to_json entry in
  match History.entry_of_json json with
  | Some e ->
      check int "results_count" 0 e.results_count;
      check bool "full_results_path is None" true (Option.is_none e.full_results_path)
  | None -> fail "Failed to parse minimal history entry"

let test_take () =
  check (list int) "take 3 from 5" [1; 2; 3] (History.take 3 [1; 2; 3; 4; 5]);
  check (list int) "take 10 from 3" [1; 2; 3] (History.take 10 [1; 2; 3]);
  check (list int) "take 0" [] (History.take 0 [1; 2; 3])

let suite = [
  "History", [
    test_case "Entry JSON Roundtrip" `Quick test_entry_json_roundtrip;
    test_case "Entry Minimal" `Quick test_entry_minimal;
    test_case "Take Function" `Quick test_take;
  ]
]

let () = run "Quasifind History" suite
