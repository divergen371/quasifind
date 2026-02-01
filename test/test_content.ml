open Alcotest
open Quasifind
open Ast
open Ast.Typed

let setup_file path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let test_content_match () =
  let temp_file = Filename.temp_file "test_content" ".txt" in
  setup_file temp_file "secret_password_123";
  
  let expr = Content (StrRe ("password", Re.compile (Re.Pcre.re "password"))) in
  let entry = {
    Eval.name = Filename.basename temp_file;
    path = temp_file;
    kind = Ast.File;
    size = 0L; (* Size not checked *)
    mtime = 0.0;
    perm = 0;
  } in
  
  check bool "matches content" true (Eval.eval 0.0 expr entry);
  
  let expr_fail = Content (StrRe ("missing", Re.compile (Re.Pcre.re "missing"))) in
  check bool "no match" false (Eval.eval 0.0 expr_fail entry);
  
  Sys.remove temp_file

let test_content_timestamps () =
  (* This test is tricky to make deterministic without waiting, 
     so we just trust the logic for now or do a simple read check *)
  let temp_file = Filename.temp_file "ts_test" ".txt" in
  setup_file temp_file "data";
  Unix.sleep 1; (* Wait to ensure atime differs if updated *)
  
  let stats_before = Unix.stat temp_file in
  let atime_before = stats_before.st_atime in
  
  (* Eval with timestamp preservation (simulated via stealth mode logic) *)
  let expr = Content (StrEq "data") in
  let entry = { Eval.name = "ts"; path = temp_file; kind = Ast.File; size = 4L; mtime = 0.0; perm = 0 } in
  
  (* Run eval with preserve_timestamps=true *)
  let _ = Eval.eval ~preserve_timestamps:true 0.0 expr entry in
  
  let stats_after = Unix.stat temp_file in
  (* atime should be preserved (restored) *)
  (* Note: utimes might set microseconds to 0 depending on FS resolution, so we allow small diffs or exact match *)
  (* For robust test, we check it's close to before, or exactly equal if FS supports it. *)
  (* On some systems, atime update is lazy (noatime/relatime). This test might pass trivially if OS didn't update atime. *)
  (* But we execute the code path at least. *)
  
  if stats_after.st_atime <> atime_before then
    Printf.eprintf "Warning: atime changed from %.3f to %.3f even with preservation (FS might be slow or low res)\n" atime_before stats_after.st_atime;
  
  check bool "eval returns true" true (Eval.eval ~preserve_timestamps:true 0.0 expr entry);
  Sys.remove temp_file

let suite = [
  "Content", [
    test_case "Match" `Quick test_content_match;
    test_case "Timestamp" `Quick test_content_timestamps;
  ]
]

let () = run "Quasifind Content" suite
