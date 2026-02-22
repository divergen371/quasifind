(** Typechecker for Quasifind AST.

    This module validates an untyped Abstract Syntax Tree (AST), ensuring that
    operators are applied to correct field types (e.g., preventing string matching
    on file sizes) and compiling regular expressions. *)

(** Represents errors encountered during type checking. *)
type error = 
  | UnknownField of string
  | TypeMismatch of { field: string; expected: string; got: string }
  | InvalidOp of { field: string; op: Ast.cmp_op; reason: string }
  | RegexError of string

(** Formats a type checking error into a human-readable string. *)
val string_of_error : error -> string

(** [check expr] converts an untyped AST expression into a typed AST expression.
    
    It validates all comparisons, normalizes sizes (e.g., '1MB' to bytes) and 
    durations (e.g., '1h' to seconds), and pre-compiles any regular expressions.
    
    @return [Ok typed_expr] if the expression is well-typed, or an [Error] with details. *)
val check : Ast.Untyped.expr -> (Ast.Typed.expr, error) result
