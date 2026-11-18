---
id: TASK-15
title: >-
  Tests: 既存テストの偽陽性修正と未カバーモジュール (Formatter/Dirent/Rule_loader/Fsevents/Daemon)
  のテスト追加
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T16:10:00Z'
labels:
  - tests
  - quality
milestone: m-2
dependencies: []
references:
  - test/test_traversal.ml
  - test/dune
  - lib/quasifind/formatter.ml
  - lib/quasifind/dirent.ml
  - lib/quasifind/rule_loader.ml
  - lib/quasifind/fsevents.ml
  - lib/quasifind/daemon.ml
  - https://github.com/divergen371/quasifind/issues/15
priority: high
type: task
ordinal: 15000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既存テストの偽陽性問題およびユニット/統合テストの重大なカバレッジ欠落を解消する。

観測事実:
1. test/test_traversal.ml (L472-506 test_loop_termination): `with _ -> ()` で Stack_overflow や Eio エラーを握りつぶしており、シンボリックリンク循環クラッシュを隠蔽する偽陽性テストになっている。
2. test/test_traversal.ml (L446-470 test_preserve_timestamps): `Traversal.traverse` 単体では `lstat` しか行わないため `atime` 保存の実証になっていない。
3. 以下のモジュールに専用ユニットテストが一切存在しない:
   - `Formatter` (JSON/CSV/Table/Null/Color のエスケープと整列)
   - `Dirent` (`iter_batch` および 1000 件超 `readdir_bulk`)
   - `Rule_loader` (`save_rules` -> `load_rules` 往復テストが無いことが二重書き込みバグを見逃した原因)
   - `Fsevents` (macOS FSEvents start/poll/stop 基本動作)
   - `Daemon` (起動・ライブ更新・IPC検索・stats・graceful stop の E2E 統合テスト)
4. `Interactive` / `Watcher` / `Ghost` はスモークテストまたはモック文字列テストのみで実動作・エラー系テストが不足している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 test_loop_termination から with _ -> () を撤去し、循環リンクで例外なく終了かつ二重走査しないことを検証すること
- [ ] #2 Formatter, Dirent (1000件超含む), Rule_loader (保存・読込往復), Fsevents のユニットテストが test/dune に追加され通過すること
- [ ] #3 Daemon の E2E 統合テスト（一時ディレクトリで起動→ファイル追加/変更/削除→IPC クエリ検証→stop）が追加され通過すること
- [ ] #4 test_preserve_timestamps が単体 lstat ではなく実際の内容読み取りまたはタイムスタンプ保持処理を含めて atime/mtime 保存を検証すること
- [ ] #5 Interactive / Watcher / Ghost について、モック文字列だけでなく実プロセス・異常系を含む実動作テストが追加され通過すること
<!-- AC:END -->
