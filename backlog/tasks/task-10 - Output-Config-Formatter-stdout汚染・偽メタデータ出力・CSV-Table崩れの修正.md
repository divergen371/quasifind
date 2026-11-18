---
id: TASK-10
title: 'Output / Config / Formatter: stdout汚染・偽メタデータ出力・CSV/Table崩れの修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - formatter
  - config
  - cli
  - bug
milestone: m-1
dependencies: []
references:
  - lib/quasifind/config.ml
  - lib/quasifind/rule_loader.ml
  - lib/quasifind/formatter.ml
  - bin/main.ml
  - https://github.com/divergen371/quasifind/issues/10
priority: medium
type: bug
ordinal: 10000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
標準出力のフォーマット整合性および出力時のメタデータ取得に複数の不具合がある。

観測事実:
1. config.ml (L161) / rule_loader.ml (L94): 初回のデフォルトファイル自動生成時に `"Created default config at ..."` / `"Created default rules at ..."` を標準出力 (`Printf.printf`) に出しており、`--format json` や `--ls` の出力を破壊する。
2. bin/main.ml (L242) / traversal.ml (L106): `--format json/csv/table` 指定時や `--color` の実行可能判定 (`is_executable`) 時でも、`Eval.requires_metadata` が false だと `lstat` を省略するため、`size = 0`, `mtime = 1970-01-01`, `perm = ---------` という偽のメタデータが出力される。
3. formatter.ml (L96-105): CSV 出力に RFC 4180 のカンマ/ダブルクォート/改行エスケープが無く、Table 出力は ANSI カラーコードのバイト長を含めて `%-60s` パディングするため色付き行だけ列幅が崩れる。
4. bin/main.ml (L136-137, L252): 不正な `--format` / `--color` 引数がエラー・警告なくデフォルトにフォールバックし、`--interactive --format json` 併用時は開始 `[` だけ出力され閉じ `]` が出ない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Config.load / Rule_loader.load_rules の初回生成通知が stderr に出力（またはサイレント化）され、stdout の検索結果・JSON/CSV を汚染しないこと
- [ ] #2 --format json/csv/table または --color always/auto で実行権限色分けが必要な場合に Traversal の stat が有効化され実メタデータが出力されること
- [ ] #3 Formatter の CSV 出力が RFC 4180 準拠でエスケープされ、Table 出力が ANSI エスケープ長を除外した表示幅で整列すること
- [ ] #4 不正な --format / --color 値に対して明確なエラーを返し、--interactive 併用時の JSON 出力破綻を防止すること
<!-- AC:END -->
