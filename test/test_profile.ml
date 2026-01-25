open Alcotest
open Quasifind

let test_json_roundtrip () =
  let profile : Profile.t = {
    root_dir = Some "/home/user";
    expr = "name =~ /.*\\.ml$/";
    max_depth = Some 5;
    follow_symlinks = true;
    include_hidden = false;
    exclude = ["_build"; "node_modules"];
  } in
  let json = Profile.to_json profile in
  match Profile.of_json json with
  | Some p -> 
      check string "root_dir" "/home/user" (Option.get p.root_dir);
      check string "expr" "name =~ /.*\\.ml$/" p.expr;
      check int "max_depth" 5 (Option.get p.max_depth);
      check bool "follow_symlinks" true p.follow_symlinks;
      check bool "include_hidden" false p.include_hidden;
      check int "exclude count" 2 (List.length p.exclude)
  | None -> fail "Failed to parse profile JSON"

let test_json_minimal () =
  let profile : Profile.t = {
    root_dir = None;
    expr = "true";
    max_depth = None;
    follow_symlinks = false;
    include_hidden = false;
    exclude = [];
  } in
  let json = Profile.to_json profile in
  match Profile.of_json json with
  | Some p -> 
      check bool "root_dir is None" true (Option.is_none p.root_dir);
      check string "expr" "true" p.expr
  | None -> fail "Failed to parse minimal profile"

let suite = [
  "Profile", [
    test_case "JSON Roundtrip" `Quick test_json_roundtrip;
    test_case "JSON Minimal" `Quick test_json_minimal;
  ]
]

let () = run "Quasifind Profile" suite
