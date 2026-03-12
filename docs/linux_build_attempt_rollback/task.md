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

- [x] ~~**Phase 7: macOS 専用 `getattrlistbulk` 爆速化 (VFS Lock Bypass)**~~ (Abandoned: validation proved Lazy Stat was faster)
  - [x] ~~`dirent_stubs.zig` に macOS 環境用 (`@import("builtin").os.tag == .macos`) の分岐を追加。~~
  - [x] ~~`getattrlistbulk` を用いた一括メタデータ＆エントリ取得ロジックの実装（Zigレベル）。~~
  - [x] ~~`dirent.ml` および `traversal.ml` との連携: 取得済みメタデータ (size, mtime, is_dir) を OCaml 側に直接返し、トラバーサル中の個別の `stat` 呼び出しを削減。~~
  - [x] ~~macOS 環境でのパフォーマンスベンチマークテストの実施。~~
  - [x] ~~**【追加実装】** AST の `needs_stat` フラグを FFI 層へ渡し、名前探索のみの場合は `getattrlistbulk` すらバイパスする軽量化。~~
  - [x] ~~**【バグ修正】** OCamlへの変換時(`Val_long`)の負数シフトによるZigパニック回避 (`@bitCast` unsigned経由)。~~

---

- [x] **Phase 8: ファイルマネージャー向け・超高速リスト出力 API (`--ls`) の実装**
  - [x] CLI オプション `--ls` (または `--list`) の追加。検索ではなく、指定ディレクトリのメタデータを全出力するモード。
  - [x] `main` ブランチに、以前の実験コードである Zig の `getattrlistbulk` 呼び出し（OS X 専用バルク取得）を「リスト出力専用エンドポイント (`Dirent.readdir_bulk_stat`)」として復活させる。
  - [x] トラバーサル処理を介さず、指定ディレクトリ 1 階層のみ（`-a` の隠しファイル制御含む）を一括で取得する専用フローを構成する。
  - [x] 取得結果を OS 標準の `ls -al` と比較し、数十万ファイルのディレクトリ展開スピードが最適化されていることを確認する。

- [x] **Phase 9: バルクスキャンAPI (`--ls`) のテスト拡充**
  - [x] シンボリックリンク、ハードリンクを含むテスト用のディレクトリツリーを構築する準備。
  - [x] `Dirent.readdir_bulk` 関数を直接叩き、期待されるエントリ（ファイル、ディレクトリ、シンボリックリンク等）が正確に返ることを確認するユニットテストの作成。
  - [x] CLI レベル (`--ls`) での e2e テストを追加し、ソート順（隠しファイル先行の英数字昇順）などが正しく機能しているかを検証する。

- [x] **Phase 10: CLI ユーザビリティの自動テスト拡充 (Cram E2E)**
  - [x] `-max-depth` 制限: 指定した階層より下を探索しないことのスナップショット検証。
  - [x] `-follow-symlinks` 制約: オプションの有無によるシンボリックリンク先のトラバース挙動の違いを検証。
  - [x] `--exclude` パターンマッチ: 特定のディレクトリやファイル群を正確にスキップできているかの検証。
  - [x] DSLクエリの複合条件: 例外的なクエリ (例: `-name "foo" AND -type "d"`) や正規表現が期待通りに動くかの総合的な e2e パターンを `test_cli.t` に記述する。

- [x] ~~**Phase 11: Linux / マルチプラットフォーム向けビルド互換性の修正**~~ [ABANDONED]
  - [x] ~~`lib/dune` の `dirent_stubs` および `search_stubs` ビルドアクションで、OS 判定スクリプトを用いて macOS 専用フラグを分離する。~~
  - [x] ~~`fsevents_stubs.zig` のビルドアクションで、Linux時にはダミーオブジェクトを出力するか、コンパイル自体を回避する仕組みを組み込む。~~
  - [x] ~~`fsevents` モジュールへの OCaml 側からのアクセス（Linux時）が実行不能（ダミー挙動）となるように、安全装置を張る（または既存の `is_available` 等を活用する）。~~
  - [x] ~~macOS 環境でのビルドとテストパスを再度確認する。~~
