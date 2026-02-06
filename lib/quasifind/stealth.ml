(* Stealth module - hide process from ps/top *)
(* Makes quasifind appear as a kernel worker thread *)

external set_process_name : string -> unit = "caml_set_process_name"
external get_default_process_name : unit -> string = "caml_get_default_process_name"

let default_fake_name = get_default_process_name ()

(* Clear argv to hide command line from /proc/PID/cmdline *)
let clear_argv () =
  (* On Unix, we can't directly modify argv, but we can try to minimize exposure *)
  (* The actual hiding is done by the C stub *)
  ()

(* Enable stealth mode *)
let enable ?(fake_name = default_fake_name) () =
  Printf.eprintf "[Stealth] Masking process as '%s'\n%!" fake_name;
  try
    set_process_name fake_name;
    Printf.eprintf "[Stealth] Process name masked successfully\n%!"
  with _ ->
    Printf.eprintf "[Stealth] Warning: Could not mask process name (may require root)\n%!"

(* Check if stealth mode is available *)
let is_available () =
  try
    set_process_name "[test]";
    set_process_name default_fake_name;
    true
  with _ -> false
