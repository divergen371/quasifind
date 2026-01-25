(* Ghost File Detection using lsof *)
(* Looks for unlinked files still open by processes *)

let scan root =
  (* Use human readable format to simplify parsing of the filename at the end *)
  (* 2>/dev/null to hide permission errors etc *)
  let cmd = "lsof +L1 2>/dev/null" in 
  
  try
    let ic = Unix.open_process_in cmd in
    let lines = ref [] in
    try
      while true do
        lines := input_line ic :: !lines
      done;
      []
    with End_of_file ->
      ignore (Unix.close_process_in ic);
      List.rev !lines
      |> List.filter (fun line -> 
           (* Skip header and empty lines *)
           line <> "" && not (String.starts_with ~prefix:"COMMAND" line)
         )
      |> List.map (fun line ->
           (* Extract last column (filename) *)
           match String.split_on_char ' ' line |> List.filter (fun s -> s <> "") |> List.rev with
           | name :: _ -> name
           | [] -> ""
         )
      |> List.filter (fun name -> 
           name <> "" && (
             let abs_root = if Filename.is_relative root then Filename.concat (Sys.getcwd ()) root else root in
             String.starts_with ~prefix:abs_root name
           )
         )
  with _ -> 
    Printf.eprintf "[Warning] 'lsof' command failed or not found. Ghost scan skipped.\n%!";
    []
