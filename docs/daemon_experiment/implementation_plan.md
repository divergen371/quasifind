## Phase 3: IPC Server & Client Query (Communication)

### Goal

Enable external `quasifind` commands to query the running daemon for instant search results, bypassing the slow disk traversal.

### Proposed Changes

#### [NEW] [lib/quasifind/ipc.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/ipc.ml)

- **Unix Domain Socket**: Server listening on `~/.cache/quasifind/daemon.sock`.
- **Protocol**: Simple JSON-based protocol (newline delimited).
  - Request: `{ "type": "query", "expr": <json_ast> }` | `{ "type": "stats" }` | `{ "type": "shutdown" }`
  - Response: `{ "status": "ok", "results": [ ... ] }` | `{ "status": "error", "message": "..." }`

#### [MODIFY] [lib/quasifind/daemon.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/daemon.ml)

- **Integration**:
  - Initialize `Ipc.server` in the Eio loop.
  - Handle incoming queries by executing `Eval` against the in-memory `Vfs`.
  - Ensure concurrent query handling (read-lock on VFS if needed, or rely on persistent functional structure).

#### [MODIFY] [bin/main.ml](file:///Users/atsushi/OCaml/quasifind/bin/main.ml)

- **Client Logic**:
  - Add logic to `search` command to check if daemon is running (socket exists).
  - If daemon exists, send query via IPC.
  - If daemon fails or not running, fallback to standard traversal (or error if `--daemon-only` flag is set).

### Verification Plan

- **IPC Test**: Use `nc -U` to send raw JSON requests to the socket.
- **Client Test**: Run `quasifind -name "*.ml"` and verify it uses the daemon (check speed/logs).

## Phase 4: Advanced Features & Optimization

### [MODIFY] [lib/quasifind/ipc.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/ipc.ml)

- **Regex Support**:
  - Update `json_to_expr` to properly deserialize `StrRe` patterns.
  - Implement server-side regex compilation/execution.

### [NEW] [lib/quasifind/art.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/art.ml)

- **Adaptive Radix Tree**:
  - Implement a specialized Trie for file paths.
  - Key optimization: Span compression (compress linear paths like `usr/local/bin` into one node).
  - Use `Adaptive` node types (Array4, Array16, Array48, Array256) to save memory for sparse/dense directories.
- **Integration**:
  - Replace `Vfs.t` (currently `Map`-based Trie) with `Art.t`.

### [MODIFY] [lib/quasifind/daemon.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/daemon.ml)

- **Hybrid Search**:
  - For `Content` and `Entropy` queries:
    - First, apply all metadata filters (Name, Size, Time) using VFS.
    - For remaining candidates, perform actual disk I/O (`read_file`) to check content.
    - Caution: This blocks the Eio loop. Must run in a separate domain or thread pool to avoid stalling other queries/watcher.

### [NEW] [lib/quasifind/cache.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/cache.ml)

- **Persistence**:
  - `save : Vfs.t -> string -> unit` (Serialize VFS to file).
  - `load : string -> Vfs.t` (Deserialize).
  - Format: Binary (Marshal) or custom compact format.

## Phase 5: CLI Cleanup

### [MODIFY] [bin/main.ml](file:///Users/atsushi/OCaml/quasifind/bin/main.ml)

- **Option Validation**:
  - When `--daemon` is active, warn if `follow_symlinks` or `include_hidden` differs from daemon config.
  - Implement `--exec` locally: Client receives paths, then runs command on them.

## Goal Description (Phase 1 & 2 Archive)

Enhance the VFS with string interning for memory efficiency, and integrate the `Watcher` module to update the VFS in real-time based on filesystem events.

## User Review Required

> [!NOTE]
> Phase 2 focuses on memory optimization and real-time updates. ART (Adaptive Radix Tree) is deferred to a later phase.

## Proposed Changes

### [MODIFY] [lib/quasifind/vfs.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/vfs.ml) (Virtual File System)

- **String Interning**: Implement a simple hashconsing mechanism for path components (filenames and directory names) to reduce memory usage.
  - Use `Weak` hash table or a global string pool.
- _Refactor_: Ensure all strings stored in the Trie are interned.

### [MODIFY] [lib/quasifind/daemon.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/daemon.ml)

- **Initial Scan Optimization**:
  - Use `Traversal` module (Quasifind's own engine) instead of `find`.
  - Automatically set parallelism (`jobs`) to `Domain.recommended_domain_count ()` to maximize speed.
  - Implement a callback adapter to feed `Traversal` results directly into `Vfs.insert`.
- **Watcher Integration**:
  - Use `Watcher.watch` (or a modified version) to listen for FSEvents/inotify.
  - Map Watcher events (`New`, `Modified`, `Deleted`) to `Vfs.insert` and removal operations.
  - Ensure thread safety: protect `Vfs` updates with `Eio.Mutex` or use an `Atomic` reference (since VFS is immutable).

### [NEW] [lib/quasifind/intern.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/intern.ml) (Optional)

- Dedicated module for string interning if logic becomes complex. For now, can be inside `Vfs`.

## Verification Plan

### Automated Tests

- **Interning Test**: Verify that identical strings share the same physical address (using `==`).
- **Live Update Test**: Start daemon, create/delete files externally, query VFS to see if it updates.

### Manual Verification

- `dune exec bin/main.exe -- daemon`
- `touch test_file`
- Check daemon logs for "VFS updated".
