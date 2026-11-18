---
id: TASK-12
title: 'Ghost / Suspicious / Rule_converter: --check-ghost のパス一致・走査漏れ修正とルール更新の堅牢化'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - ghost
  - suspicious
  - rules
  - bug
milestone: m-1
dependencies: []
references:
  - lib/quasifind/ghost.ml
  - lib/quasifind/suspicious.ml
  - lib/quasifind/rule_converter.ml
  - bin/main.ml
  - https://github.com/divergen371/quasifind/issues/12
priority: medium
type: bug
ordinal: 12000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セキュリティ調査機能 (--check-ghost, --suspicious, --update-rules) に動作不能・誤検出リスクがある。

観測事実:
1. ghost.ml (L18-19): `root = "."` のとき `abs_root` が `"/cwd/."` となり、`lsof` の実パスに `String.starts_with` が一切一致しない。また L12 で空白分割の末尾要素のみ取るためスペースを含むパスが破損する。
2. bin/main.ml (L382-383): `--check-ghost` 単体実行時に `run_logic Ast.Typed.False` を呼び出しており、不要なディレクトリ全走査と空結果の History 記録が発生する。
3. bin/main.ml (L295) / suspicious.ml (L5): `hidden_exec` がドット始まりのファイル名を検査するにもかかわらず、`--suspicious` 単体では `include_hidden = false` のまま走査されるため `hidden_exec` が絶対に検出されない。
4. rule_converter.ml (L4-29): `curl -sL` に `-f` (`--fail`) が無く HTTP 404/500 ページも成功扱いして正規表現化する。さらに取得リストが空のとき `name =~ /()$/` / `name =~ /^()$/` を生成し、エラー時には `temp_file` が削除されずリークする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Ghost.scan が root="." や末尾スラッシュ付きパスを正規化し、空白を含むパスでも正しく抽出できること
- [ ] #2 --check-ghost 単体実行時に不要なファイルシステム走査を行わないこと
- [ ] #3 --suspicious 実行時に hidden_exec を含めて意図通り検出できるよう include_hidden の扱いが修正・明文化されること
- [ ] #4 Rule_converter が HTTP エラー (--fail) および空リストを拒否し、temp_file を確実にクリーンアップすること
<!-- AC:END -->
