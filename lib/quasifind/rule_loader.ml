(* Module for loading and saving external detection rules *)

type rule_def = {
  name : string;
  expr : string;
}

type rule_set = {
  version : string;
  rules : rule_def list;
}

let default_rule_set = {
  version = "1.0";
  rules = [
    { name = "Sample: PHP WebShell"; expr = "name =~ /\\.php$/ && content =~ /eval\\\\(base64_|shell_exec\\\\(/" };
    { name = "Sample: Reverse Shell"; expr = "content =~ /bash -i >& \\/dev\\/(tcp|udp)/" };
  ]
}

(* Using minimal JSON handling to avoid complex dependencies if possible, 
   but since Yojson is available, we use it for robustness *)

let rule_to_json r =
  `Assoc [
    ("name", `String r.name);
    ("expr", `String r.expr)
  ]

let rule_of_json = function
  | `Assoc assoc ->
      let name = 
        match List.assoc_opt "name" assoc with
        | Some (`String s) -> s
        | _ -> "Unknown Rule"
      in
      let expr = 
        match List.assoc_opt "expr" assoc with
        | Some (`String s) -> s
        | _ -> "false"
      in
      { name; expr }
  | _ -> { name = "Invalid"; expr = "false" }

let to_json rs =
  `Assoc [
    ("version", `String rs.version);
    ("rules", `List (List.map rule_to_json rs.rules))
  ]

let of_json = function
  | `Assoc assoc ->
      let version = 
        match List.assoc_opt "version" assoc with
        | Some (`String s) -> s
        | _ -> "1.0"
      in
      let rules = 
        match List.assoc_opt "rules" assoc with
        | Some (`List l) -> List.map rule_of_json l
        | _ -> []
      in
      { version; rules }
  | _ -> { version = "1.0"; rules = [] }

let get_config_dir () =
  let home = Sys.getenv "HOME" in
  let xdg = try Sys.getenv "XDG_CONFIG_HOME" with Not_found -> Filename.concat home ".config" in
  let dir = Filename.concat xdg "quasifind" in
  if not (Sys.file_exists dir) then Unix.mkdir dir 0o755;
  dir

let rules_file () =
  Filename.concat (get_config_dir ()) "rules.json"

let save_rules rs =
  let json = to_json rs in
  let file = rules_file () in
  let oc = open_out file in
  Yojson.Basic.to_channel oc json;
  Yojson.Basic.to_channel oc json;
  close_out oc

let reset_to_default () =
  let file = rules_file () in
  if Sys.file_exists file then Sys.remove file;
  save_rules default_rule_set;
  Printf.printf "Reset rules to default at %s\n%!" file

let load_rules () =
  let file = rules_file () in
  if not (Sys.file_exists file) then (
    save_rules default_rule_set;
    Printf.printf "Created default rules at %s\n%!" file;
    Some default_rule_set
  ) else
    try
      let json = Yojson.Basic.from_file file in
      Some (of_json json)
    with _ -> None
