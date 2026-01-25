open Alcotest
open Quasifind

let test_parse_valid () =
  let lines = [
    "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NLINK NODE NAME";
    "bash 123 root 1u REG 1,1 0 0 1234 /tmp/deleted_file";
    "chrome 456 user 2u REG 1,1 100 0 5678 /home/user/Downloads/incomplete.crdownload";
  ] in
  let result = Ghost.parse_lsof_output lines "/" in
  check (list string) "parse valid lines" ["/tmp/deleted_file"; "/home/user/Downloads/incomplete.crdownload"] result

let test_filter_root () =
  let lines = [
    "bash 123 root 1u REG 1,1 0 0 1234 /tmp/deleted_file";
    "chrome 456 user 2u REG 1,1 100 0 5678 /home/user/Downloads/incomplete.crdownload";
  ] in
  (* Filter by /home *)
  let result = Ghost.parse_lsof_output lines "/home" in
  check (list string) "filter by root" ["/home/user/Downloads/incomplete.crdownload"] result

let test_parse_garbage () =
  let lines = [
    "garbage line without sufficient columns";
    "just_one_word";
    "";
    "COMMAND PID ...";
  ] in
  let result = Ghost.parse_lsof_output lines "/" in
  check (list string) "handle garbage gracefully" [] result

let suite = [
  "Ghost", [
    test_case "Parse Valid" `Quick test_parse_valid;
    test_case "Filter Root" `Quick test_filter_root;
    test_case "Garbage Input" `Quick test_parse_garbage;
  ]
]

let () = run "Quasifind Ghost" suite
