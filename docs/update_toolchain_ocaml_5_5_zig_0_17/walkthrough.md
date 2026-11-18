# 修正内容の確認 (Walkthrough): OCaml 5.5.2 / Dune 3.25.0 / Zig 0.17.0 対応

## 1. 変更したファイル一覧

1. **プロジェクト・ドキュメント設定**
   - [dune-project](file:///Users/atsushi/OCaml/quasifind/dune-project): `(lang dune 3.21)` から `(lang dune 3.25)` に更新。
   - [quasifind.opam](file:///Users/atsushi/OCaml/quasifind/quasifind.opam): `dune` のバージョン制約を `>= "3.25"` に更新。
   - [README.md](file:///Users/atsushi/OCaml/quasifind/README.md): 前提環境の表記を OCaml `5.5.2` / Zig `0.17.x` に更新。
   - [AGENTS.md](file:///Users/atsushi/OCaml/quasifind/AGENTS.md): Zig 0.17 FFI スタブ実装規約および Dune ビルド設定規約を記載したワークスペースルールを新規作成。

2. **Zig 0.17.0 FFI スタブ**
   - [lib/quasifind/dirent_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/dirent_stubs.zig):
     - `@cImport` を廃止し、OCaml 5.5.2 C API（`value`, `caml_alloc`, `caml_alloc_small`, `caml_alloc_custom`, `caml_copy_string`, `caml_enter_blocking_section`, `caml_leave_blocking_section`, `uerror` 等）および Darwin `aarch64-macos` の `dirent` (1048 bytes)、`attrlist` (24 bytes)、`stat` (144 bytes)、`timespec` を `const c` に明示定義。
     - `st.st_mtime` の参照を `st.st_mtimespec.tv_sec` に更新し、`custom_operations` の未指定関数ポインタ初期値を `null` に統一。
   - [lib/quasifind/search_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/search_stubs.zig):
     - `@cImport` を廃止し、OCaml C API・POSIX `stat` / `mmap` / `munmap` / `madvise`・POSIX 正規表現 (`regex_t`, `regmatch_t`, `regcomp`, `regexec`, `regfree`) を `const c` に明示定義。
   - [lib/quasifind/fsevents_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/fsevents_stubs.zig):
     - `@cImport` を廃止し、OCaml C API・`pthread_mutex_t` (64 bytes) / `pthread_t`・CoreServices / FSEvents 関連の外部宣言を整理。
     - Zig 0.17 で削除された `std.posix.write` を `c.write(c.STDERR_FILENO, msg.ptr, msg.len)` に置換。

3. **Dune ビルド・テスト設定**
   - [lib/dune](file:///Users/atsushi/OCaml/quasifind/lib/dune#L60): `zig cc` に `--sysroot $(xcrun --show-sdk-path)` を渡す際のフレームワーク検索パスを `-F /System/Library/Frameworks` に修正し、SDK パスの二重連結を解消。
   - [test/dune](file:///Users/atsushi/OCaml/quasifind/test/dune#L77-L78): Cram テストがサンドボックス内で `quasifind` 実行ファイルを参照できるよう `(cram (deps %{bin:quasifind}))` を追加。

---

## 2. 検証結果

### 確認できたこと
- `opam exec -- dune build` が警告・エラーなしで成功すること（終了コード `0`）。
- `opam exec -- dune runtest` により、以下のテストがすべて通過すること（終了コード `0`）：
  - 単体テスト・プロパティテスト（計19スイート：`Rules`, `Ghost`, `Entropy`, `Quasifind`, `Suspicious`, `Properties`, `Exec`, `Profile`, `Qerror`, `Config`, `RuleConverter`, `History`, `Interactive`, `VFS`, `ART`, `IPC`, `Watcher`, `Content`, `Traversal`）
  - Cram 統合テスト（[test_ls.t](file:///Users/atsushi/OCaml/quasifind/test/test_ls.t), [test_cli.t](file:///Users/atsushi/OCaml/quasifind/test/test_cli.t) の強制再実行 `--force` を含む）

### 未確認事項（自動テスト範囲外）
- FSEvents デーモンの長時間常駐監視や外部通知（Webhook / Email / Slack）の実送信、対話型 TUI (`fzf` 等) の実ターミナル操作。
