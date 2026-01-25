open Yojson.Safe

type fuzzy_finder = Auto | Fzf | Builtin [@@deriving show, eq]

type t = {
  fuzzy_finder : fuzzy_finder;
  ignore : string list;
} [@@deriving show, eq]

let default = {
  fuzzy_finder = Auto;
  ignore = ["_build"; ".git"; "node_modules"; ".DS_Store"];
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
  { fuzzy_finder; ignore }

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

let load () =
  let path = get_config_path () in
  if not (Sys.file_exists path) then default
  else
    try
      let json = Yojson.Safe.from_file path in
      t_of_json json
    with e ->
      Printf.eprintf "Warning: Failed to parse config file %s: %s\n" path (Printexc.to_string e);
      default
