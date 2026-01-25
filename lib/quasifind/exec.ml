open Eio.Std

let replace_placeholder template path =
  let re = Re.Pcre.regexp "\\{\\}" in
  try Re.Pcre.substitute ~rex:re ~subst:(fun _ -> path) template
  with _ -> template ^ " " ^ path (* fallback or strict? standard find replaces occurrences or appends? Standard find requires {} usually. If not present, usually it is an error or it appends? "find . -exec ls" -> "ls" runs once or per file? find requires {}. If I follow user request, "command" string is passed. *)
  (* Let's assume: if {} is present, replace all. If not, append path at end. *)

let has_placeholder template =
  try ignore (Re.Pcre.exec ~rex:(Re.Pcre.regexp "\\{\\}") template); true
  with Not_found -> false

let prepare_command template path =
  if has_placeholder template then
    replace_placeholder template path
  else
    template ^ " " ^ path

(* Split string into command and args roughly. 
   This is simplistic. Ideally use a shell parser or requiring proper args list.
   But cmdliner arg is a single string. 
   We will treat the whole string as "sh -c cmd" or parse spaces?
   "sh -c" is safest for complex commands. 
   However, user might want to run without shell overhead.
   If use Eio.Process.spawn, we need prog and args list.
   If we use "sh -c", we need to escape keys. 
   Let's try to do simple space splitting but respect quotes? Too complex for now.
   Let's stick to: if it contains spaces and no {}, maybe use shell?
   
   Actually, Eio.Process.run takes a sw and a list of strings (cmd + args).
   If we use `Sys.command` it blocks the domain? Eio has `Eio.Process`.
   
   Let's assume the input string is a shell command line.
   Using `Eio_unix.Process` (or `Eio.Process`) with a shell is robust.
   `Eio.Process.run mgr ("sh" :: "-c" :: cmd_str :: [])`
*)

let run_one ~mgr ~sw:_ cmd_template path =
  let cmd_str = prepare_command cmd_template path in
  (* Use sh -c to execute the command string defined by user *)
  Eio.Process.run mgr ("sh" :: "-c" :: cmd_str :: [])

let run_batch ~mgr ~sw:_ cmd_template paths =
  (* For batch, we replace {} with all paths joined by space, or append all paths *)
  let all_paths = String.concat " " paths in (* TODO: escaping *)
  let cmd_str = 
    if has_placeholder cmd_template then
      replace_placeholder cmd_template all_paths
    else
      cmd_template ^ " " ^ all_paths
  in
  Eio.Process.run mgr ("sh" :: "-c" :: cmd_str :: [])
