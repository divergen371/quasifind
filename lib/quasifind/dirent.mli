(** Directory Traversal and Type Reading.

    This module provides efficient bindings to Zig FFI stubs for reading directory 
    entries along with their file types (`d_type`), avoiding the need for 
    separate `stat` calls during filesystem traversal. *)

(** The type of a directory entry as reported by the OS. *)
type kind =
  | Unknown
  | Reg      (** Regular file *)
  | Dir      (** Directory *)
  | Symlink  (** Symbolic link *)
  | Other    (** Sockets, pipes, block devices, etc. *)

(** [readdir path] reads the directory at [path] and returns a list of 
    tuples containing the entry name and its [kind].
    
    This uses a Zig FFI stub to read `d_type` directly from `dirent`. *)
val readdir : string -> (string * kind) list

(** [iter_batch path f] iterates over the entries in the directory at [path],
    calling the function [f name kind] for each entry.
    
    This uses a highly optimized Zig FFI stub to read directory entries in batches
    into a pre-allocated buffer, significantly reducing the overhead of 
    crossing the OCaml/Zig boundary. *)
val iter_batch : ?prefixes:string array -> ?suffixes:string array -> string -> (string -> kind -> unit) -> unit

(** [readdir_bulk path] immediately fetches all directory entries including their
    metadata (size, mtime, mode, uid, gid) directly from the OS in a single bulk operation 
    (where supported, e.g. getattrlistbulk on macOS).
    
    This is highly optimized for GUI file manager listing where full metadata
    of all entries must be loaded instantaneously, without sequential stat calls.
    Returns an array of tuples: (name, kind, size_in_bytes, mtime_seconds, mode, uid, gid). *)
val readdir_bulk : string -> (string * kind * int * int * int * int * int) array
