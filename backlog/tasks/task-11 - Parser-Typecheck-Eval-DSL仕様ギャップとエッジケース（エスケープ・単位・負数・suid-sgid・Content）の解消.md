---
id: TASK-11
title: >-
  Parser / Typecheck / Eval:
  DSL仕様ギャップとエッジケース（エスケープ・単位・負数・suid/sgid・Content!=）の解消
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - dsl
  - parser
  - typecheck
  - eval
  - bug
milestone: m-1
dependencies: []
references:
  - lib/quasifind/parser.ml
  - lib/quasifind/typecheck.ml
  - lib/quasifind/eval.ml
  - https://github.com/divergen371/quasifind/issues/11
priority: medium
type: bug
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DSL パーサ・型検査・評価器に仕様との不一致およびエッジケースの不具合がある。

観測事実:
1. parser.ml (L43-45 quoted_string): `\n`, `\t`, `\r` を実際の改行/タブ/CR ではなく 2 文字のリテラル `"\\n"`, `"\\t"`, `"\\r"` として返しているため、改行やタブを含む文字列比較ができない。
2. parser.ml (L18-38, L76-93, L134-135): 負数のパース非対応、`true`/`false` の単語境界未チェック、`README.md` / `Usage-Guide.md` / `bin/main.ml` (L532) に記載のある単位 (`K`, `M`, `G`, `+1M` 等) が未実装。
3. typecheck.ml (L112-121): `README.md` (L315) に記載の `suid`, `sgid` フィールドが未実装 (`Unknown field` エラー)。また L32-42 `normalize_size` に Int64 乗算オーバーフロー検査が無く、L69 で `Int64.to_int` 経由変換、L13 の未使用例外 `TypeError` が残存している。
4. eval.ml (L110-117): `Content (StrNe ...)` でファイルオープン/mmap 失敗 (`Fallback -> None`) 時に `true` を返しており、読込エラーを一致条件成立として扱っている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 quoted_string の \n, \t, \r エスケープが実際の制御文字へデコードされること
- [ ] #2 suid / sgid フィールドおよびドキュメント記載の単位系について実装追加または仕様統一が行われること
- [ ] #3 size 正規化の Int64 オーバーフロー検査と適切なエラー返却、未使用コード整理が行われること
- [ ] #4 Content (StrNe) でファイル読込不能時に false かつエラー/警告扱いとなり、正常値へ誤変換しないこと
<!-- AC:END -->
