---
id: TASK-13
title: 'CLI / Interactive / Traversal / Config: 対話設定反映・ignoreグロブ・TUI幅・環境堅牢化'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - cli
  - interactive
  - traversal
  - config
  - bug
milestone: m-1
dependencies: []
references:
  - bin/main.ml
  - lib/quasifind/interactive.ml
  - lib/quasifind/traversal.ml
  - lib/quasifind/config.ml
  - lib/quasifind/watcher.ml
  - https://github.com/divergen371/quasifind/issues/13
priority: medium
type: bug
ordinal: 13000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI・対話UI・設定・無視パターンの細部における機能不整合とクラッシュ要因を解消する。

観測事実:
1. bin/main.ml (L266): `--interactive` 検索時に `config.fuzzy_finder` を無視して `Config.Builtin` をハードコードしている。
2. interactive.ml (L73-93, L268-274): `read_key` が 3 バイト以上の ANSI シーケンス（PageUp 等）の残余文字をクエリへ混入させる。また描画パディングが `String.length`（バイト数）基準のため日本語等マルチバイト文字で右ペイン境界が崩れる。
3. bin/main.ml (L129-130) & traversal.ml (L115): `should_visit` がベース名のみに `ignore_re` を適用するため `README.md` 例示の `**/*.o` 等のパスパターンが機能しない。不正な glob パターン時の例外処理も無い。
4. bin/main.ml (L114-119): `uname -s` を毎回サブシェル起動している。
5. config.ml (L123) / profile.ml (L44) / history.ml (L45) / rule_loader.ml (L67): `HOME` 未設定環境で `Not_found` によりクラッシュする。
6. watcher.ml (L165-170) / bin/main.ml: `config.heartbeat_url` および `--heartbeat-url` が CLI/Daemon から Watcher へ渡されていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 bin/main.ml の --interactive が config.fuzzy_finder を参照すること
- [ ] #2 TUI の read_key が複数バイトエスケープシーケンスを正しく消費し、描画幅計算が文字幅 (UTF-8/全角) を考慮すること
- [ ] #3 ignore パターンがパス全体パターンにも対応し、不正 glob 指定時に適切なエラーメッセージを出すこと
- [ ] #4 HOME 未設定時も安全にフォールバックし、heartbeat_url が CLI/Daemon の Watcher に接続されること
<!-- AC:END -->
