---
id: TASK-17
title: 'Docs: README.md・Usage-Guide.md と実装の仕様乖離を一括解消'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - docs
  - cli
milestone: m-2
dependencies: []
references:
  - README.md
  - docs/wiki/Usage-Guide.md
  - bin/main.ml
  - https://github.com/divergen371/quasifind/issues/17
priority: medium
type: docs
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ユーザー向けドキュメント (`README.md`, `docs/wiki/Usage-Guide.md`) と現行実装 (`bin/main.ml`, `parser.ml`, `typecheck.ml`) の間に多数の仕様矛盾が存在する。

観測事実:
1. `-j` オプション: `README.md` (L70, L77, L83, L84, L260, L266, L272, L306, L384) と `Usage-Guide.md` (L76, L121) が旧仕様 `-j 8` / `-j N` / `--jobs=JOBS` のまま残っており、`README.md` L91 の「コア数指定を廃止」と同一ファイル内でも矛盾している（現行 `bin/main.ml` L537 はブールフラグ）。
2. Watcher 通知オプション名: `README.md` (L399-401) は `--webhook`, `--email`, `--slack` と記載しているが、実装 (`bin/main.ml` L546-548) は `--notify-url`, `--notify-email`, `--slack-webhook`。
3. Daemon 管理コマンド: `README.md` (L431) は `quasifind stats --daemon`、`Usage-Guide.md` (L96) は `quasifind daemon start` と記載しているが、実装 (`bin/main.ml` L604-646) は `quasifind daemon` / `quasifind daemon stats` / `quasifind daemon stop`。
4. その他乖離: `README.md` L103-108/L158（シンタックスシュガー未実装・ignore 未実装記述）、L315（`suid`/`sgid` 記載）、L445 / `Usage-Guide.md` L64（`(?i)` や単位 `K, M, G` の差異）、L463（`ignore` の `**/*.o` 例示）、L512-534（テスト数・実態とのズレ）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 README.md および docs/wiki/Usage-Guide.md の全 CLI オプション・サブコマンド例が現行実装と一致すること
- [ ] #2 DSL フィールド・単位・正規表現・ignore・テストカバレッジ表の記述が実装と一致すること
<!-- AC:END -->
