open Eio.Std

(* Quote path for shell: 'path' and replace ' with '\'' *)
let quote_path s =
  "'" ^ (Re.Pcre.substitute ~rex:(Re.Pcre.regexp "'") ~subst:(fun _ -> "'\\''") s) ^ "'"

let replace_placeholder template path =
  let re = Re.Pcre.regexp "\\{\\}" in
  try Re.Pcre.substitute ~rex:re ~subst:(fun _ -> path) template
  with _ -> template ^ " " ^ path 

let has_placeholder template =
  try ignore (Re.Pcre.exec ~rex:(Re.Pcre.regexp "\\{\\}") template); true
  with Not_found -> false

let prepare_command template path =
  let quoted_path = quote_path path in
  if has_placeholder template then
    replace_placeholder template quoted_path
  else
    template ^ " " ^ quoted_path

let run_one ~mgr ~sw:_ cmd_template path =
  let cmd_str = prepare_command cmd_template path in
  Eio.Process.run mgr ("sh" :: "-c" :: cmd_str :: [])

let run_batch ~mgr ~sw:_ cmd_template paths =
  (* Quote all paths and join by space *)
  let all_paths = List.map quote_path paths |> String.concat " " in
  let cmd_str = 
    if has_placeholder cmd_template then
      replace_placeholder cmd_template all_paths
    else
      cmd_template ^ " " ^ all_paths
  in
  Eio.Process.run mgr ("sh" :: "-c" :: cmd_str :: [])
