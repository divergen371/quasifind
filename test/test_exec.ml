open Alcotest
open Quasifind

let test_quote_path () =
  check string "simple" "'hello'" (Exec.quote_path "hello");
  check string "with space" "'hello world'" (Exec.quote_path "hello world");
  (* Single quote is escaped as: '\'' *)
  check string "with quote" "''\\''escaped'\\'''" (Exec.quote_path "'escaped'")

let test_has_placeholder () =
  check bool "has {}" true (Exec.has_placeholder "echo {}");
  check bool "no placeholder" false (Exec.has_placeholder "echo hello")

let test_replace_placeholder () =
  check string "replace {}" "echo 'file.txt'" (Exec.replace_placeholder "echo {}" "'file.txt'");
  check string "multiple {}" "cat 'a' 'a'" (Exec.replace_placeholder "cat {} {}" "'a'")

let test_prepare_command () =
  check string "with placeholder" "echo '/tmp/test.txt'" (Exec.prepare_command "echo {}" "/tmp/test.txt");
  check string "without placeholder" "ls '/tmp/file'" (Exec.prepare_command "ls" "/tmp/file")

let suite = [
  "Exec", [
    test_case "Quote Path" `Quick test_quote_path;
    test_case "Has Placeholder" `Quick test_has_placeholder;
    test_case "Replace Placeholder" `Quick test_replace_placeholder;
    test_case "Prepare Command" `Quick test_prepare_command;
  ]
]

let () = run "Quasifind Exec" suite
