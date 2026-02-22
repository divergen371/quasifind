(** macOS FSEvents integration for native file system monitoring.

    On macOS, this module uses the FSEvents API to watch for file system
    changes with low latency and minimal CPU overhead. On other platforms,
    all operations are no-ops (returning [Unavailable]). *)

(** The result of starting the FSEvents watcher. *)
type status = Available | Unavailable

(** [start ~path ~latency] begins watching [path] for file system changes.
    Events are buffered internally and retrieved via [poll].
    [latency] is the coalescing interval in seconds (e.g., 0.5).
    Returns [Available] on success, [Unavailable] if FSEvents is not supported. *)
val start : path:string -> latency:float -> status

(** [poll ()] returns a list of paths that have changed since the last poll.
    Returns an empty list if no changes occurred or FSEvents is unavailable. *)
val poll : unit -> string list

(** [stop ()] stops the FSEvents watcher and releases resources. *)
val stop : unit -> unit
