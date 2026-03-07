# Quasifind CスタブからZigへの完全移行 Tasks (Phase 4)

- [x] **Phase 4.1: OCaml 側の FFI シグネチャ設計**
  - [x] `dirent.ml` の `iter_batch` 関数シグネチャを変更し、フィルタ条件を受け取れるようにする。
  - [x] Zig 側の `caml_readdir_batch` スタブ関数シグネチャを追従。
- [x] **Phase 4.2: Zig 側高速フィルタリングの実装 (`dirent_stubs.zig`)**
  - [x] 渡された OCaml の文字列配列 (Array of string) を Zig のスライス配列としてパース。
  - [x] `std.mem.endsWith` 相当の文字列比較を C 次元で実行し、不要と判断したバッチエントリは `caml_alloc` せずにスキップ。
- [x] **Phase 4.3: OCaml 側のトラバーサル連動 (`traversal.ml`)**
  - [x] AST から名前ベースのフィルタリング条件 (`StrEndsWith`, `StrEq` 等) を抽出する関数の実装。
  - [x] 抽出した条件を `Dirent.readdir` 呼び出し時に渡す。
- [x] **Phase 4.4: 性能検証とデバッグ**
  - [x] 既存のテストスイートがプレフィルタリング導入後も機能するか検証。
  - [x] `run_benchmark.sh` 実行による `fd` との最終対決。

- [x] **Phase 5: 堅牢化と品質向上 (Hardening)**
  - [x] `strdup` 戻り値チェックとエラーハンドリングの追加。
  - [x] OCaml GC に伴うポインタ移動からの保護 (`caml_register_global_root`)。
  - [x] `fsevents` 状態フラグのデータ競合修正 (Atomic)。
  - [x] `pthread_create` 失敗時のリソースクリーンアップ実装。
  - [x] `fstat` 失敗時の未初期化メモリ参照バグ修正。
  - [x] `REG_STARTEND` 非互換環境（Linux等）へのフォールバック実装。
  - [x] `Double_val` のアライメント安全性向上 (`memcpy`)。
  - [x] 内部マクロ (`Wosize_val`) の依存性ドキュメント化。
  - [x] `main` ブランチへのマージとリモートプッシュ。

- [x] **Phase 6: 並列スレッド数の自動最適化 (Auto-Capping Parallelism)**
  - [x] CLI オプション `-j N` を `-j` / `--parallel` フラグに変更。
  - [x] `Domain.recommended_domain_count()` を基準とした最適な並列数を自動算出。
  - [x] macOS 環境 (Darwin) を検知し、VFS ロック競合を防ぐため最大スレッド数を 4 にキャップするロジックの実装。
