open Alcotest
open Quasifind

let test_truncate () =
  (* Test truncate function from TUI module - note: min length is 10 *)
  check string "short string" "hello" (Interactive.TUI.truncate "hello" 20);
  check string "exact length" "hello" (Interactive.TUI.truncate "hello" 5);
  (* With min length 10, truncating "hello world" to 8 still uses 10, so "hello ..." *)
  check string "truncated to min" "hello w..." (Interactive.TUI.truncate "hello world" 8);
  check string "truncated longer" "hello w..." (Interactive.TUI.truncate "hello world again" 10)

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
  (* Just verify is_atty doesn't crash when called *)
  let _ = Interactive.is_atty () in
  ()

let suite = [
  "Interactive.TUI", [
    test_case "Truncate" `Quick test_truncate;
    test_case "Shell Quote" `Quick test_shell_quote;
    test_case "Escape Sequences" `Quick test_escape_sequences;
    test_case "is_atty exists" `Quick test_is_atty_function_exists;
  ]
]

let () = run "Quasifind Interactive" suite
