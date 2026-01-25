(* Interactive selection module *)

let is_atty () = Unix.isatty Unix.stdin

let check_fzf_availability () =
  try
    let ret = Sys.command "which fzf > /dev/null 2>&1" in
    ret = 0
  with _ -> false

(* Run fzf with candidates piped to stdin *)
let run_fzf ?preview_cmd candidates =
  let preview_opt = match preview_cmd with
    | Some cmd -> " --preview '" ^ cmd ^ "'"
    | None -> ""
  in
  let fzf_cmd = "fzf" ^ preview_opt in
  let (ic, oc) = Unix.open_process fzf_cmd in
  try
    List.iter (fun s -> output_string oc (s ^ "\n")) candidates;
    close_out oc; (* Send EOF to fzf to start *)
    
    let res = try Some (input_line ic) with End_of_file -> None in
    match Unix.close_process (ic, oc) with
    | Unix.WEXITED 0 -> res
    | _ -> None
  with _ ->
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

  (* Input reading with Escape Sequence handling *)
  type key = 
    | Char of char
    | Enter
    | Backspace
    | Up
    | Down
    | Esc
    | Unknown

  let read_key () =
    let buf = Bytes.create 3 in
    match Unix.read Unix.stdin buf 0 1 with
    | 0 -> None
    | _ ->
      let c = Bytes.get buf 0 in
      match c with
      | '\027' -> (* Escape sequence? *)
          let old_vmin = (Unix.tcgetattr Unix.stdin).c_vmin in
          let old_vtime = (Unix.tcgetattr Unix.stdin).c_vtime in
          (* Set non-blocking read to check for sequence *)
          let termios = Unix.tcgetattr Unix.stdin in
          Unix.tcsetattr Unix.stdin Unix.TCSANOW { termios with c_vmin = 0; c_vtime = 0 };
          
          let res = 
            match Unix.read Unix.stdin buf 1 2 with
            | 0 -> Esc (* Just Esc *)
            | n ->
              if n >= 2 && Bytes.get buf 1 = '[' then
                match Bytes.get buf 2 with
                | 'A' -> Up
                | 'B' -> Down
                | _ -> Unknown
              else Esc (* Unknown sequence or incomplete, treat as Esc for safety *)
          in
          (* Restore blocking *)
          Unix.tcsetattr Unix.stdin Unix.TCSANOW { termios with c_vmin = old_vmin; c_vtime = old_vtime };
          Some res
      | '\n' | '\r' -> Some Enter
      | '\127' -> Some Backspace
      | c -> Some (Char c)

  (* State *)
  type state = {
    query : string;
    orig_candidates : string list;
    filtered : string list;
    selected_idx : int;
    scroll_offset : int;
  }

  let get_term_size () =
    try
      let ic = Unix.open_process_in "tput cols" in
      let cols = try int_of_string (String.trim (input_line ic)) with _ -> 80 in
      ignore (Unix.close_process_in ic);
      let ic = Unix.open_process_in "tput lines" in
      let rows = try int_of_string (String.trim (input_line ic)) with _ -> 24 in
      ignore (Unix.close_process_in ic);
      (cols, rows)
    with _ -> (80, 24)

  let truncate s len =
    let len = max 10 len in
    if String.length s <= len then s
    else String.sub s 0 (len - 3) ^ "..."

  (* Shell-safe quoting for preview command argument *)
  let shell_quote s =
    let b = Buffer.create (String.length s + 10) in
    Buffer.add_char b '\'';
    String.iter (fun c ->
      if c = '\'' then Buffer.add_string b "'\\''"
      else Buffer.add_char b c
    ) s;
    Buffer.add_char b '\'';
    Buffer.contents b

  (* Read lines from input channel as Seq *)
  let read_lines_seq ic : string Seq.t =
    let rec next () =
      match input_line ic with
      | line -> Seq.Cons (line, next)
      | exception End_of_file -> Seq.Nil
    in
    next

  (* Execute preview command and get output lines *)
  let get_preview preview_cmd selected_item =
    match preview_cmd with
    | None -> []
    | Some cmd_template ->
        let quoted_item = shell_quote selected_item in
        let cmd = Str.global_replace (Str.regexp_string "{}") quoted_item cmd_template in
        match Unix.open_process_in cmd with
        | ic ->
            let lines = read_lines_seq ic |> List.of_seq in
            ignore (Unix.close_process_in ic);
            lines
        | exception Unix.Unix_error (err, _, _) ->
            Printf.eprintf "[Warning] Preview command failed: %s\n%!" (Unix.error_message err);
            ["(Preview error)"]

  let render state display_rows (cols, _) preview_cmd =
    let left_width = cols / 2 - 1 in
    let right_width = cols - left_width - 3 in (* 3 for separator *)
    
    (* Get preview content for selected item *)
    let selected_item = 
      if state.selected_idx < List.length state.filtered then
        List.nth state.filtered state.selected_idx
      else ""
    in
    let preview_lines = 
      if preview_cmd = None then [] 
      else get_preview preview_cmd selected_item 
    in
    
    (* Status line *)
    let status_line = Printf.sprintf "> %s" state.query in
    output_string stderr (clear_line ^ "\r" ^ truncate status_line (cols - 1) ^ "\n");
    
    let rec print_row idx =
      if idx >= display_rows then ()
      else begin
        let line_idx = idx + state.scroll_offset in
        
        (* Left pane: candidates *)
        let left_content =
          if line_idx >= List.length state.filtered then "~"
          else
            let cand = List.nth state.filtered line_idx in
            let prefix = if line_idx = state.selected_idx then "> " else "  " in
            let display_cand = truncate cand (left_width - 4) in
            if line_idx = state.selected_idx then
              esc ^ "[1;32m" ^ prefix ^ display_cand ^ esc ^ "[0m"
            else prefix ^ display_cand
        in
        
        (* Right pane: preview *)
        let right_content =
          if preview_cmd = None then ""
          else if idx < List.length preview_lines then
            truncate (List.nth preview_lines idx) right_width
          else ""
        in
        
        (* Render row *)
        let separator = if preview_cmd = None then "" else " │ " in
        let left_padded = 
          let visible_len = 
            (* Remove ANSI codes for length calc *)
            let stripped = Str.global_replace (Str.regexp "\027\\[[0-9;]*m") "" left_content in
            String.length stripped
          in
          left_content ^ String.make (max 0 (left_width - visible_len)) ' '
        in
        output_string stderr (clear_line ^ "\r" ^ left_padded ^ separator ^ right_content ^ "\n");
        print_row (idx + 1)
      end
    in
    print_row 0;
    
    Printf.eprintf "%s" (move_up (display_rows + 1));
    flush stderr

  let loop ?preview_cmd candidates =
    let orig_termios = enable_raw () in
    output_string stderr hide_cursor;
    let term_dims = get_term_size () in
    
    let rec aux state =
      render state 10 term_dims preview_cmd;
      
      match read_key () with
      | None -> None
      | Some key ->
        match key with
        | Esc -> None
        | Enter -> 
             if state.selected_idx < List.length state.filtered then
               Some (List.nth state.filtered state.selected_idx)
             else None
        | Backspace ->
             let q = state.query in
             let len = String.length q in
             let new_q = if len > 0 then String.sub q 0 (len - 1) else q in
             let new_filtered = Fuzzy_matcher.rank ~query:new_q ~candidates:state.orig_candidates in
             aux { state with query = new_q; filtered = new_filtered; selected_idx = 0; scroll_offset = 0 }
        | Up ->
             let sel = max 0 (state.selected_idx - 1) in
             let scroll = 
               if sel < state.scroll_offset then sel 
               else state.scroll_offset 
             in
             aux { state with selected_idx = sel; scroll_offset = scroll }
        | Down ->
             let sel = min (List.length state.filtered - 1) (state.selected_idx + 1) in
             let scroll = 
               if sel >= state.scroll_offset + 10 then sel - 9
               else state.scroll_offset
             in
             aux { state with selected_idx = sel; scroll_offset = scroll }
        | Char c ->
             let code = Char.code c in
             (* Support C-p / C-n as well *)
             if code = 14 then (* C-n *)
                 let sel = min (List.length state.filtered - 1) (state.selected_idx + 1) in
                 let scroll = if sel >= state.scroll_offset + 10 then sel - 9 else state.scroll_offset in
                 aux { state with selected_idx = sel; scroll_offset = scroll }
             else if code = 16 then (* C-p *)
                 let sel = max 0 (state.selected_idx - 1) in
                 let scroll = if sel < state.scroll_offset then sel else state.scroll_offset in
                 aux { state with selected_idx = sel; scroll_offset = scroll }
             else if code >= 32 && code <= 126 then
               let new_q = state.query ^ String.make 1 c in
               let new_filtered = Fuzzy_matcher.rank ~query:new_q ~candidates:state.orig_candidates in
               aux { state with query = new_q; filtered = new_filtered; selected_idx = 0; scroll_offset = 0 }
             else
               aux state
        | Unknown -> aux state
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
      Printf.eprintf "%s" (csi ^ string_of_int 11 ^ "B"); 
      output_string stderr show_cursor;
      disable_raw orig_termios;
      res
    with e ->
      output_string stderr show_cursor;
      disable_raw orig_termios;
      raise e
end

let select ?(query="") ?(finder=Config.Auto) ?preview_cmd candidates =
  if not (is_atty ()) then (
    Printf.eprintf "Interactive selection requires a terminal.\n";
    None
  ) else
  let use_fzf = 
    match finder with
    | Config.Fzf -> true
    | Config.Builtin -> false
    | Config.Auto -> check_fzf_availability ()
  in
  
  if use_fzf then
    if check_fzf_availability () then
      run_fzf ?preview_cmd candidates
    else (
      if finder = Config.Fzf then Printf.eprintf "Warning: fzf not found, falling back to builtin TUI.\n";
      TUI.loop ?preview_cmd candidates
    )
  else
    TUI.loop ?preview_cmd candidates
