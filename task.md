# Quasifind Tasks

## Completed

- [x] **Core Features**
  - [x] Typed DSL (`size > 10MB`, `mtime < 7d`)
  - [x] Parallel Traversal (`Eio` + `Saturn`)
  - [x] Regex Support (PCRE path matching)
  - [x] Mmap Optimization for content search
  - [x] Interactive Mode & History
- [x] **Resilience Hardening**
  - [x] Heartbeat Monitoring
  - [x] Configuration Tamper Detection
  - [x] Binary Integrity Check
  - [x] Stealth Mode Improvements (macOS support)

## Active

- [ ] **Daemon Mode Experiment** (`experiment/daemon-mode`)
  - [ ] Phase 1: PoC (In-Memory Trie Structure)
  - [ ] Phase 2: Live Updates (Watcher Integration)
  - [ ] Phase 3: Client-Server IPC

## Backlog

- [ ] **Plugin System**: Allow Lua or Wasm plugins for custom file scoring
- [ ] **Distributed Search**: Search across multiple machines via SSH agent
