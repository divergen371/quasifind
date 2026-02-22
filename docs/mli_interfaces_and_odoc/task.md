# Task List: .mli and odoc Integration

## 1. Setup & Tooling
- [ ] Verify `odoc` is installed in Opam environment.
- [ ] Check/Add `(documentation)` stanza to `lib/dune`.
- [ ] Run initial `dune build @doc` to ensure baseline generation works.

## 2. Core AST & Config Interfaces
- [ ] Create `ast.mli` with `odoc` comments.
- [ ] Create `config.mli` with `odoc` comments.

## 3. Core Logic & VFS (High Priority for Encapsulation)
- [x] Create `intern.mli` (Hide weak hash table details).
- [x] Create `art.mli` (Make `type 'a t` abstract, expose `insert`, `remove`, `find_opt`).
- [x] Create `vfs.mli` (Expose `t`, `insert`, `remove`, `count_nodes`, hide internal Eio locks if any).
- [x] Create `eval.mli` (Expose `eval`, `can_prune_path`, hide internal recursions).
- [x] Create `dirent.mli`.

## 4. Daemon & Real-time Subsystem
- [x] Create `ipc.mli` (Expose `run`, types `request`/`response`, hide connection loop).
- [x] Create `watcher.mli` (Expose `watch_fibers`, hide internal scan state loops).
- [x] Create `daemon.mli` (Expose `start_daemon`).

## 5. Search Engine & CLI Features
- [x] Create `parser.mli`.
- [x] Create `typecheck.mli`.
- [x] Create `traversal.mli`.
- [x] Create `search.mli`.
- [x] Create remaining feature `.mli`s (`stealth`, `ghost`, `history`, `interactive`, `profile`, `fuzzy_matcher`, etc.).

## 6. Final Review
- [x] Run `dune clean && dune build`.
- [x] Run `dune build @doc`.
- [x] Review HTML output for missing documentation or exposed internal modules.
