---
id: TASK-19
title: 'Chore / Hygiene: 孤立ファイル・一時ファイル・旧ツールチェーン設定・odoc警告・ベンチスクリプト整理'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - chore
  - cleanup
  - odoc
  - toolchain
milestone: m-2
dependencies: []
references:
  - lib/quasifind.ml
  - lib/quasifind/art.mli
  - lib/quasifind/exec.mli
  - test_file_phase2_live_update.txt
  - task.md
  - compile_flags.txt
  - .vscode/settings.json
  - .vscode/c_cpp_properties.json
  - bench/test.ml
  - bench/bench_content.sh
  - bench/experiment_parallel.sh
  - etc/repro_depth.sh
  - https://github.com/divergen371/quasifind/issues/19
priority: medium
type: chore
ordinal: 19000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ビルド対象外の壊れたファイル、一時ファイル、旧環境設定、odoc マークアップの不備を一掃する。

観測事実:
1. `lib/quasifind.ml`: `lib/dune` の `(modules ...)` に含まれずビルド対象外で、存在しない `Typed` モジュールを参照している孤立ファイル。
2. `lib/quasifind/art.mli` (L8, L14-24): 「内部構造は隠蔽されている」と書きつつ具体型を公開している矛盾。`lib/quasifind/exec.mli` (L8, L20, L32, L35): `"[{}]"` 記述が odoc 記法と衝突する恐れ。`lib/dune` の `(documentation)` スタンザおよび `dune build @doc` の警告確認が必要。
3. 一時ファイル・旧タスク: ルートの `test_file_phase2_live_update.txt` (0B, git追跡中)、旧 `task.md` (Backlog へ移行済み)、`etc/` や `bench/results/` 内の 0 バイトファイル・古いバイナリ生成物 (`etc/repro_*`)。
4. 旧ツールチェーン/CLI参照: `compile_flags.txt`, `.vscode/settings.json`, `.vscode/c_cpp_properties.json` が `5.4.0` を参照。`bench/test.ml` が存在しない `VStr` 等を参照しコンパイル不能。`bench/bench_content.sh`, `bench/experiment_parallel.sh`, `etc/repro_depth.sh` が旧 `-j 8` / `-j 2` を使用。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 孤立ファイル lib/quasifind.ml および一時ファイル test_file_phase2_live_update.txt 等の不要ファイルが整理・削除されること
- [ ] #2 dune build @doc が警告/エラーゼロで成功するよう .mli の odoc コメントが整備されること
- [ ] #3 compile_flags.txt と .vscode/* が OCaml 5.5.2 環境に整合し、bench/* スクリプトが現行 -j フラグで動作すること
<!-- AC:END -->
