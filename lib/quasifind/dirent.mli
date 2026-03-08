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
    tuples containing the entry name, its [kind], [size], and [mtime].
    
    This uses a Zig FFI stub to read `d_type` directly from `dirent`. *)
val readdir : string -> (string * kind * int * int) list

(** [iter_batch path f] iterates over the entries in the directory at [path],
    calling the function [f name kind size mtime] for each entry.
    [size] and [mtime] may be -1 if they are not available from the OS traversal API.
    
    This uses a highly optimized Zig FFI stub to read directory entries in batches
    into a pre-allocated buffer, significantly reducing the overhead of 
    crossing the OCaml/Zig boundary. *)
val iter_batch : ?prefixes:string array -> ?suffixes:string array -> string -> (string -> kind -> int -> int -> unit) -> unit
