---
id: TASK-16
title: 'Tests: 境界値・回帰・CLI E2Eテスト拡充 (Search SIMD/PCRE, Pruning, ART, Cram)'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - tests
  - cram
  - qcheck
milestone: m-2
dependencies: []
references:
  - test/test_cli.t
  - test/test_ls.t
  - test/test_props.ml
  - test/test_art.ml
  - test/test_content.ml
  - https://github.com/divergen371/quasifind/issues/16
priority: medium
type: task
ordinal: 16000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
境界値、回帰ケース、および CLI E2E テスト (Cram) の網羅性を強化する。

観測事実:
1. `test_content.ml`: Zig NEON SIMD (`search_stubs.zig`) の境界長（0, 1, 3, 4, 15, 16, 31, 32, 34, 4096 バイト等）や、PCRE メタ文字 (`\s`, `\d`, `\w`, `(?i)` 等) と OCaml Re の結果一致テストが無い。
2. `can_prune_path` / `Planner`: `path =~ /foo|bar/`, `name =~ /foo|bar\.ml$/`, `path == "a/b.ml"`, 大文字小文字無視 (`(?i)`) 等の探索漏れ回帰テストが無い。
3. `test_art.ml` / `test_vfs.ml`: `Large`→`Small` 縮小・再圧縮テストや `Vfs.split_path` の絶対パス/`./` テストが無い。
4. `test/test_cli.t`: シンタックスシュガー (`-n`, `--iname`, `-e`, `-t`, `-s`, `-m`, `-c`)、`--format` 各種、`--profile`/`--save-profile`、`--suspicious`、`--check-ghost`、`--integrity`、`history` の E2E テストが存在しない。また `test_ls.t` は 10 件程度のみで 1001 件以上のバッチ境界を検証していない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Search の SIMD 長さ境界・ページ境界および PCRE メタ文字一致テストが追加されること
- [ ] #2 can_prune_path / Planner の探索漏れ回帰テストおよび ART Large->Small 縮小テストが追加されること
- [ ] #3 test_cli.t / test_ls.t にシンタックスシュガー・出力形式・プロファイル・1001件超 --ls 等の Cram テストが追加されること
<!-- AC:END -->
