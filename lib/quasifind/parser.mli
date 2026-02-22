(** Parser for Quasifind Queries.

    This module parses user-provided query strings into an untyped 
    Abstract Syntax Tree (AST). It uses the Angstrom parser combinator library 
    to handle complex expressions, sizes, and durations. *)

(** [parse str] takes a query string [str] and attempts to parse it into an 
    `Ast.Untyped.expr`. 
    
    @return [Ok expr] if parsing succeeds, or [Error msg] with details about 
            the syntax error. *)
val parse : string -> (Ast.Untyped.expr, string) result
