(** Directory Traversal and File Discovery.

    This module handles the physical scanning of the filesystem, taking a query 
    AST to optimize the traversal plan. It supports both single-threaded DFS
    and high-performance concurrent work-stealing traversal. *)

(** The traversal strategy to use. *)
type strategy =
  | DFS                (** Traditional depth-first traversal on a single core *)
  | Parallel of int    (** Concurrent work-stealing traversal with [n] workers *)

(** Configuration for the traversal engine. *)
type config = {
  strategy : strategy;
  max_depth : int option;     (** Stop scanning after descending this many directories *)
  follow_symlinks : bool;     (** Whether to traverse into symlinked directories *)
  include_hidden : bool;      (** Whether to scan files starting with '.' *)
  ignore : string list;       (** Exact directory names to skip (e.g., ".git") *)
  ignore_re : Re.re list;     (** Pre-compiled regexes of paths/names to skip *)
  preserve_timestamps : bool; (** Whether to restore access times after stat/read *)
  spawn : ((unit -> unit) -> unit) option; (** Hook to spawn domains/fibers *)
}

(** [traverse config root_path expr emit] begins a traversal starting at [root_path].
    
    The [expr] AST is analyzed before traversal to prune irrelevant directory branches 
    and optimize `stat` calls.
    
    For every file or directory discovered that hasn't been pruned, [emit entry]
    is called. Note: the [emit] function may be called concurrently from multiple
    threads if the [Parallel] strategy is used. *)
val traverse : config -> string -> Ast.Typed.expr -> (Eval.entry -> unit) -> unit
