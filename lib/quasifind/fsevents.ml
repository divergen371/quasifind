(* fsevents.ml - macOS FSEvents bindings *)

external start_c : string -> float -> int = "caml_fsevents_start"
external poll_c : unit -> string list = "caml_fsevents_poll"
external stop_c : unit -> unit = "caml_fsevents_stop"

type status = Available | Unavailable

let start ~path ~latency : status =
  match start_c path latency with
  | 1 -> Available
  | _ -> Unavailable

let poll () : string list = poll_c ()

let stop () : unit = stop_c ()
