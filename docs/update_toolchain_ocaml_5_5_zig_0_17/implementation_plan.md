# 実装計画: OCaml 5.5.2 / Dune 3.25.0 / Zig 0.17.0 環境への更新

## 1. 目的と背景
開発環境のツールチェーン更新（OCaml `5.5.2`、Dune `3.25.0`、Zig `0.17.0`）に伴い、`quasifind` プロジェクトの設定ファイルおよび Zig FFI スタブを更新し、ビルドと全テストがエラーなく通過する状態にする。

## 2. 課題の整理（事実ベース）
1. **Dune バージョン定義**:
   - 現環境の Dune は `3.25.0` であるため、`dune-project` および `quasifind.opam` のバージョン指定を合わせる必要がある。
2. **Zig 0.17.0 における `@cImport` の廃止**:
   - Zig `0.17.0` では `@cImport` / `@cInclude` 組み込み関数が削除されており、`lib/quasifind/*.zig` のコンパイル時に `error: invalid builtin function: '@cImport'` が発生する。
3. **Zig 0.17.0 における `std.posix.write` の削除**:
   - `fsevents_stubs.zig` で使用していた `std.posix.write` および `std.posix.STDERR_FILENO` が Zig `0.17.0` の標準ライブラリから削除されている。
4. **`zig cc` における `--sysroot` と `-F` のパス解決変更**:
   - `lib/dune` で `zig cc` に `--sysroot $(xcrun --show-sdk-path)` と `-F $(xcrun --show-sdk-path)/System/Library/Frameworks` を同時に渡すと、Zig `0.17.0` が `-F` に対して `--sysroot` を自動前置するため SDK パスが二重になり、`CoreServices` フレームワークのリンクに失敗する。
5. **Dune 3.25 における Cram テストのサンドボックス依存**:
   - `test/test_ls.t` および `test/test_cli.t` で `quasifind` バイナリを呼び出す際、`test/dune` に `(cram (deps %{bin:quasifind}))` の宣言がないとサンドボックス内の `PATH` にバイナリが配置されず `quasifind: command not found` となる。

## 3. 変更方針

### 3.1 プロジェクト設定ファイル
- [dune-project](file:///Users/atsushi/OCaml/quasifind/dune-project): `(lang dune 3.25)` に更新。
- [quasifind.opam](file:///Users/atsushi/OCaml/quasifind/quasifind.opam): `"dune" {>= "3.25"}` に更新。
- [README.md](file:///Users/atsushi/OCaml/quasifind/README.md): OCaml `5.5.2`、Zig `0.17.x` の記載に更新。

### 3.2 Zig FFI スタブ (`lib/quasifind/*.zig`)
- 実環境のヘッダ（`/Users/atsushi/.opam/5.5.2/lib/ocaml/caml/*.h` および `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/usr/include/`）に基づき、各 `.zig` ファイル内の `const c = struct { ... };` に `extern "c"` 関数および `extern struct` を明示的に定義する。
- `aarch64-macos` では `__DARWIN_ONLY_64_BIT_INO_T = 1` かつ `__DARWIN_ONLY_UNIX_CONFORMANCE = 1` であるため、`$INODE64` や `$UNIX2003` サフィックスは付与せず標準 C シンボル名を使用する。
- 対象ファイル：
  - [lib/quasifind/dirent_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/dirent_stubs.zig)
  - [lib/quasifind/search_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/search_stubs.zig)
  - [lib/quasifind/fsevents_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/fsevents_stubs.zig)

### 3.3 Dune ビルド・テスト定義
- [lib/dune](file:///Users/atsushi/OCaml/quasifind/lib/dune): `fsevents_stubs` の共有ライブラリ生成ルールにて `-F /System/Library/Frameworks` を指定。
- [test/dune](file:///Users/atsushi/OCaml/quasifind/test/dune): `(cram (deps %{bin:quasifind}))` を追加。

### 3.4 ワークスペースルールの保存
- [AGENTS.md](file:///Users/atsushi/OCaml/quasifind/AGENTS.md): 今後の変更時に `@cImport` や重複 `-F` パス等を再導入しないよう規約を明文化。
