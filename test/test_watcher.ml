open Alcotest
open Quasifind

(* Watcher module tests - testing pure functions *)

let test_string_of_event () =
  check string "New" "NEW" (Watcher.string_of_event Watcher.New);
  check string "Modified" "MODIFIED" (Watcher.string_of_event Watcher.Modified);
  check string "Deleted" "DELETED" (Watcher.string_of_event Watcher.Deleted)

let test_event_type_variants () =
  (* Test that all event types can be created and converted *)
  let events = [Watcher.New; Watcher.Modified; Watcher.Deleted] in
  let strings = List.map Watcher.string_of_event events in
  check int "event count" 3 (List.length strings);
  check bool "all different" true (
    let unique = List.sort_uniq String.compare strings in
    List.length unique = 3
  )

let test_log_event_none_channel () =
  (* Verify log_event with None doesn't crash *)
  Watcher.log_event ?log_channel:None Watcher.New "/test/path";
  ()

let test_send_webhook_none () =
  (* Verify send_webhook with None doesn't crash or do anything *)
  Watcher.send_webhook ?webhook_url:None Watcher.New "/test/path";
  ()

let test_send_email_none () =
  (* Verify send_email with None doesn't crash *)
  Watcher.send_email ?email_addr:None Watcher.New "/test/path";
  ()

let test_send_slack_none () =
  (* Verify send_slack with None doesn't crash *)
  Watcher.send_slack ?slack_url:None Watcher.New "/test/path";
  ()

let suite = [
  "Watcher", [
    test_case "String of Event" `Quick test_string_of_event;
    test_case "Event Type Variants" `Quick test_event_type_variants;
    test_case "Log Event None" `Quick test_log_event_none_channel;
    test_case "Send Webhook None" `Quick test_send_webhook_none;
    test_case "Send Email None" `Quick test_send_email_none;
    test_case "Send Slack None" `Quick test_send_slack_none;
  ]
]

let () = run "Quasifind Watcher" suite
