(** Polling-based Filesystem Monitoring.

    This module provides functionality to continuously scan a directory tree
    for changes (new, modified, or deleted files) that match a specific AST expression.
    It integrates with Eio for concurrent monitoring and supports various notification
    channels (Webhook, Email, Slack). *)

(** Represents the state of a file used for detecting modifications. *)
type file_state = {
  path : string;
  mtime : float;
  perm : int;
}

(** The type of filesystem events. *)
type event_type =
  | New
  | Modified
  | Deleted

(** Converts an event type to a string representation. *)
val string_of_event : event_type -> string

(** [log_event ?log_channel event_type path] unconditionally formats and writes 
    an event to the given log channel, if one is provided. *)
val log_event : ?log_channel:out_channel -> event_type -> string -> unit

(** Internal notification functions exposed for testing *)
val send_webhook : ?webhook_url:string -> event_type -> string -> unit
val send_email : ?email_addr:string -> event_type -> string -> unit
val send_slack : ?slack_url:string -> event_type -> string -> unit

(** [watch_fibers] starts the monitoring loops as asynchronous Eio fibers.
    
    This function spawns fibers to:
    1. Send periodic heartbeat signals (if configured).
    2. Check configuration file integrity.
    3. Perform periodic filesystem scans to detect changes.
    
    @param sw The Eio switch to attach fibers to.
    @param clock The clock used for sleep delays.
    @param interval Seconds to wait between filesystem scans.
    @param root The root directory to monitor.
    @param cfg The traversal configuration (e.g., hidden files, symlinks).
    @param expr The AST expression to filter monitored files.
    @param on_new Callback fired when a new matching file is found.
    @param on_modified Callback fired when an existing matching file is updated.
    @param on_deleted Callback fired when a previously matching file is removed or stops matching.
    @param log_file Optional path to a file where events will be logged.
    @param webhook_url Optional URL to POST JSON event payloads.
    @param email_addr Optional email address to send event alerts via `mail`.
    @param slack_url Optional Slack Webhook URL to send event alerts.
    @param heartbeat_url Optional URL to POST JSON heartbeat payloads.
    @param heartbeat_interval Seconds between heartbeats (default 60).
    @param shutdown_flag Reference that stops all fibers when set to true. *)
val watch_fibers : 
  sw:Eio.Switch.t -> 
  clock:_ Eio.Time.clock -> 
  interval:float -> 
  root:string -> 
  cfg:Traversal.config -> 
  expr:Ast.Typed.expr -> 
  on_new:(Eval.entry -> unit) -> 
  on_modified:(Eval.entry -> unit) -> 
  on_deleted:(Eval.entry -> unit) -> 
  ?log_file:string -> 
  ?webhook_url:string -> 
  ?email_addr:string -> 
  ?slack_url:string -> 
  ?heartbeat_url:string -> 
  ?heartbeat_interval:int -> 
  ?shutdown_flag:bool ref -> 
  unit -> unit

(** Convenience function to start the watcher in a standalone [Eio_main.run] loop. 
    Accepts the same parameters as [watch_fibers] (except sw and clock). *)
val watch : 
  interval:float -> 
  root:string -> 
  cfg:Traversal.config -> 
  expr:Ast.Typed.expr -> 
  on_new:(Eval.entry -> unit) -> 
  on_modified:(Eval.entry -> unit) -> 
  on_deleted:(Eval.entry -> unit) -> 
  ?log_file:string -> 
  ?webhook_url:string -> 
  ?email_addr:string -> 
  ?slack_url:string -> 
  ?heartbeat_url:string -> 
  ?heartbeat_interval:int -> 
  unit -> unit

(** Standalone watcher that prints events directly to standard output. *)
val watch_with_output : 
  interval:float -> 
  root:string -> 
  cfg:Traversal.config -> 
  expr:Ast.Typed.expr -> 
  ?log_file:string -> 
  ?webhook_url:string -> 
  ?email_addr:string -> 
  ?slack_url:string -> 
  ?heartbeat_url:string -> 
  ?heartbeat_interval:int -> 
  unit -> unit
