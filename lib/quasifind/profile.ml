(* Profile module for saving and loading search profiles *)
open Yojson.Safe

type t = {
  root_dir : string option;
  expr : string;
  max_depth : int option;
  follow_symlinks : bool;
  include_hidden : bool;
  exclude : string list;
}

let to_json p =
  `Assoc [
    ("root_dir", match p.root_dir with Some s -> `String s | None -> `Null);
    ("expr", `String p.expr);
    ("max_depth", match p.max_depth with Some n -> `Int n | None -> `Null);
    ("follow_symlinks", `Bool p.follow_symlinks);
    ("include_hidden", `Bool p.include_hidden);
    ("exclude", `List (List.map (fun s -> `String s) p.exclude));
  ]

let of_json json : t option =
  let open Util in
  try
    let root_dir = match member "root_dir" json with `String s -> Some s | _ -> None in
    let expr = member "expr" json |> to_string in
    let max_depth = match member "max_depth" json with `Int n -> Some n | _ -> None in
    let follow_symlinks = member "follow_symlinks" json |> to_bool in
    let include_hidden = member "include_hidden" json |> to_bool in
    let exclude = 
      match member "exclude" json with
      | `List l -> List.filter_map (function `String s -> Some s | _ -> None) l
      | _ -> []
    in
    Some { root_dir; expr; max_depth; follow_symlinks; include_hidden; exclude }
  with 
  | Util.Type_error (msg, _) ->
      Printf.eprintf "[Warning] Failed to parse profile: %s\n%!" msg;
      None
  | _ -> None

let get_profiles_dir () =
  let home = Sys.getenv "HOME" in
  let config_dir = 
    try Sys.getenv "XDG_CONFIG_HOME" 
    with Not_found -> Filename.concat home ".config" 
  in
  let dir = Filename.concat (Filename.concat config_dir "quasifind") "profiles" in
  (* Ensure parent dirs exist *)
  let parent = Filename.dirname dir in
  if not (Sys.file_exists parent) then
    (try Unix.mkdir parent 0o755 with _ -> ());
  if not (Sys.file_exists dir) then
    (try Unix.mkdir dir 0o755 with _ -> ());
  dir

let profile_path name =
  Filename.concat (get_profiles_dir ()) (name ^ ".json")

let save ~name profile =
  let path = profile_path name in
  match open_out path with
  | oc ->
      output_string oc (Yojson.Safe.pretty_to_string (to_json profile) ^ "\n");
      close_out oc;
      Ok ()
  | exception Sys_error msg ->
      Error (Printf.sprintf "Cannot save profile: %s" msg)

let load name : (t, string) result =
  let path = profile_path name in
  if not (Sys.file_exists path) then
    Error (Printf.sprintf "Profile '%s' not found" name)
  else
    match open_in path with
    | ic ->
        let content = really_input_string ic (in_channel_length ic) in
        close_in ic;
        (match Yojson.Safe.from_string content with
         | json ->
             (match of_json json with
              | Some p -> Ok p
              | None -> Error "Invalid profile format")
         | exception Yojson.Json_error msg ->
             Error (Printf.sprintf "Invalid JSON: %s" msg))
    | exception Sys_error msg ->
        Error (Printf.sprintf "Cannot read profile: %s" msg)

let list () : string list =
  let dir = get_profiles_dir () in
  if not (Sys.file_exists dir) then []
  else
    match Sys.readdir dir with
    | entries ->
        entries
        |> Array.to_list
        |> List.filter (fun name -> Filename.check_suffix name ".json")
        |> List.map (fun name -> Filename.chop_suffix name ".json")
    | exception _ -> []
