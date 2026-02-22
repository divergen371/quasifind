(** Search Profiles.

    This module manages user-defined search profiles. A profile is a named 
    JSON file (stored in `~/.config/quasifind/profiles/`) that saves a common 
    search query and associated configuration flags. *)

(** Represents a saved search profile. *)
type t = {
  root_dir : string option;   (** The directory to start searching from *)
  expr : string;              (** The quasifind query expression string *)
  max_depth : int option;     (** The maximum depth to search *)
  follow_symlinks : bool;     (** Whether to follow symlinks *)
  include_hidden : bool;      (** Whether to include hidden files *)
  exclude : string list;      (** Paths/names to ignore *)
}

(** [save ~name profile] writes the profile to disk under the given [name]. 
    Returns [Ok ()] on success, or an [Error msg] on failure. *)
val save : name:string -> t -> (unit, string) result

(** [load name] reads the profile with the given [name] from disk.
    Returns [Ok profile] on success, or an [Error msg] on failure. *)
val load : string -> (t, string) result

(** [list ()] enumerates the names of all currently saved profiles. *)
val list : unit -> string list

(** Serializes a profile to JSON. Exposed for testing. *)
val to_json : t -> Yojson.Safe.t

(** Parses a profile from JSON. Exposed for testing. *)
val of_json : Yojson.Safe.t -> t option
