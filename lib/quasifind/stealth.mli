(** Process Hiding Capabilities.

    This module allows the quasifind daemon/process to hide its identity 
    from system monitors like `ps` or `top` by modifying its `argv` and 
    process name via C stubs. *)

(** [enable ?fake_name ()] attempts to mask the current process name.
    If [fake_name] is not provided, it defaults to a system-appropriate 
    fake name (e.g., "[kworker/0:1]" on Linux). *)
val enable : ?fake_name:string -> unit -> unit

(** [is_available ()] checks if the current OS supports process name 
    modification (some platforms or permission levels may restrict this). *)
val is_available : unit -> bool

(** The default fake process name used if none is specified (e.g., "[kworker/0:1]").
    Exposed for testing. *)
val default_fake_name : string

(** Clears the process argument vector (argv). Exposed for testing. *)
val clear_argv : unit -> unit
