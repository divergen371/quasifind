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

(* Obsolete internal source definitions - moved to Config *)

(* The converter function *)
let update_from_source () =
  let config = Config.load () in
  Printf.printf "Fetching external security lists (%d sources)...\n%!" (List.length config.rule_sources);
  
  let generated_rules = 
    List.fold_left (fun acc (source : Config.rule_source_def) ->
      Printf.printf "Fetching %s from %s...\n%!" source.name source.url;
      match fetch_url source.url with
      | Ok items ->
          (match source.kind with
           | Config.Extensions ->
               let rule = {
                 Rule_loader.name = source.name;
                 expr = Printf.sprintf "name =~ /\\.(%s)$/" (list_to_regex_alt items)
               } in
               rule :: acc
           | Config.Filenames ->
               let rule = {
                 Rule_loader.name = source.name;
                 expr = Printf.sprintf "name =~ /^(%s)$/" (list_to_regex_alt items)
               } in
               rule :: acc
          )
      | Error msg ->
          Printf.eprintf "Warning: %s. Using fallback/skipped.\n%!" msg;
          acc
    ) [] config.rule_sources
  in

  if generated_rules = [] then
    Printf.printf "No new rules generated (fetch failed or no sources).\n%!"
  else
    let current_rules = match Rule_loader.load_rules () with Some rs -> rs.rules | None -> [] in
    
    (* Remove old generated rules to avoid duplication/stale data *)
    let kept_rules = List.filter (fun (r : Rule_loader.rule_def) -> not (String.starts_with ~prefix:"Generated:" r.name)) current_rules in
    
    let new_rules = kept_rules @ generated_rules in
    
    let new_rule_set = { Rule_loader.version = "1.1"; rules = new_rules } in
    Rule_loader.save_rules new_rule_set;
    
    Printf.printf "Successfully generated and saved %d rules.\n%!" (List.length new_rules)
