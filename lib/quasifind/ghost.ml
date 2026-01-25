(* Ghost File Detection using lsof *)
(* Looks for unlinked files still open by processes *)

let scan () =
  let cmd = "lsof +L1 -F n 2>/dev/null" in 
  (* -F n outputs machine readable format: p<PID> then n<NAME> *)
  (* But +L1 with -F might be tricky. Let's use standard output and grep or parse *)
  (* Simple format: lsof +L1 returns lines. We want filenames. *)
  
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
           (* Skip header if present, usually headers start with COMMAND *)
           not (String.starts_with ~prefix:"COMMAND" line)
         )
      |> List.map (fun line ->
           (* Extract last column *)
           match String.split_on_char ' ' line |> List.filter (fun s -> s <> "") |> List.rev with
           | name :: _ -> name
           | [] -> ""
         )
      |> List.filter (fun name -> name <> "")
  with _ -> 
    Printf.eprintf "[Warning] 'lsof' command failed or not found. Ghost scan skipped.\n%!";
    []
