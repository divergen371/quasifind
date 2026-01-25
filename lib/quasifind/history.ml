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

let entry_of_json json : entry option =
  let open Util in
  try
    let timestamp = member "timestamp" json |> to_float in
    let command = member "command" json |> to_list |> List.map to_string in
    let results_count = member "results_count" json |> to_int in
    let results_sample = member "results_sample" json |> to_list |> List.map to_string in
    let full_results_path = match member "full_results_path" json with `String s -> Some s | _ -> None in
    Some { timestamp; command; results_count; results_sample; full_results_path }
  with 
  | Util.Type_error (msg, _) ->
      Printf.eprintf "[Warning] Failed to parse history entry: %s\n%!" msg;
      None
  | _ ->
      Printf.eprintf "[Warning] Failed to parse history entry: unknown error\n%!";
      None

let ensure_dir path =
  if not (Sys.file_exists path) then
    try Unix.mkdir path 0o755
    with Unix.Unix_error (err, _, _) ->
      Printf.eprintf "[Warning] Cannot create directory %s: %s\n%!" path (Unix.error_message err)

let get_history_dir () =
  let home = Sys.getenv "HOME" in
  let xdg_data = 
    try Sys.getenv "XDG_DATA_HOME" 
    with Not_found -> Filename.concat (Filename.concat home ".local") "share" 
  in
  let dir = Filename.concat xdg_data "quasifind" in
  ensure_dir dir;
  dir

let get_history_file () =
  Filename.concat (get_history_dir ()) "history.jsonl"

let get_results_dir () =
  let dir = Filename.concat (get_history_dir ()) "results" in
  ensure_dir dir;
  dir

let save_results results =
  let uuid = 
    let t = Unix.gettimeofday () in
    let r = Random.int 1000000 in
    Printf.sprintf "%.0f-%06d" t r 
  in
  let filename = Filename.concat (get_results_dir ()) (uuid ^ ".txt") in
  match open_out filename with
  | oc ->
      List.iter (fun line -> output_string oc (line ^ "\n")) results;
      close_out oc;
      Some filename
  | exception Sys_error msg ->
      Printf.eprintf "[Warning] Cannot save results: %s\n%!" msg;
      None

let take n lst =
  let rec aux n acc = function
    | [] -> List.rev acc
    | _ when n <= 0 -> List.rev acc
    | x :: xs -> aux (n - 1) (x :: acc) xs
  in
  aux n [] lst

let add ~cmd ~results =
  let timestamp = Unix.gettimeofday () in
  let results_count = List.length results in
  let results_sample = 
    if results_count > 5 then take 5 results else results 
  in
  
  let full_results_path = 
    if results_count > 0 then save_results results else None 
  in
  
  let entry = { timestamp; command = Array.to_list cmd; results_count; results_sample; full_results_path } in
  let json = entry_to_json entry in
  
  let history_file = get_history_file () in
  match open_out_gen [Open_wronly; Open_append; Open_creat] 0o644 history_file with
  | oc ->
      output_string oc (Yojson.Safe.to_string json ^ "\n");
      close_out oc
  | exception Sys_error msg ->
      Printf.eprintf "[Warning] Cannot write to history file: %s\n%!" msg

(* Read file lines as Seq *)
let read_lines_seq ic : string Seq.t =
  let rec next () =
    match input_line ic with
    | line -> Seq.Cons (line, next)
    | exception End_of_file -> Seq.Nil
  in
  next

let load () : entry list =
  let history_file = get_history_file () in
  if not (Sys.file_exists history_file) then []
  else
    match open_in history_file with
    | ic ->
        let entries =
          read_lines_seq ic
          |> Seq.filter (fun line -> String.trim line <> "")
          |> Seq.filter_map (fun line ->
               match Yojson.Safe.from_string line with
               | json -> entry_of_json json
               | exception Yojson.Json_error msg ->
                   Printf.eprintf "[Warning] Invalid JSON in history: %s\n%!" msg;
                   None
             )
          |> List.of_seq
        in
        close_in ic;
        entries
    | exception Sys_error msg ->
        Printf.eprintf "[Warning] Cannot read history file: %s\n%!" msg;
        []
