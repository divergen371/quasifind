(** JIT Compile Cache for Regular Expressions.

    Compiling regular expressions is an expensive operation. This module
    provides a thread-safe, size-bounded cache for compiled PCRE regexes. *)

(** [compile pattern] returns a compiled regular expression for the given pattern.
    If the pattern was compiled recently, it returns the cached instance.
    @param pattern The PCRE pattern string to compile.
    @return The compiled regular expression.
    @raise Re.Pcre.Parse_error if the pattern is syntactically invalid. *)
val compile : string -> Re.re
