---
id: TASK-23
title: 'UX / Integration: GUIファイルマネージャー向け Hybrid IPC API・互換モード・拡張構想'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - feature
  - ipc
  - ux
  - architecture
milestone: m-3
dependencies: []
references:
  - docs/file_manager_architecture/requirements.md
  - docs/daemon_experiment/future_improvements.md
  - task.md
  - https://github.com/divergen371/quasifind/issues/23
priority: low
type: feature
ordinal: 23000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GUI ファイルマネージャーのバックエンドとしての統合 API および将来の拡張機能 (`requirements.md`, `future_improvements.md` #22, #25, #28, #29, `task.md`)。

対象候補:
- Hybrid IPC API (`list_dir` バルクスキャン, `search_interactive` ファジー検索ストリーミング, `fs_watch` Push 通知イベント)
- CLI UX 拡張（対話 REPL モード、大規模走査進捗表示、`--find-compat` / `--fd-compat`）
- 将来スパイク: プラグインシステム (Lua/Wasm)、SSH 経由分散検索
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GUI バックエンド向け IPC プロトコル (list_dir / search_interactive / fs_watch) の仕様確定とプロトタイプが実装されること
- [ ] #2 互換モード・REPL・プラグイン等の優先順位が Backlog 上で仕分け・決定されること
<!-- AC:END -->
