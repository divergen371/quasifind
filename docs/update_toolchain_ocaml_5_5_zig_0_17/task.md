# タスクリスト: OCaml 5.5.2 / Dune 3.25.0 / Zig 0.17.0 環境への更新

- [x] プロジェクト設定・ドキュメントのバージョン更新
  - [x] [dune-project](file:///Users/atsushi/OCaml/quasifind/dune-project) の `(lang dune ...)` を `3.25` に更新
  - [x] [quasifind.opam](file:///Users/atsushi/OCaml/quasifind/quasifind.opam) の `dune` 依存バージョンを `>= "3.25"` に更新
  - [x] [README.md](file:///Users/atsushi/OCaml/quasifind/README.md) の推奨環境表記を OCaml `5.5.2` / Zig `0.17.x` に更新
- [x] Zig 0.17.0 対応（FFI スタブの修正）
  - [x] OCaml 5.5.2 C ヘッダおよび macOS SDK ヘッダ (`aarch64-macos`) の構造体・シンボル仕様確認
  - [x] [lib/quasifind/dirent_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/dirent_stubs.zig) の `@cImport` を明示的な `extern "c"` / `extern struct` 定義に置換
  - [x] [lib/quasifind/search_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/search_stubs.zig) の `@cImport` を明示的な `extern "c"` / `extern struct` 定義に置換
  - [x] [lib/quasifind/fsevents_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/fsevents_stubs.zig) の `@cImport` および廃止された `std.posix.write` を明示的な `extern "c"` 定義に置換
- [x] ビルド・テスト設定の修正と検証
  - [x] [lib/dune](file:///Users/atsushi/OCaml/quasifind/lib/dune) における `zig cc` の `--sysroot` と `-F` パス重複問題を修正（`-F /System/Library/Frameworks`）
  - [x] [test/dune](file:///Users/atsushi/OCaml/quasifind/test/dune) に Cram テスト用のバイナリ依存 `(cram (deps %{bin:quasifind}))` を追加
  - [x] `opam exec -- dune build && opam exec -- dune runtest` の通過確認
- [x] ワークスペースルールの永続化とリポジトリ反映
  - [x] [AGENTS.md](file:///Users/atsushi/OCaml/quasifind/AGENTS.md) の作成
  - [x] コミットおよび `origin/main` へのプッシュ
