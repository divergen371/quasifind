(** Suspicious File Detection Logic.

    This module combines built-in heuristics (like checking for 777 permissions 
    or unexpectedly large temp files) with user-defined rules (loaded via `Rule_loader`) 
    to create a composite AST expression capable of finding potentially malicious files. *)

(** [rules ()] constructs an AST expression that represents the logical OR 
    of all built-in suspicious heuristics and dynamically loaded custom rules. 
    It automatically parses and type-checks the custom rules, ignoring invalid ones. *)
val rules : unit -> Ast.Untyped.expr

(** Returns the built-in AST expression for default heuristics without loading 
    external custom rules. Exposed for testing. *)
val default_rules : unit -> Ast.Untyped.expr
