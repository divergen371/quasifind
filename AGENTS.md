# quasifind ワークスペースルール (OCaml 5.5.x + Zig 0.17.x + Dune)

## 1. ツールチェーン前提
- **OCaml**: `5.5.x` (`opam exec --` 経由で実行)
- **Dune**: `3.25+`
- **Zig**: `0.17.x`

## 2. Zig 0.17 FFI スタブ実装規約 (`lib/quasifind/*.zig`)
1. **`@cImport` / `@cInclude` の使用禁止**:
   - Zig 0.17 では `@cImport` が廃止されているため使用しないこと。
   - OCaml C API (`caml/*`) および OS (POSIX / Darwin) の型・定数・関数は、各 `.zig` ファイル内の `const c = struct { ... };` に `extern "c"` および `extern struct` を用いて明示的に定義すること。
2. **ヘッダ仕様の事前確認**:
   - 構造体（`dirent`, `stat`, `attrlist`, `regex_t`, `regmatch_t`, `pthread_mutex_t`, `custom_operations` 等）を追加・変更する場合は、推測で定義せず、必ず以下の実ヘッダを確認すること：
     - OCaml ヘッダ: `$(opam var lib)/ocaml/caml/` (`mlvalues.h`, `custom.h`, `alloc.h`, `memory.h`, `fail.h`, `signals.h`, `unixsupport.h`)
     - macOS SDK ヘッダ: `$(xcrun --show-sdk-path)/usr/include/`
3. **macOS Apple Silicon (`aarch64-macos`) の ABI 規約**:
   - `aarch64-macos` では `__DARWIN_ONLY_64_BIT_INO_T = 1` かつ `__DARWIN_ONLY_UNIX_CONFORMANCE = 1` であるため、`$INODE64` や `$UNIX2003` サフィックスは付与せず標準シンボル名（`opendir`, `readdir`, `fstat`, `fstatat`, `regcomp` 等）を使用すること。
   - `struct stat` の更新時刻は `st_mtimespec.tv_sec` を参照すること。
4. **`std.posix` 依存の抑制**:
   - Zig 0.17 では `std.posix.write` 等が削除されているため、FFI スタブ内のシステムコールは `const c` 内の `extern "c"` 宣言（`c.write`, `c.open`, `c.close` 等）を使用すること。

## 3. Dune ビルド設定規約 (`lib/dune`)
1. **`zig cc` における `--sysroot` と `-F` の併用注意**:
   - `zig cc` に `--sysroot $(xcrun --show-sdk-path)` を渡す際、Zig 0.17 は `-F` のパスに対して自動的に `--sysroot` を前置する。
   - そのため、`-F $(xcrun --show-sdk-path)/System/Library/Frameworks` ではなく、必ず `-F /System/Library/Frameworks` を指定すること（二重パス化によるフレームワーク未検出を防ぐため）。
