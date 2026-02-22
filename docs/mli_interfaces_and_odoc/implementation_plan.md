# Implementation Plan: .mli Interfaces and odoc Documentation (#38, #39)

## Goal
Improve code quality, maintainability, and clarity by introducing Interface files (`.mli`) for all modules in `lib/quasifind/` and integrating standard OCaml `odoc` documentation.

## Proposed Strategy

1.  **Dune Configuration for odoc**
    *   Ensure `(documentation)` stanza exists in `lib/dune`.
    *   Verify `dune build @doc` works and produces expected output structure.
2.  **Iterative `.mli` Creation & Documentation**
    We will approach the modules logically, prioritizing core data structures and interfaces first, ensuring each step compiles.

    *   **Group 1: Core AST & Config**
        *   `ast.mli`: Document AST types and operators.
        *   `config.mli`: Document configuration types.
    *   **Group 2: Core Logic & File System**
        *   `eval.mli`: Document the `eval` function and required types. Hide recursive internal logic.
        *   `intern.mli`: Document the string interning interface.
        *   `vfs.mli` / `art.mli`: CRITICAL. Define `type 'a t` abstractly. Expose only public operations (`insert`, `find_opt`, `remove`, `fold`). Hide internal `Node4`, `Node16` etc. (or `Small`/`Large`).
        *   `dirent.mli`: Document directory entry types and `readdir` signatures.
    *   **Group 3: Daemon & IPC**
        *   `ipc.mli`: Document the JSON-RPC interface and server start function.
        *   `daemon.mli`: Expose only the daemon start function.
        *   `watcher.mli`: Expose the watching interface.
    *   **Group 4: Search & Features**
        *   `traversal.mli`, `fuzzy_matcher.mli`, `stealth.mli`, `ghost.mli`, `history.mli`, `interactive.mli`, `profile.mli`, `rule_converter.mli`, `rule_loader.mli`, `search.mli`, `suspicious.mli`, `typecheck.mli`, `parser.mli`.
3.  **Documentation Standards**
    *   Use standard `odoc` syntax: `(** [func arg] does X... *)` preceding declarations in `.mli` files.
    *   Ensure all public types and functions are commented.
    *   Hide helper functions entirely from the `.mli`.

## Verification Plan

### Automated Checks
*   **Compilation**: `opam exec -- dune build` must pass continuously. This ensures `.mli` signatures perfectly match `.ml` implementations.
*   **Doc Generation**: `opam exec -- dune build @doc` must succeed without warnings about unresolvable references.

### Manual Verification
*   Open the generated HTML `_build/default/_doc/_html/quasifind/Quasifind/index.html` in a local browser to verify the structure, rendering of markdown/comments, and absence of internal types.
*   Confirm that a change in `vfs.ml` (implementation) does not trigger recompilation of `daemon.ml` (provided `vfs.mli` remains unchanged).
