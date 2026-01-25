open Yojson.Safe

type fuzzy_finder = Auto | Fzf | Builtin [@@deriving show, eq]

type t = {
  fuzzy_finder : fuzzy_finder;
  ignore : string list;
  email : string option;
  webhook_url : string option;
  slack_url : string option;
} [@@deriving show, eq]

let default = {
  fuzzy_finder = Auto;
  ignore = ["_build"; ".git"; "node_modules"; ".DS_Store"];
  email = None;
  webhook_url = None;
  slack_url = None;
}

let fuzzy_finder_of_string = function
  | "auto" -> Auto
  | "fzf" -> Fzf
  | "builtin" -> Builtin
  | _ -> Auto (* default callback *)

let t_of_json json =
  let open Util in
  let fuzzy_finder = 
    try member "fuzzy_finder" json |> to_string |> fuzzy_finder_of_string
    with _ -> default.fuzzy_finder 
  in
  let ignore =
    try member "ignore" json |> to_list |> List.map to_string
    with _ -> default.ignore
  in
  let email = 
    try to_option to_string (member "email" json)
    with _ -> None
  in
  let webhook_url = 
    try to_option to_string (member "webhook_url" json)
    with _ -> None
  in
  let slack_url = 
    try to_option to_string (member "slack_url" json)
    with _ -> None
  in
  { fuzzy_finder; ignore; email; webhook_url; slack_url }

let get_config_dir () =
  let home = Sys.getenv "HOME" in
  match Sys.getenv_opt "XDG_CONFIG_HOME" with
  | Some path -> Filename.concat path "quasifind"
  | None -> Filename.concat (Filename.concat home ".config") "quasifind"

let get_config_path () =
  let dir = get_config_dir () in
  if not (Sys.file_exists dir) then 
    (try Unix.mkdir dir 0o755 with _ -> ());
  Filename.concat dir "config.json"

let t_to_json t =
  let open Util in
  `Assoc [
    ("fuzzy_finder", `String (match t.fuzzy_finder with Auto -> "auto" | Fzf -> "fzf" | Builtin -> "builtin"));
    ("ignore", `List (List.map (fun s -> `String s) t.ignore));
    ("email", match t.email with Some s -> `String s | None -> `Null);
    ("webhook_url", match t.webhook_url with Some s -> `String s | None -> `Null);
    ("slack_url", match t.slack_url with Some s -> `String s | None -> `Null);
  ]

let save_default path =
  let json = t_to_json default in
  try
    Yojson.Safe.to_file path json;
    Printf.printf "Created default config at %s\n%!" path
  with e ->
    Printf.eprintf "Warning: Failed to ensure default config at %s: %s\n" path (Printexc.to_string e)

let load () =
  let path = get_config_path () in
  if not (Sys.file_exists path) then (
    save_default path;
    default
  ) else
    try
      let json = Yojson.Safe.from_file path in
      t_of_json json
    with e ->
      Printf.eprintf "Warning: Failed to parse config file %s: %s\n" path (Printexc.to_string e);
      default
