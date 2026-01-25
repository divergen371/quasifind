open Alcotest
open Quasifind

(* Stealth module has mostly system-dependent functions, but we can test:
   - default_fake_name constant
   - is_available function (may fail on some systems but shouldn't crash)
*)

let test_default_fake_name () =
  check string "default name" "[kworker/0:0]" Stealth.default_fake_name

let test_is_available_no_crash () =
  (* Just verify it doesn't crash - actual result depends on system *)
  let _ = Stealth.is_available () in
  ()

let test_clear_argv_no_crash () =
  (* Verify clear_argv doesn't crash *)
  Stealth.clear_argv ()

let suite = [
  "Stealth", [
    test_case "Default Fake Name" `Quick test_default_fake_name;
    test_case "is_available no crash" `Quick test_is_available_no_crash;
    test_case "clear_argv no crash" `Quick test_clear_argv_no_crash;
  ]
]

let () = run "Quasifind Stealth" suite
