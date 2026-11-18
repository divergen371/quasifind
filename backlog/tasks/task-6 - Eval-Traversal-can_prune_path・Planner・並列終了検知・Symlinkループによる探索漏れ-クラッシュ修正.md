---
id: TASK-6
title: 'Eval / Traversal: can_prune_path・Planner・並列終了検知・Symlinkループによる探索漏れ/クラッシュ修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - traversal
  - eval
  - parallel
  - bug
milestone: m-0
dependencies: []
references:
  - lib/quasifind/eval.ml
  - lib/quasifind/traversal.ml
  - https://github.com/divergen371/quasifind/issues/6
priority: high
type: bug
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
探索計画 (Planner)、枝刈り (can_prune_path)、並列終了検知、シンボリックリンク追跡に探索漏れおよびクラッシュを起こすバグが存在する。

観測事実:
1. eval.ml (L265-279 can_prune_path): `Path (StrRe (pattern, _))` のプレフィックス抽出が正規表現構文（`|`, `*`, `?`, `{`, `^`, `$` 等）および `./` プレフィックス正規化を考慮しておらず、`path =~ /src/lib/.*/` 等で `dir_norm` (`./src`) と `prefix` (`src/lib/`) が不一致になり探索漏れ (False Negative) を起こす。`Path (StrEq)` も絶対パス/`./` 混在で不整合がある。
2. traversal.ml (L30-40, L403-406 extract_start_path): `path == "src/foo.ml"` のようにファイルパスを指定すると、それをディレクトリとして `opendir` しようとし `Not a directory` 警告を出して 0 件になる。
3. traversal.ml (L73-101 try_extract_suffix): `name =~ /foo|bar\.ml$/` の選択 `|` や `name =~ /(?i).*\.ml$/` の大文字小文字無視でも `".ml"` を必須サフィックスとして Zig 側へプッシュダウンし、マッチすべきファイルが誤除外される。
4. traversal.ml (L313-339 traverse_parallel): `attempt_steal` がランダム `2 * concurrency` 回しか試みないため、未処理タスクが他ワーカーのキューに残っていても全員が `idle_count == concurrency` に達し早期終了（探索漏れ）し得る。
5. traversal.ml (L202-208): `follow_symlinks = true` 時に `(st_dev, st_ino)` による循環検知が無く、ループするシンボリックリンクで無限再帰/クラッシュする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 can_prune_path が Path(StrRe) / Path(StrEq) で探索漏れ (False Negative) を絶対に起こさない仕様へ修正されること
- [ ] #2 Planner.extract_start_path がファイルパス指定時に opendir 失敗で 0 件にならないこと
- [ ] #3 Planner.extract_suffixes が | や (?i) 等を含む正規表現で誤った必須サフィックスを抽出しないこと
- [ ] #4 traverse_parallel が未処理タスク残存中に早期終了しない決定的な終了検知を行うこと
- [ ] #5 follow_symlinks 時に visited inode 集合等で循環リンクを安全に検出しスキップすること
<!-- AC:END -->
