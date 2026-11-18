---
id: TASK-21
title: 'Daemon / Persistence: Marshal脱却と起動時差分同期・ソケット権限制御・ベンチマーク整備'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - daemon
  - vfs
  - security
  - enhancement
milestone: m-3
dependencies: []
references:
  - lib/quasifind/vfs.ml
  - lib/quasifind/ipc.ml
  - docs/daemon_experiment/future_improvements.md
  - https://github.com/divergen371/quasifind/issues/21
priority: low
type: enhancement
ordinal: 21000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Daemon のキャッシュ永続化、セキュリティ、および計測基盤を改善する (`future_improvements.md` #5, #6, #26, #27)。

観測事実:
- vfs.ml (L108-127): `Marshal` によりダンプしているため OCaml バージョン変更や型変更に対する耐性が無く、起動時のキャッシュ復元後にディスクとの差分同期（削除ファイル除去等）が初回スキャン前に整理されない。
- ipc.ml (L18-20): ソケット親ディレクトリは 0o700 だがソケット自体の権限モード・サンドボックス範囲制限オプションが未整備。
- デーモン性能の定期測定（初回スキャン時間 vs クエリ応答時間）の統合ベンチマーク整備が必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Vfs.save / load が Marshal 非依存の型安全・バージョン検証付きフォーマットへ移行されること
- [ ] #2 ソケット権限 (0o600/0o700) と設定可能な daemon_mode/sandbox 制限が整理されること
<!-- AC:END -->
