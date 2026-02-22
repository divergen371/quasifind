(** Command History and Result Logging.

    This module provides functionality to save and load previous quasifind 
    searches. It logs the full command-line arguments, timestamp, result count, 
    a small sample of matches, and saves the full result set to a temporary file. *)

(** Represents a single historical search execution. *)
type entry = {
  timestamp : float;                  (** Unix timestamp of the search *)
  command : string list;              (** The full command line executed *)
  results_count : int;                (** Total number of files matched *)
  results_sample : string list;       (** Up to 5 sample file paths from the results *)
  full_results_path : string option;  (** Path to a file containing all matching paths *)
}

(** [add ~cmd ~results] logs a search execution. 
    It automatically saves the full [results] list to a file and appends
    an entry to `~/.local/share/quasifind/history.jsonl`. *)
val add : cmd:string array -> results:string list -> unit

(** [load ()] loads the search history from `~/.local/share/quasifind/history.jsonl`.
    
    @return A list of history entries, ordered chronologically (oldest first). *)
val load : unit -> entry list

(** Serializes a history entry to JSON. Exposed for testing. *)
val entry_to_json : entry -> Yojson.Safe.t

(** Parses a history entry from JSON. Exposed for testing. *)
val entry_of_json : Yojson.Safe.t -> entry option

(** Takes the first n elements of a list. Exposed for testing. *)
val take : int -> 'a list -> 'a list
