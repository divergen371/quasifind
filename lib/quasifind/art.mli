(** Adaptive Radix Tree (ART) implementation for Quasifind.

    This module provides an efficient Radix Tree (Prefix Trie) data structure
    used as the core of the Virtual File System (VFS). It optimizes memory by 
    adapting node sizes based on the number of children (e.g., small arrays vs.
    hash maps) and sharing common path prefixes.
    
    The internal structure of the tree is safely hidden behind this interface. *)

module PathMap : Map.S with type key = String.t

(** Internal node structure representing the children of a Radix Tree node. 
    Exposed primarily for testing/advanced traversal. *)
type 'a children =
  | Small of (string * 'a t) list
  | Large of 'a t PathMap.t

(** The type representing the Radix Tree. 
    ['a] is the type of the value stored at the leaf nodes. *)
and 'a t = {
  value : 'a option;
  children : 'a children;
}

(** An empty tree. *)
val empty : 'a t

(** [insert tree path_parts value] inserts a [value] into the [tree] 
    at the location specified by the list of [path_parts] (e.g., ["src"; "main.ml"]). *)
val insert : 'a t -> string list -> 'a -> 'a t

(** [find_opt tree path_parts] looks up the value associated with [path_parts].
    Returns [Some value] if found, or [None] otherwise. *)
val find_opt : 'a t -> string list -> 'a option

(** [remove tree path_parts] removes the value associated with [path_parts] from
    the tree, pruning empty intermediate nodes to save memory. *)
val remove : 'a t -> string list -> 'a t

(** [fold f acc tree] folds the function [f] over all values stored in the tree.
    The fold order is not strictly guaranteed but generally follows a depth-first traversal. *)
val fold : ('acc -> 'a -> 'acc) -> 'acc -> 'a t -> 'acc

(** [fold_path f acc tree] is similar to [fold], but the function [f] also 
    receives the reconstructed string path of each entry. *)
val fold_path : ('acc -> string -> 'a -> 'acc) -> 'acc -> 'a t -> 'acc

(** [fold_with_prune can_prune f acc tree] folds over the tree but allows 
    skipping of entire subtrees if [can_prune path_prefix] returns true. *)
val fold_with_prune : (string -> bool) -> ('acc -> string -> 'a -> 'acc) -> 'acc -> 'a t -> 'acc

(** [count_nodes tree] returns the total number of values (nodes with data) 
    stored in the tree. *)
val count_nodes : 'a t -> int
