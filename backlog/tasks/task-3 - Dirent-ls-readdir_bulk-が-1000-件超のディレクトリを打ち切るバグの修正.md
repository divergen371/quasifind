---
id: TASK-3
title: 'Dirent (--ls): readdir_bulk が 1000 件超のディレクトリを打ち切るバグの修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - dirent
  - cli
  - bug
milestone: m-0
dependencies: []
references:
  - lib/quasifind/dirent.ml
  - lib/quasifind/dirent_stubs.zig
  - bin/main.ml
  - https://github.com/divergen371/quasifind/issues/3
priority: high
type: bug
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
--ls / --list で使用する Dirent.readdir_bulk が、1001 件以上のエントリを含むディレクトリで最初の 1000 件しか返さない。

観測事実:
- lib/quasifind/dirent_stubs.zig (L445, L464) の `caml_readdir_bulk_stat` は `BATCH_MAX = 1000` (および `SCAN_MAX = 4000`) でチャンク返却する設計になっている。
- しかし lib/quasifind/dirent.ml (L47-55) の `readdir_bulk` は `readdir_bulk_stat h` を 1 回だけ呼んで `closedir h` しており、残りのバッチを読み出すループが無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Dirent.readdir_bulk が空配列が返るまで readdir_bulk_stat を反復呼び出し、全エントリを結合して返すこと
- [ ] #2 1001 件以上のファイルを含むディレクトリに対する --ls テストで全件出力されること
<!-- AC:END -->
