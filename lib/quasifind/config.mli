(** Configuration management for Quasifind.

    This module handles loading, parsing, and saving the user configuration
    typically stored in `~/.config/quasifind/config.json`. *)

(** The type of fuzzy finder to use for interactive search mode. *)
type fuzzy_finder = Auto | Fzf | Builtin
[@@deriving show, eq]

(** The type of source for security/suspicious rules. *)
type rule_source_type = Extensions | Filenames
[@@deriving show, eq]

(** Definition of a remote rule source. *)
type rule_source_def = {
  name : string;
  url : string;
  kind : rule_source_type;
}
[@@deriving show, eq]

(** The main configuration record. *)
type t = {
  fuzzy_finder : fuzzy_finder;
  ignore : string list;               (** Directories to always ignore (e.g., .git, node_modules) *)
  email : string option;              (** Email for alerts *)
  webhook_url : string option;        (** Webhook URL for alerts *)
  slack_url : string option;          (** Slack webhook URL for alerts *)
  heartbeat_url : string option;      (** URL to ping for daemon heartbeat *)
  heartbeat_interval : int;           (** Interval in seconds for heartbeat pings *)
  rule_sources : rule_source_def list;(** Remote sources for suspicious file rules *)
  daemon : daemon_config;             (** Daemon-specific configuration *)
}
[@@deriving show, eq]

(** Configuration specific to the daemon process. *)
and daemon_config = {
  watch_interval : float;    (** Interval in seconds between watcher scans (default: 2.0) *)
  cache_path : string option;(** Custom cache directory (default: ~/.cache/quasifind/) *)
  roots : string list;       (** Root directories to watch (default: ["."]) *)
  exclude : string list;     (** Directory patterns to exclude from scanning *)
}
[@@deriving show, eq]

(** The default configuration. *)
val default : t

(** Parses a fuzzy finder value from a string. *)
val fuzzy_finder_of_string : string -> fuzzy_finder

(** Parses a configuration from a Yojson AST. *)
val t_of_json : Yojson.Safe.t -> t

(** Serializes a configuration to a Yojson AST. *)
val t_to_json : t -> Yojson.Safe.t

(** Loads the configuration from the standard user config path.
    If the file does not exist, it creates a default one and returns it. *)
val load : unit -> t

(** Resets the configuration file to the default state, overwriting any existing config. *)
val reset_to_default : unit -> unit

(** Retrieves the absolute path to the configuration directory. *)
val get_config_dir : unit -> string

(** Retrieves the absolute path to the configuration file (config.json). *)
val get_config_path : unit -> string
