(** External Rule Fetching and Conversion.

    This module handles the downloading of external security lists 
    (e.g., known malware extensions, suspicious filenames) defined in the 
    configuration and converts them into quasifind AST rules. *)

(** [update_from_source ()] fetches the rule sources defined in the current 
    configuration, converts their contents into valid quasifind detection rules, 
    and saves the new rule set to disk. Prints progress to stdout. *)
val update_from_source : unit -> unit

(** Converts a list of extension or filename strings into a regex alternation 
    pattern (e.g., "a|b|c"). Exposed for testing. *)
val list_to_regex_alt : string list -> string
