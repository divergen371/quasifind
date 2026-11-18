---
id: TASK-22
title: 'Performance / Engine: ストリーミング結果出力・Intern LRU・永続AC / Teddy SIMD / Lazy DFA 検討'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - performance
  - simd
  - engine
  - enhancement
milestone: m-3
dependencies: []
references:
  - bin/main.ml
  - lib/quasifind/intern.ml
  - lib/quasifind/search_stubs.zig
  - docs/design/search_engine_evolution.md
  - docs/daemon_experiment/future_improvements.md
  - https://github.com/divergen371/quasifind/issues/22
priority: low
type: enhancement
ordinal: 22000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
大規模ディレクトリでのメモリ効率と検索スループットをさらに引き上げる最適化群 (`future_improvements.md` #30, #32, #34, #35, #36 および `search_engine_evolution.md`)。

観測事実:
- bin/main.ml (L158): `all_found_paths` に全ヒットパスを蓄積するため 100 万件ヒット時にメモリ圧迫する。
- intern.ml (L4-35): 2世代切替のみで LRU ではなく、切替時に全エントリが一気に古い世代へ移る。
- search_stubs.zig: 検索ごとに `ac_lite_t` をスタック上に構築しており、複数パターン同時検索や `Custom_tag` によるエンジン永続化、Teddy SIMD / Lazy DFA が未実装。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 通常検索時の完全ストリーミング処理（メモリ上に全結果リストを保持しないオプション/設計）が実装されること
- [ ] #2 複数キーワード検索や永続化 AC エンジン (Custom_tag) / Teddy SIMD のプロトタイプ評価と実装判断が完了すること
<!-- AC:END -->
