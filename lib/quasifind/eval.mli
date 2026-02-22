(** Evaluation Engine for Quasifind Queries.

    This module provides the core logic to evaluate a parsed and typed 
    AST expression against a file entry. It supports matching on name, 
    path, size, time, permissions, content, and entropy. *)

(** Represents the metadata of a single file during evaluation. *)
type entry = {
  name : string;         (** Base name of the file *)
  path : string;         (** Full path to the file *)
  kind : Ast.file_type;  (** Type of the file (File, Dir, Symlink) *)
  size : int64;          (** File size in bytes *)
  mtime : float;         (** Last modification time (Unix timestamp) *)
  perm : int;            (** File permissions *)
}

(** [eval ~preserve_timestamps now expr entry] evaluates the AST [expr] 
    against the given file [entry].
    
    @param preserve_timestamps If true, reading file content (for content/entropy tests) 
                               will restore the original access/modification times.
    @param now The current time (Unix timestamp) used to calculate file age.
    @param expr The typed AST expression to evaluate.
    @param entry The file data to evaluate against.
    @return [true] if the entry matches the expression, [false] otherwise. *)
val eval : ?preserve_timestamps:bool -> float -> Ast.Typed.expr -> entry -> bool

(** [can_prune_path dir_path expr] determines if a directory subtree can be 
    safely pruned (skipped) during traversal based on the query structure.
    
    For example, if the query strictly requires [path == "src/lib/foo.ml"], 
    then any [dir_path] that is not a prefix of that path can be pruned.
    
    @return [true] if the directory and all its children can be guaranteed 
            to *not* match the expression. *)
val can_prune_path : string -> Ast.Typed.expr -> bool

(** [requires_metadata expr] statically analyzes an expression to determine
    if it depends on file metadata (like size, mtime, perm) that requires a `stat` call. *)
val requires_metadata : Ast.Typed.expr -> bool

(** [calculate_entropy content] calculates the Shannon entropy of a string.
    Exposed primarily for testing. *)
val calculate_entropy : string -> float
