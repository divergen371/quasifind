(* Interactive selection module *)

let is_atty () = Unix.isatty Unix.stdin

let check_fzf_availability () =
  try
    let ret = Sys.command "which fzf > /dev/null 2>&1" in
    ret = 0
  with _ -> false

(* Run fzf with candidates piped to stdin *)
let run_fzf candidates =
  let cmd = "fzf" in
  let (ic, oc) = Unix.open_process cmd in
  try
    List.iter (fun s -> output_string oc (s ^ "\n")) candidates;
    close_out oc; (* Send EOF to fzf to start *)
    
    let res = try Some (input_line ic) with End_of_file -> None in
    match Unix.close_process (ic, oc) with
    | Unix.WEXITED 0 -> res
    | _ -> None
  with e ->
    ignore (Unix.close_process (ic, oc));
    None

(* Built-in TUI *)
module TUI = struct
  (* Terminal control *)
  let esc = "\027"
  let csi = esc ^ "["
  let clear_line = csi ^ "2K" ^ "\r"
  let move_up n = if n > 0 then csi ^ string_of_int n ^ "A" else ""
  let hide_cursor = csi ^ "?25l"
  let show_cursor = csi ^ "?25h"

  (* Raw mode configuration *)
  let enable_raw () =
    let termios = Unix.tcgetattr Unix.stdin in
    let new_termios = { termios with 
      c_icanon = false; 
      c_echo = false; 
      c_vmin = 1; 
      c_vtime = 0 
    } in
    Unix.tcsetattr Unix.stdin Unix.TCSANOW new_termios;
    termios (* Return original to restore *)

  let disable_raw termios =
    Unix.tcsetattr Unix.stdin Unix.TCSANOW termios

  (* Input reading *)
  let read_char () =
    let buf = Bytes.create 1 in
    let n = Unix.read Unix.stdin buf 0 1 in
    if n = 0 then None else Some (Bytes.get buf 0)

  (* State *)
  type state = {
    query : string;
    orig_candidates : string list;
    filtered : string list;
    selected_idx : int;
    scroll_offset : int;
  }

  let render state display_rows =
    (* Move cursor up to overwrite previous render *)
    (* We assume we render display_rows + 1 (status line) lines *)
    (* Clear screen area done by overwriting? or clearing? *)
    (* Proper way: Print lines. Next render, move up N lines and print again. *)
    
    let status_line = Printf.sprintf "> %s" state.query in
    output_string stdout (clear_line ^ status_line ^ "\n");
    
    let rec print_candidates idx count =
      if count >= display_rows then ()
      else
        let line_idx = idx + state.scroll_offset in
        if line_idx >= List.length state.filtered then
           output_string stdout (clear_line ^ "~\n") (* Empty line *)
        else
          let cand = List.nth state.filtered line_idx in
          let prefix = if line_idx = state.selected_idx then "> " else "  " in
          (* Highlights? text formatting? Keep simple. *)
          (* Handle ansi strip? Assume simple text. *)
          (* Highlight selected *)
          let line = 
            if line_idx = state.selected_idx then
               esc ^ "[1;32m" ^ prefix ^ cand ^ esc ^ "[0m"
            else prefix ^ cand
          in
          output_string stdout (clear_line ^ line ^ "\n");
          print_candidates (idx + 1) (count + 1)
    in
    print_candidates 0 0;
    
    (* Move cursor back to input line end? No, hide cursor generally. *)
    Printf.printf "%s" (move_up (display_rows + 1));
    flush stdout

  let loop candidates =
    let orig_termios = enable_raw () in
    output_string stdout hide_cursor;
    
    let rec aux state =
      render state 10; (* Display 10 rows *)
      
      match read_char () with
      | None -> None
      | Some c ->
        let code = Char.code c in
        match code with
        | 3 (* Ctrl-C *) | 27 (* Esc *) -> None
        | 10 | 13 (* Enter *) -> 
             if state.selected_idx < List.length state.filtered then
               Some (List.nth state.filtered state.selected_idx)
             else None
        | 127 (* Backspace *) ->
             let q = state.query in
             let len = String.length q in
             let new_q = if len > 0 then String.sub q 0 (len - 1) else q in
             let new_filtered = Fuzzy_matcher.rank ~query:new_q ~candidates:state.orig_candidates in
             aux { state with query = new_q; filtered = new_filtered; selected_idx = 0; scroll_offset = 0 }
        | _ ->
             (* Basic char input *)
             if code >= 32 && code <= 126 then
               let new_q = state.query ^ String.make 1 c in
               let new_filtered = Fuzzy_matcher.rank ~query:new_q ~candidates:state.orig_candidates in
               aux { state with query = new_q; filtered = new_filtered; selected_idx = 0; scroll_offset = 0 }
             else
               (* Handle arrows (Esc [ A / B) *)
               (* If Esc, we handled above. But read might give sequence. 
                  read_char only reads 1 byte.
                  If keys send multiple bytes, we need to read them.
                  Simplification: Just support C-n/C-p for Up/Down or simple chars.
                  Arrow keys are \027[A etc. We need a parser.
                  For now: Ctrl-N (14) = Down, Ctrl-P (16) = Up.
               *)
               match code with
               | 14 (* C-n *) -> 
                   let sel = min (List.length state.filtered - 1) (state.selected_idx + 1) in
                   aux { state with selected_idx = sel }
               | 16 (* C-p *) ->
                   let sel = max 0 (state.selected_idx - 1) in
                   aux { state with selected_idx = sel }
               | _ -> aux state
    in
    
    let init_state = {
       query = "";
       orig_candidates = candidates;
       filtered = candidates;
       selected_idx = 0;
       scroll_offset = 0;
    } in
    
    try
      let res = aux init_state in
      (* Cleanup TUI drawing area? *)
      (* Move to bottom and print newline to preserve output? *)
      Printf.printf "%s" (csi ^ string_of_int 11 ^ "B"); 
      output_string stdout show_cursor;
      disable_raw orig_termios;
      res
    with e ->
      output_string stdout show_cursor;
      disable_raw orig_termios;
      raise e
end

let select ?(query="") candidates =
  if not (is_atty ()) then (
    Printf.eprintf "Interactive selection requires a terminal.\n";
    None
  ) else
  if check_fzf_availability () then
    run_fzf candidates
  else
    TUI.loop candidates
