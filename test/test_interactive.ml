open Alcotest
open Quasifind

let test_truncate () =
  (* Test truncate function from TUI module - note: min length is 10 *)
  check string "short string" "hello" (Interactive.TUI.truncate "hello" 20);
  check string "exact length" "hello" (Interactive.TUI.truncate "hello" 5);
  (* With min length 10, truncating "hello world" to 8 still uses 10, so "hello ..." *)
  check string "truncated to min" "hello w..." (Interactive.TUI.truncate "hello world" 8);
  check string "truncated longer" "hello w..." (Interactive.TUI.truncate "hello world again" 10);
  (* UTF-8 Tests: 日本語 (3 bytes per char) *)
  (* "こんにちは" (15 bytes) truncated to 10 bytes should not break in the middle of 'に' *)
  (* "こ" (3b), "ん" (3b), "に" (3b) -> total 9 bytes. 10th byte would be start of 'ち'. *)
  (* If truncated to 10 bytes (including "..."): len-3 = 7. 
     "こ"(3), "ん"(3), "に"(1st byte) -> should revert to 6 bytes "こん" *)
  check string "utf8 truncate" "こん..." (Interactive.TUI.truncate "こんにちは" 10)

let test_sanitize () =
  check string "printable" "hello" (Interactive.TUI.sanitize "hello");
  check string "newline" "hello world" (Interactive.TUI.sanitize "hello\nworld");
  check string "control" "^A^B^C" (Interactive.TUI.sanitize "\001\002\003");
  check string "utf8 preserve" "こんにちは" (Interactive.TUI.sanitize "こんにちは");
  check string "mixed" "こん^Aにち" (Interactive.TUI.sanitize "こん\001にち")

let test_shell_quote () =
  (* Test shell_quote escapes single quotes correctly *)
  check string "simple" "'hello'" (Interactive.TUI.shell_quote "hello");
  check string "with space" "'hello world'" (Interactive.TUI.shell_quote "hello world");
  check string "with quote" "''\\''escaped'\\'''" (Interactive.TUI.shell_quote "'escaped'")

let test_escape_sequences () =
  (* Test CSI escape sequences *)
  check string "move_up 0" "" (Interactive.TUI.move_up 0);
  check string "move_up 1" "\027[1A" (Interactive.TUI.move_up 1);
  check string "move_up 5" "\027[5A" (Interactive.TUI.move_up 5);
  check string "clear_line" "\027[2K\r" Interactive.TUI.clear_line;
  check string "hide_cursor" "\027[?25l" Interactive.TUI.hide_cursor;
  check string "show_cursor" "\027[?25h" Interactive.TUI.show_cursor

let test_is_atty_function_exists () =
  (* SMOKE TEST: Just verify is_atty doesn't crash when called - result depends on environment *)
  let _ = Interactive.is_atty () in
  ()

let test_fuzzy_rank () =
  let candidates = [
    "./lib/quasifind/fsevents_stubs.c";
    "./lib/quasifind/stealth_stubs.c";
    "./test_file_phase2_live_update.txt";
    "./lib/quasifind/dirent_stubs.c";
    "./lib/quasifind/search_stubs.c";
    "./docs/mli_interfaces_and_odoc/implementation_plan.md";
    "./lib/quasifind/rule_converter.ml";
    "./lib/quasifind/rule_converter.mli";
    "./docs/interactive_search_feature";
    "./lib/quasifind/fuzzy_matcher.ml";
    "./lib/quasifind/ast.ml";
  ] in
  let results = Fuzzy_matcher.rank ~query:"ast" ~candidates in
  Printf.printf "\n--- RANK RESULTS for 'ast' ---\n";
  List.iteri (fun i s ->
    let score =
      match Fuzzy_matcher.match_score ~query:"ast" ~candidate:s with
      | Some s -> string_of_int s | None -> "none"
    in
    Printf.printf "%d (score %s): %s\n" (i+1) score s
  ) results;
  check string "first ranked is ast.ml" "./lib/quasifind/ast.ml" (List.hd results)

let suite = [
  "Interactive.TUI", [
    test_case "Truncate" `Quick test_truncate;
    test_case "Shell Quote" `Quick test_shell_quote;
    test_case "Escape Sequences" `Quick test_escape_sequences;
    test_case "is_atty exists" `Quick test_is_atty_function_exists;
    test_case "Fuzzy Matcher Rank" `Quick test_fuzzy_rank;
    test_case "Sanitize" `Quick test_sanitize;
  ]
]

let () = run "Quasifind Interactive" suite
