---
id: TASK-1
title: 'Zig FFI (dirent_stubs/fsevents_stubs): OCaml GCルート漏れ・未初期化配列・境界チェック欠落の修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T16:10:00Z'
labels:
  - zig-ffi
  - memory-safety
  - bug
milestone: m-0
dependencies: []
references:
  - lib/quasifind/fsevents_stubs.zig
  - lib/quasifind/dirent_stubs.zig
  - https://github.com/divergen371/quasifind/issues/1
priority: high
type: bug
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Zig FFI スタブ内に OCaml 5 GC 安全性違反およびメモリ安全性上の不具合が複数存在する。

観測事実:
1. fsevents_stubs.zig (L266-288 caml_fsevents_poll): `result` および `cons` が `caml_register_global_root` に登録されないままループ内で `caml_alloc(2, 0)` と `caml_copy_string` を呼んでおり、マイナー GC 発生時に移動・回収され UAF/セグフォの危険がある。
2. fsevents_stubs.zig (L192-194): stop 後の再 start で `init_fsevents()` により mutex を再初期化している。
3. dirent_stubs.zig (L411-435 caml_readdir_batch, L609-636 caml_readdir_bulk_stat): `caml_alloc(count, 0)` で確保した未初期化配列 `ocaml_arr` をルート登録した状態で `caml_copy_string` / `caml_alloc` を呼ぶため、GC が未初期化要素を辿る危険がある。
4. dirent_stubs.zig (L357-362): `readdir` エラー時の `c.uerror` 前に `results_arr[0..count]` の `strdup` 済み文字列を解放していない。
5. dirent_stubs.zig (L465-549 caml_readdir_bulk_stat): `getattrlistbulk` が `-1` を返してもエラー通知せず終了し、`attrBuf` 読み出しに境界チェックや `namelen == 0` 時の NUL 終端保証がない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 fsevents_stubs.zig の caml_fsevents_poll で OCaml 値の全ポインタが適切にルート保護され、GC 下でもクラッシュしないこと
- [ ] #2 dirent_stubs.zig の caml_readdir_batch / caml_readdir_bulk_stat で確保直後の配列スロットが Val_unit 等で初期化された上で後続アロケーションを行うこと
- [ ] #3 readdir エラーパスで strdup 済みメモリが確実に free されること
- [ ] #4 getattrlistbulk の異常終了ハンドリングおよび attrBuf パースの境界・NUL終端チェックが実装されていること
- [ ] #5 fsevents_stubs.zig で stop 後の再 start 時に初期化済み mutex が再初期化されず、複数回の start/stop サイクルが安全に動作すること
<!-- AC:END -->
