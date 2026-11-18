---
id: TASK-4
title: 'Rule_loader: save_rules の JSON 二重書き込みによる rules.json 破損の修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - rules
  - persistence
  - bug
milestone: m-0
dependencies: []
references:
  - lib/quasifind/rule_loader.ml
  - https://github.com/divergen371/quasifind/issues/4
priority: high
type: bug
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
カスタム検出ルールを保存する `Rule_loader.save_rules` が同じ JSON を 2 回連続で書き込んでいるため、生成された `rules.json` が不正な JSON となり次回以降の読み込みが必ず失敗する。

観測事実:
- lib/quasifind/rule_loader.ml (L80-81):
  `Yojson.Basic.to_channel oc json;`
  `Yojson.Basic.to_channel oc json;`
  と重複記述されている。
- これにより `--update-rules` や初回 `load_rules ()` / `--reset-rules` で保存された `rules.json` は `{...}{...}` 形式になり、`Yojson.Basic.from_file` が例外を起こして `load_rules ()` が `None` を返す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Rule_loader.save_rules の重複する to_channel 呼び出しを削除し、有効な単一 JSON（末尾改行付き等）が書き込まれること
- [ ] #2 save_rules 後に load_rules で同じ rule_set が復元できる往復ユニットテストが追加・通過すること
<!-- AC:END -->
