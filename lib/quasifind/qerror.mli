(** Global Error Types and Formatting.

    This module defines the unified error type used throughout the quasifind 
    application to replace raw exception throwing. It also provides utilities 
    for converting errors to user-friendly messages and standard exit codes. *)

(** The unified error type for Quasifind. *)
type t =
  | ParseError of string          (** Syntax error during query parsing *)
  | TypeError of string           (** Type mismatch or invalid operation in the query *)
  | FileError of string * string  (** File system access error (path, reason) *)
  | DaemonError of string         (** Error related to the background daemon and IPC *)
  | PermissionDenied of string    (** Permission denied accessing a path *)
  | GeneralError of string        (** Any other unexpected application error *)

(** Converts an error to a human-readable, user-friendly string message. *)
val to_string : t -> string

(** Returns an appropriate process exit code for the given error.
    - 0 indicates success (not an error, though not represented here).
    - 1 indicates a general or file-related error.
    - 2 indicates a syntax or type error (user input mistake).
    - 3 indicates a daemon or IPC connection error. *)
val to_exit_code : t -> int
