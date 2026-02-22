(** Output formatting for search results.

    Supports multiple output formats (default, JSON, CSV, table, null-separated)
    and colored output based on file type. *)

(** Output format type. *)
type format =
  | Default  (** Path only, one per line *)
  | Json     (** JSON array with full metadata *)
  | Csv      (** CSV with header row *)
  | Table    (** Fixed-width table *)
  | Null     (** Null-separated paths (for xargs -0) *)

(** Color mode for terminal output. *)
type color_mode =
  | Always  (** Always use ANSI colors *)
  | Auto    (** Use colors when stdout is a TTY *)
  | Never   (** No colors *)

(** [parse_format s] parses a format string.
    Returns [Some format] or [None] if invalid. *)
val parse_format : string -> format option

(** [parse_color s] parses a color mode string.
    Returns [Some mode] or [None] if invalid. *)
val parse_color : string -> color_mode option

(** [format_entry ~format ~color entry] formats a single entry for output. *)
val format_entry : format:format -> color:color_mode -> Eval.entry -> string

(** [format_header ~format] returns a header string if the format requires one. *)
val format_header : format:format -> string option

(** [format_json_start ()] returns the opening bracket for JSON array output. *)
val format_json_start : unit -> string

(** [format_json_end ()] returns the closing bracket for JSON array output. *)
val format_json_end : unit -> string
