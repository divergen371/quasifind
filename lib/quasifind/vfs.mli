(** Virtual File System (VFS) for Daemon Mode.

    This module maintains an in-memory representation of the filesystem
    using an Adaptive Radix Tree (ART). It allows for extremely fast
    queries without touching the physical disk. *)

(** Represents a file's metadata stored in the VFS. *)
type inode = {
  size : int64;  (** File size in bytes *)
  mtime : float; (** Last modification time (Unix timestamp) *)
  perm : int;    (** File permissions (e.g., 0o755) *)
}

(** Represents a complete entry in the VFS. *)
type entry = {
  kind : Ast.file_type; (** The type of the file (File, Dir, Symlink) *)
  inode : inode;        (** The metadata associated with the file *)
}

(** The abstract type representing the Virtual File System. 
    It is internally backed by an Adaptive Radix Tree. *)
type t

(** An empty VFS. *)
val empty : t

(** [insert vfs path kind size mtime perm] inserts or updates a file entry 
    in the [vfs] at the specified [path].
    
    The [path] is automatically split into segments and interned to save memory. *)
val insert : t -> string -> [ `Dir | `File ] -> int64 -> float -> int -> t

(** [remove vfs path] removes the file or directory at [path] from the [vfs]. *)
val remove : t -> string -> t

(** [find_opt vfs path] looks up the entry at [path] in the [vfs].
    Returns [Some entry] if found, or [None] otherwise. *)
val find_opt : t -> string -> entry option

(** [count_nodes vfs] returns the total number of entries stored inside the [vfs]. *)
val count_nodes : t -> int

(** [fold f acc vfs] folds the function [f] over all entries in the [vfs].
    The function [f] receives the accumulator and an [Eval.entry] object 
    (which includes the full path) to allow evaluation of predicates. *)
val fold : ('a -> Eval.entry -> 'a) -> 'a -> t -> 'a

(** [fold_with_query f acc vfs expr] is an optimized version of [fold] that 
    uses the provided AST [expr] to aggressively prune irrelevant subtrees.
    For example, if the query requires paths starting with "src/", other 
    directories will not be traversed. *)
val fold_with_query : ('a -> Eval.entry -> 'a) -> 'a -> t -> Ast.Typed.expr -> 'a

(** [save vfs path] serializes the entire [vfs] state to a binary file at [path]
    using OCaml's [Marshal] module. Useful for persistent caching across daemon restarts. *)
val save : t -> string -> unit

(** [load path] attempts to deserialize a VFS state from the binary file at [path].
    Returns [Some vfs] if successful, or [None] if the file doesn't exist or is corrupted. *)
val load : string -> t option
