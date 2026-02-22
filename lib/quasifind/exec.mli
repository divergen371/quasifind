(** Execution of External Commands.

    This module handles the `-exec` functionality of quasifind, allowing 
    discovered files to be passed to external shell commands securely. *)

(** [run_one ~mgr ~sw cmd_template path] executes a command for a single file.
    
    If [cmd_template] contains "[{}]", it is replaced with the shell-quoted [path].
    Otherwise, the shell-quoted [path] is appended to the end of the command.
    
    @param mgr The Eio Process manager.
    @param sw The Eio Switch (ignored currently).
    @param cmd_template The command string template (e.g., "rm -f [{}]").
    @param path The file path to execute the command on. *)
val run_one : mgr:_ Eio.Process.mgr -> sw:'a -> string -> string -> unit

(** [run_batch ~mgr ~sw cmd_template paths] executes a command once, passing 
    multiple files as arguments at the same time.
    
    If [cmd_template] contains "[{}]", it is replaced with a space-separated 
    list of all shell-quoted [paths]. Otherwise, the quoted paths are appended.
    
    @param mgr The Eio Process manager.
    @param sw The Eio Switch (ignored currently).
    @param cmd_template The command string template (e.g., "chmod +x").
    @param paths The list of file paths. *)
val run_batch : mgr:_ Eio.Process.mgr -> sw:'a -> string -> string list -> unit

(** Shell-quotes a string. Exposed for testing. *)
val quote_path : string -> string

(** Checks if a command template contains the "[{}]" placeholder. Exposed for testing. *)
val has_placeholder : string -> bool

(** Replaces the "[{}]" placeholder in a template with the given path. Exposed for testing. *)
val replace_placeholder : string -> string -> string

(** Constructs the final shell command string by either replacing "[{}]" or appending the quoted path. Exposed for testing. *)
val prepare_command : string -> string -> string
