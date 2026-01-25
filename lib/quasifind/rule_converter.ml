(* Module for fetching and converting external security lists into rules *)

(* Helper to fetch content from URL *)
let fetch_url url =
  let temp_file = Filename.temp_file "quasifind_fetch" ".txt" in
  let cmd = Printf.sprintf "curl -sL %s -o %s" (Filename.quote url) (Filename.quote temp_file) in
  match Unix.system cmd with
  | Unix.WEXITED 0 ->
      let ic = open_in temp_file in
      let rec read_lines acc =
        try read_lines (input_line ic :: acc)
        with End_of_file -> 
          close_in ic;
          List.rev acc
      in
      let lines = read_lines [] in
      Sys.remove temp_file;
      Ok lines
  | _ -> 
      Error (Printf.sprintf "Failed to fetch URL: %s" url)

(* Convert a list of strings (extensions/patterns) into a regex alternation string *)
let list_to_regex_alt items =
  items
  |> List.map String.trim
  |> List.filter (fun s -> s <> "" && not (String.starts_with ~prefix:"#" s)) (* Filter empty and comments *)
  |> List.map Re.Pcre.quote (* Escape special chars *)
  |> String.concat "|"

(* Sources definition *)
type source_type = Extensions | Filenames

type source_def = {
  name : string;
  url : string;
  kind : source_type;
}

(* Pre-defined trustworthy sources (Concepts/Demos) *)
(* Note: In a real scenario, these would be robust URLs from SecLists or similar *)
let sources = [
  {
    name = "Generated: Suspicious WebShell Attributes";
    (* Using a raw gist or similar for demo. Here we simulate the content if URL fails or we can use a simpler approach for the demo. *)
    url = "https://raw.githubusercontent.com/payloadbox/command-injection-payload-list/master/README.md"; (* Just a placeholder for demo structure *)
    kind = Extensions; (* We will treat this as a generic list for demo purposes *)
  }
]

(* The converter function *)
let update_from_source () =
  Printf.printf "Fetching external security lists...\n%!";
  
  (* 1. Fetch Suspicious Extensions (Simulated for Demo Stability) *)
  (* Let's simulate fetching a list of extensions often used for webshells *)
  let webshell_exts = ["php"; "phtml"; "php5"; "jsp"; "asp"; "aspx"; "cgi"; "pl"] in
  (* In real usage: fetch_url "..." |> to list *)
  
  let rule_webshell_ext = {
    Rule_loader.name = "Generated: WebShell Extensions";
    expr = Printf.sprintf "name =~ /\\.(%s)$/" (list_to_regex_alt webshell_exts)
  } in

  (* 2. Fetch Suspicious Filenames (Simulated) *)
  let susp_files = ["id_rsa"; ".aws/credentials"; "shadow"; "passwd"] in
  
  let rule_sensitive_files = {
    Rule_loader.name = "Generated: Sensitive Files";
    expr = Printf.sprintf "name =~ /^(%s)$/" (list_to_regex_alt susp_files)
  } in

  (* Combine with existing rules *)
  let current_rules = match Rule_loader.load_rules () with Some rs -> rs.rules | None -> [] in
  
  (* Remove old generated rules to avoid duplication/stale data *)
  let kept_rules = List.filter (fun (r : Rule_loader.rule_def) -> not (String.starts_with ~prefix:"Generated:" r.name)) current_rules in
  
  let new_rules = kept_rules @ [rule_webshell_ext; rule_sensitive_files] in
  
  let new_rule_set = { Rule_loader.version = "1.1"; rules = new_rules } in
  Rule_loader.save_rules new_rule_set;
  
  Printf.printf "Successfully generated and saved %d rules.\n%!" (List.length new_rules)
