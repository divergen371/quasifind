(** Fast Regex Searching via C Stubs.

    This module provides bindings to optimized C implementations of regex
    searching (using PCRE2 and memory-mapped files). This allows Quasifind
    to bypass OCaml's GC overhead when scanning the contents of large files. *)

(** The result of a regex search operation. *)
type search_result = 
  | Match    (** The pattern was found in the file *)
  | NoMatch  (** The pattern was not found in the file *)
  | Fallback (** An error occurred (e.g., file unreadable, pattern invalid), 
                 so the caller should fall back to OCaml's Re module. *)

(** [regex path pattern] opens the file at [path] and searches for [pattern]
    using an optimized C stub. *)
val regex : string -> string -> search_result
