(** Interactive Terminal User Interface (TUI).

    This module provides an interactive interface for selecting files from 
    a list of candidates. It attempts to use `fzf` if available, otherwise 
    falling back to a built-in terminal UI. *)

(** [is_atty ()] returns true if stdin is a terminal. Exposed for testing. *)
val is_atty : unit -> bool

(** [select ~query ~finder ~preview_cmd candidates] displays an interactive 
    selection menu in the terminal.
    
    @param query Initial query string to pre-fill the search box.
    @param finder Configuration for which finder backend to use (fzf vs builtin).
    @param preview_cmd A command template (using [{}]) used to preview the currently highlighted file.
    @param candidates The list of string paths to select from.
    @return [Some selected_path] if the user makes a selection, or [None] if they cancel. *)
val select : 
  ?query:string -> 
  ?finder:Config.fuzzy_finder -> 
  ?preview_cmd:string -> 
  string list -> 
  string option

(** Internal TUI module exposed primarily for testing text formatting. *)
module TUI : sig
  (** [truncate str len] safely cuts a string to a maximum length, 
      appending "..." if it exceeds the limit. *)
  val truncate : string -> int -> string

  (** [sanitize str] replaces non-printable characters and control codes with readable equivalents 
      to prevent terminal corruption, while preserving UTF-8 multi-byte characters. *)
  val sanitize : string -> string

  (** Safely quotes a string for bash execution. Exposed for testing. *)
  val shell_quote : string -> string

  val move_up : int -> string
  val clear_line : string
  val hide_cursor : string
  val show_cursor : string
end
