# Changelog

All notable changes to this project will be documented in this file.

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
