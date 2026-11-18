---
id: TASK-20
title: 'Daemon / FSEvents: ポーリング監視からFSEventsイベント駆動リアルタイム更新・複数ルート対応への移行'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - daemon
  - fsevents
  - watcher
  - enhancement
milestone: m-3
dependencies: []
references:
  - lib/quasifind/fsevents.ml
  - lib/quasifind/fsevents_stubs.zig
  - lib/quasifind/watcher.ml
  - lib/quasifind/daemon.ml
  - docs/daemon_experiment/future_improvements.md
  - https://github.com/divergen371/quasifind/issues/20
priority: medium
type: enhancement
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状の Daemon / Watcher は定期的な全ディレクトリポーリング (`Watcher.scan_files`) に依存しており、ビルド済みの `Fsevents` モジュールが未使用のデッドコードとなっている。

観測事実:
- lib/quasifind/fsevents.ml / fsevents_stubs.zig が実装・ビルドされているが、他のどのモジュールからも呼び出されていない。
- daemon.ml (L6, L75-106): `root = "."` 固定で、`config.daemon.roots` の複数ルート設定が使われていない（`future_improvements.md` #2, #4, #37）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Fsevents を利用したイベント駆動の差分 VFS 更新が Daemon に統合されること（フォールバックまたは定期整合と併用）
- [ ] #2 quasifind daemon コマンドおよび config.daemon.roots による複数ルートディレクトリ監視に対応すること
<!-- AC:END -->
