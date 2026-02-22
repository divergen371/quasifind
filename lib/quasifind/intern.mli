(** String Interning for Memory Optimization.

    This module provides a mechanism to deduplicate strings representing
    file paths or components. By reusing a single physical instance of 
    repeating strings, memory usage in the Virtual File System is significantly
    reduced. *)

(** Interns a string.
    If an identical string already exists in the interning pool, returns
    that shared physical instance. Otherwise, adds the given string to the
    pool and returns it. *)
val intern : string -> string
