# Changelog

All notable changes to this project will be documented in this file.

## [Unreleased]

### Features

- **Resilience**: Added Heartbeat monitoring to detect process termination (`--notify-url` or `heartbeat_url` in config).
- **Integrity**: Implemented configuration tamper detection (automatically alerts if `config.json` is modified).
- **Integrity**: Added `--integrity` / `-I` flag to verify the binary checksum.

### Fixes

- **Stealth Mode**: Changed default masked process name on macOS to `syslogd` (from `[kworker/0:0]`) to appear less suspicious.

## [1.0.1] - 2026-02-03

### Fixes

- **Stealth Mode**: Improved process hiding on macOS by properly overwriting `argv[0]` and clearing subsequent arguments.
- **Timestamp Wiping**: Fixed `atime` restoration logic to ensure file access timestamps are preserved even when using the optimized mmap search path.
- **Watcher Notification**: Fixed an issue where the watcher would not report file modifications in the CLI due to missing metadata key optimization.

## [1.0.0] - 2026-02-01

First major release of Quasifind!

### Features

- **Typed DSL**: Support for complex queries (`size > 10MB && mtime < 7d`) with type safety.
- **Parallel Traversal**: Multicore file system traversal using `Eio` and work-stealing for high performance.
- **Regex Support**: PCRE-compatible regex matching for filenames and paths.
- **Interactive Mode**: History browsing and command execution.
- **Stealth Mode**: Process name masking and timestamp restoration capabilities.
- **Suspicious Mode**: Heuristic detection for dangerous or hidden files.

### Optimizations

- **Mmap & Zero-Copy Regex**: Implemented `mmap`-based search for `content =~ /.../` queries, achieving ~8x CPU efficiency (vs legacy read) and ~2x IO throughput improvements on large files.
- **Lazy Stat**: Avoid `lstat` calls when metadata is not required by the query.
- **Dirent d_type**: Utilize `d_type` from `readdir` to skip unnecessary `stat` calls during traversal.

### Fixes

- Fixed `StrRe` constructor usage in traversal logic to correctly ignore regex source strings during planning.
