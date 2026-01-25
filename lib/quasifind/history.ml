open Yojson.Safe

type entry = {
  timestamp : float;
  command : string list;
  results_count : int;
  results_sample : string list;
  full_results_path : string option;
} [@@deriving show, eq]

(* Conversion helpers *)
let entry_to_json e =
  `Assoc [
    ("timestamp", `Float e.timestamp);
    ("command", `List (List.map (fun s -> `String s) e.command));
    ("results_count", `Int e.results_count);
    ("results_sample", `List (List.map (fun s -> `String s) e.results_sample));
    ("full_results_path", match e.full_results_path with Some s -> `String s | None -> `Null)
  ]

let entry_of_json json =
  let open Util in
  try
    let timestamp = member "timestamp" json |> to_float in
    let command = member "command" json |> to_list |> List.map to_string in
    let results_count = member "results_count" json |> to_int in
    let results_sample = member "results_sample" json |> to_list |> List.map to_string in
    let full_results_path = match member "full_results_path" json with `String s -> Some s | _ -> None in
    Some { timestamp; command; results_count; results_sample; full_results_path }
  with _ -> None

let get_history_dir () =
  let home = Sys.getenv "HOME" in
  let xdg_data = try Sys.getenv "XDG_DATA_HOME" with Not_found -> Filename.concat (Filename.concat home ".local") "share" in
  let dir = Filename.concat xdg_data "quasifind" in
  if not (Sys.file_exists dir) then Unix.mkdir dir 0o755;
  dir

let get_history_file () =
  Filename.concat (get_history_dir ()) "history.jsonl"

let get_results_dir () =
  let dir = Filename.concat (get_history_dir ()) "results" in
  if not (Sys.file_exists dir) then Unix.mkdir dir 0o755;
  dir

let save_results results =
  let uuid = 
    (* Simple UUID-like string from time and random *)
    let t = Unix.gettimeofday () in
    let r = Random.int 1000000 in
    Printf.sprintf "%.0f-%06d" t r 
  in
  let filename = Filename.concat (get_results_dir ()) (uuid ^ ".txt") in
  let oc = open_out filename in
  List.iter (fun line -> output_string oc (line ^ "\n")) results;
  close_out oc;
  filename

let add ~cmd ~results =
  let timestamp = Unix.gettimeofday () in
  let results_count = List.length results in
  let rec take n = function
    | [] -> []
    | x :: xs -> if n <= 0 then [] else x :: take (n-1) xs
  in
  let results_sample = 
    if results_count > 5 then take 5 results else results 
  in
  
  let full_results_path = 
    if results_count > 0 then Some (save_results results) else None 
  in
  
  let entry = { timestamp; command = Array.to_list cmd; results_count; results_sample; full_results_path } in
  let json = entry_to_json entry in
  
  let history_file = get_history_file () in
  let oc = open_out_gen [Open_wronly; Open_append; Open_creat] 0o644 history_file in
  output_string oc (Yojson.Safe.to_string json ^ "\n");
  close_out oc

let load () =
  let history_file = get_history_file () in
  if not (Sys.file_exists history_file) then []
  else
    let lines = ref [] in
    let ic = open_in history_file in
    try
      while true do
        let line = input_line ic in
        if String.trim line <> "" then
          lines := line :: !lines
      done;
      [] (* unreach *)
    with End_of_file ->
      close_in ic;
      List.filter_map (fun line ->
        try entry_of_json (Yojson.Safe.from_string line)
        with _ -> None
      ) (List.rev !lines)
