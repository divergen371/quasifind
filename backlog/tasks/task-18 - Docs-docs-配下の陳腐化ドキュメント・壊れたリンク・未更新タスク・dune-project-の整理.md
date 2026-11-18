---
id: TASK-18
title: 'Docs: docs/ 配下の陳腐化ドキュメント・壊れたリンク・未更新タスク・dune-project の整理'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - docs
  - cleanup
milestone: m-2
dependencies: []
references:
  - docs/Proposal.md
  - docs/daemon_experiment/task.md
  - docs/daemon_experiment/implementation_plan.md
  - docs/daemon_experiment/future_improvements.md
  - docs/resilience_hardening/task.md
  - docs/mli_interfaces_and_odoc/task.md
  - docs/interactive_search/implementation_plan.md
  - docs/cli_syntax_sugar_plan.md
  - docs/cli_syntax_sugar_design/implementation_plan.md
  - docs/stub_rewrite_plan/plan.md
  - dune-project
  - quasifind.opam
  - https://github.com/divergen371/quasifind/issues/18
priority: low
type: docs
ordinal: 18000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
設計・履歴ドキュメント群およびプロジェクトメタデータの整合性を整理する。

観測事実:
1. 壊れたリンク/空ディレクトリ:
   - `docs/daemon_experiment/implementation_plan.md` (L60): 存在しない `lib/quasifind/cache.ml` を参照。
   - `docs/interactive_search/implementation_plan.md` (L26): 存在しない `README.ja.md` を参照。
   - `docs/interactive_search_feature`: 空ディレクトリのまま残存。
2. 古い前提・矛盾:
   - `docs/stub_rewrite_plan/plan.md`, `docs/fix_header_error/*`, `docs/parallel_tuning_and_deduplication/walkthrough.md`, `docs/design/search_engine_evolution.md` 等に廃止済み `stealth_stubs.c`, `@cImport`, OCaml `5.4.0`, C スタブ前提が混在。
   - `docs/cli_syntax_sugar_plan.md` が未実装の将来構想のまま残存し、`docs/cli_syntax_sugar_design/implementation_plan.md` (L33) の `-i, --iname` や `walkthrough.md` (L22) の表記が実装と不一致。
   - `docs/daemon_experiment/task.md` (L71) / `walkthrough.md` (L165) の「37 items」が `future_improvements.md`（39項目）と不一致。
   - `docs/linux_build_attempt_rollback/implementation_plan.md`・`task.md` に先行タスク内容が混入。
3. 未更新チェックボックス: `docs/resilience_hardening/task.md` (L3-23), `docs/mli_interfaces_and_odoc/task.md` (L4-10, L29 stealth.mli), `docs/daemon_experiment/task.md` (L43)。
4. `dune-project` (L10-18, L39-40) / `quasifind.opam`: `username/reponame`, `Author Name <author@example.com>`, `https://url/to/documentation` 等のプレースホルダーが残存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 壊れたファイルリンクおよび空ディレクトリ docs/interactive_search_feature が修正/整理されること
- [ ] #2 過去の履歴ドキュメントと現行設計の区別（アーカイブ注記や前提更新）およびチェックボックス同期が完了すること
- [ ] #3 dune-project（および生成される quasifind.opam）の著者・リポジトリ・タグ等のメタデータが適切な値へ更新されること
<!-- AC:END -->
