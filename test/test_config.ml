open Alcotest
open Quasifind

let test_config_json_roundtrip () =
  let config : Config.t = {
    fuzzy_finder = Config.Fzf;
    ignore = ["_build"; ".git"];
    email = Some "test@example.com";
    webhook_url = Some "https://example.com/hook";
    slack_url = None;
    heartbeat_url = Some "http://localhost:8080";
    heartbeat_interval = 30;
    rule_sources = [];
  } in
  let json = Config.t_to_json config in
  let parsed = Config.t_of_json json in
  check bool "fuzzy_finder" true (Config.equal_fuzzy_finder Config.Fzf parsed.fuzzy_finder);
  check int "ignore count" 2 (List.length parsed.ignore);
  check bool "email" true (Option.is_some parsed.email);
  check bool "webhook_url" true (Option.is_some parsed.webhook_url);
  check bool "slack_url" true (Option.is_none parsed.slack_url)

let test_fuzzy_finder_of_string () =
  check bool "auto" true (Config.equal_fuzzy_finder Config.Auto (Config.fuzzy_finder_of_string "auto"));
  check bool "fzf" true (Config.equal_fuzzy_finder Config.Fzf (Config.fuzzy_finder_of_string "fzf"));
  check bool "builtin" true (Config.equal_fuzzy_finder Config.Builtin (Config.fuzzy_finder_of_string "builtin"));
  check bool "unknown -> auto" true (Config.equal_fuzzy_finder Config.Auto (Config.fuzzy_finder_of_string "unknown"))

let test_default_config () =
  let default = Config.default in
  check bool "ignore has _build" true (List.mem "_build" default.ignore);
  check bool "ignore has .git" true (List.mem ".git" default.ignore)

let suite = [
  "Config", [
    test_case "JSON Roundtrip" `Quick test_config_json_roundtrip;
    test_case "Fuzzy Finder Parsing" `Quick test_fuzzy_finder_of_string;
    test_case "Default Config" `Quick test_default_config;
  ]
]

let () = run "Quasifind Config" suite
