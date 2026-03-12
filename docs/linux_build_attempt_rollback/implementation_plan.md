# Quasifind 爆速化計画 - Phase 4: Hybrid Filter Push-down

## 目的
OCaml製のディレクトリスキャナエンジンである Quasifind が、極限まで無駄を削ぎ落とした Rust製の `fd` (内部エンジン: `ignore` クレート) を単線/並列スレッドの両方で追い抜くための最終最適化を実施します。

現状の OCaml 側での「全件アロケーション後 AST 評価」から、**「C (Zig) 側での文字列プレフィルタリング後 OCaml アロケーション」**へとパラダイムシフトを行います。

## アプローチ（ハイブリッド型 AST オフロード）

全ての AST ロジック（サイズ、パーミッション、日付等）を Zig に移植するのではなく、**検索結果の 95% を削ぎ落とせる「文字/名前のマッチング」と「ディレクトリの除外(Ignore)」** のみを、Zig (`dirent_stubs.zig` の `iter_batch`) にプッシュダウンします。

1. **`Traversal.ml` の改修**:
   - `Ast.Typed.expr` を分析し、Zig 側で処理可能な「名前マッチ条件 (`StrEq`, `StrEndsWith` など)」や「無視パターン (`ignore` 文字列)」のリストを抽出します。
2. **`dirent.ml` / `dirent_stubs.zig` の FFI インターフェース拡張**:
   - 現在の `readdir` は無条件でバッチ化して返していますが、ここに `~ignore_names:string list` や `~match_names:string list` などの引数を追加します。
   - OCaml 側からバイト列の配列を渡し、Zig 側でスライス (`[]const u8`) として解釈させます。
3. **Zig レイヤーでのゼロ・メモリアロケーション・フィルタリング**:
   - OS の `readdir` が返した `d_name` (stack buffer) と、OCaml から渡されたフィルタ条件を Zig 次元で直接 `memcmp` 等を用いて比較します。
   - 条件に「合致しない（または除外すべき）」エントリは、その場で `continue` して捨てます。
   - フィルタを通過した「選ばれしファイル」だけを `caml_alloc` で OCaml ヒープ上に構築し、OCaml エンジン（`eval.ml`）にお返しします。

## Proposed Changes

### [MODIFY] [lib/quasifind/dirent.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/dirent.ml)
#### [MODIFY] [lib/quasifind/dirent_stubs.zig](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/dirent_stubs.zig)
- バッチイテレータの初期化 (`caml_readdir_batch`) またはディレクトリオープン (`caml_opendir`) 時、もしくはイテレーション呼び出し自体に、**プレフィルタ用の引数（文字列ポインタの配列）**を渡せるようにシグネチャを変更します。
- Zig 側で安全かつ高速に `ignore` リストや `match_suffix` 等の判定を行うロジックを追加します。

### [MODIFY] [lib/quasifind/traversal.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/traversal.ml)
- トラバーサルループの開始前に、現在のクエリ (`Ast.Typed.expr`) からプッシュダウン可能な条件を収集 (Extract) します。
- 抽出した条件を `Dirent.readdir ~filter` のように FFI へ引き渡します。
- ※ OCaml の `eval.ml` による厳密評価は引き続き行うことで、複雑なロジックを担保します。

## ベンチマーク検証目標
- `run_benchmark.sh` の `quasifind (parallel)` のスコアが `fd` のスコア (約 1.27秒) を超える、あるいは同等 (1.20秒〜1.25秒) の領域に突入することを目指します。

# Phase 7: macOS getattrlistbulk Optimization (VFS Lock Bypass) [ABANDONED]

> [!CAUTION]
> **検証の結果破棄されました (Rolled back)**
> `getattrlistbulk` を用いた一括メタデータ取得は、名前フィルタリングのみのクエリ（メタデータが不要な場合）であってもカーネルに強制的なディスクシークとサイズ計算を行わせてしまい、元の「Lazy Stat」実装（名前で絞り込めた少数のファイルにのみ `lstat` を発行する）と比べて極めて遅くなる（約10倍の速度低下）ことが判明しました。
> このため、この最適化アプローチは破棄し、Quasifind の元の実装が持つ「Lazy Stat + 4-thread cap」が最適解であることが証明されました。

## 目的
macOS 環境において、並列実行時に発生する OS カーネルの VFS (Virtual File System) レイヤのロック競合を抜本的に回避します。現在、各ファイルごとに `stat` や `lstat` を呼び出すことで大量のシステムコールとロック競合が発生していますが、`getattrlistbulk` を用いることで数十〜数百エントリのメタデータと名前を 1 回のシステムコールで一気に引き抜きます。

## アプローチ
1. **`dirent_stubs.zig` への macOS 専用分岐追加**:
   - `builtin.os.tag == .macos` の場合のみ有効化される、`getattrlistbulk` を用いたディレクトリスキャンロジックを実装します。Linux 環境等では従来の `readdir` を fallback として使用します。
   - `ATTR_CMN_NAME`, `ATTR_CMN_OBJTYPE` のみならず、`ATTR_CMN_MODTIME`, `ATTR_FILE_TOTALSIZE` までを取得するバルククエリを投げます。

2. **FFI インターフェースの拡張設計 (`dirent.ml` / `traversal.ml`)**:
   - `iter_batch` の戻り値を、単なる名前と種別（`string * file_kind`）の配列から、事前に取得したメタデータを包含する形（または別配列で返す形）へと拡張します。
   - Traversalエンジン側では、「すでにサイズや更新日時が取得できている場合」は `Unix.lstat` の呼び出しをスキップ（ショートサーキット）するように改修します。これにより、トラバーサル中の `stat` 呼び出し回数をほぼゼロにし、System Wait を劇的に減らします。

## 課題
- OCaml の FFI を通じてどのように効率よくメタデータ（`mtime`, `size`）を渡すか。タプルのアロケーションが増えると OCaml ヒープへの圧力が上がるため、現在のように Zig 側で AST 条件フィルタ（`size > 1MB` 等）も評価してしまうプッシュダウンアプローチを拡張し、条件に引っかかったものだけを選択的に返すのが最も美しくオーバーヘッドがありません。ただし、第一歩としては単純に「メタデータを格納したフラットな配列」として OCaml 側に一括で渡す方式をテストします。

---

# Phase 8: ファイルマネージャー向け・超高速リスト出力 API (`--ls`) の実装

## 目的
将来の GUI ファイルマネージャー開発に備え、事前のバックエンド機能として「指定されたディレクトリの中身（メタデータ付き）を一瞬で全件取得する機能（`--ls -a` 相当）」を `quasifind` に組み込みます。
Phase 7 で棄却された「`getattrlistbulk`（バルクスキャンAPI）」ロジックを再利用し、検索トラバーサルとは完全に分離された **"リスト表示特化型エンドポイント"** として復活させます。

## アプローチ

1. **CLI エントリポイントの拡張 (`bin/main.ml` / `bin/cli.ml`)**
   - 新たなオプション `--ls <dir>`（または `--list`）を追加します。
   - このオプションが指定された場合は、ASTのパースや並列トラバーサル（`Traversal.run`）を行わず、即座に「単一ディレクトリ一括取得処理」へフォークします。

2. **OCaml FFI 側の分離 (`lib/quasifind/dirent.ml` / `dirent.mli`)**
   - 既存の `readdir_batch`（軽量版）はそのままにし、新たに `readdir_bulk_stat` という専用の OCaml 外部関数バインディングを追加します。
   - 戻り値は `(string * file_kind * int64 * int64) array` (名前, 種類, サイズ, 更新日時) とし、一括で表示用メタデータを引き出せるようにします。

3. **Zig 側のバルク API 復活 (`lib/quasifind/dirent_stubs.zig`)**
   - 以前 `experiment-getattrlistbulk` ブランチで作成した `getattrlistbulk` を用いるコードを `caml_readdir_bulk_stat` として新規に実装します。
   - macOS (`builtin.os.tag == .macos`) ではバルクスキャンを行い、Linux環境に対しては fallback として通常の `readdir` + `lstat` ループを提供して互換性を維持します。

4. **出力フォーマット**
   - TSV (タブ区切り) や JSONL 形式等で標準出力（または指定ストリーム）に流し込めるようにし、将来的な IPC 通信の形式と互換性を持たせます。

### Phase 9: バルクスキャンAPI (`--ls`) のテスト拡充 (完了)

- **目標**: `quasifind --ls` の振る舞いをエンドツーエンド（e2e）で検証し、品質を担保する。
- **アプローチ**:
  - Cram テストフレームワークを利用して `test/test_ls.t`（または新規の `test/test_ls.t`）に `--ls` 専用のテストケースを追加。
  - **検証項目**:
    1. **通常ファイルとディレクトリ**のパース（権限、種類が正しく出るか）。
    2. **シンボリックリンク (`l`)** と **ハードリンク** に対する `getattrlistbulk`（またはフォールバック）の挙動確認。リンク先への誤影響（不必要なトラバース）が行われないこと。
    3. **ソートの正確性**: ドットで始まる隠しファイル群が先頭に来ており、かつ大文字・小文字を無視したアルファベット順（ASCII）になっていること。
  - テスト実行前にシェルコマンド（`ln -s` など）で専用のモックツリーを構築し、標準出力の結果をスナップショット検証する。

### Phase 10: CLI ユーザビリティの自動テスト拡充 (Cram E2E) (New)

- **目標**: 既存の CLI 各機能（オプション）が複雑なディレクトリ構造下で意図通り作動することを Cram テストで保証する。
- **アプローチ**:
  - `test/test_cli.t` を新設し、テスト用の深いディレクトリツリー（シンボリックリンクや除外対象フォルダを含む）を構築する。
  - 以下の CLI オプションに対するテストパターンを記述し、マッチする行数や結果パスを検証する。
    1. **`--exclude`**: 指定したディレクトリ（例: `.git` や `node_modules` 相当のフォルダ）内が確実にスキップされ結果に出現しないこと。
    2. **`-max-depth N`**: 指定した深さ（例えば 1 や 2）のディレクトリより下層が探索されない設計になっていること。
    3. **`-follow-symlinks`**: オプションがない場合はリンク先ディレクトリの中まで探索せず、付与したときだけリンク先をトラバースすることの比較。
    4. **DSL 複合クエリ**: `-name ".*?\.txt" AND size > 1KB` のような DSL が正しくパース・評価され、意図したファイルのみを出力すること。

---

# Phase 11: Linux / マルチプラットフォーム向けビルド互換性の修正 [ABANDONED]

> [!CAUTION]
> **検証の結果破棄されました (Rolled back)**
> Linux と macOS の間で `struct_stat` の定義や Zig の C ヘッダ解決（`sys/types.h`, `sys/stat.h` 等）に深い差異があり、クロスプラットフォーム対応の開発・保守コストが高すぎると判断されたため、Quasifind は引き続き macOS (Apple Silicon) に特化した最適化パスを歩むこととなりました。

## 目的
現在 `lib/dune` の Zig Cスタブコンパイルルールにおいて、`-target aarch64-macos` や `-framework CoreServices` といった macOS 固有のオプションが**ハードコード**されており、Linux などの他プラットフォームでビルド（`dune build` / `dune install`）が失敗する問題を解決する。

## アプローチ
`dune-configurator` を導入するほど仰々しい設定ではないため、Dune の `(action (bash ...))` 内でシェルスクリプトレイヤーの `uname -s` を用いた動的なフラグ組み立てを行い、ホスト OS に応じたビルドコマンドを発行させる。

1. **`lib/dune` の `(rule)` (アクション群) の修正**:
   - `dirent_stubs`, `search_stubs`, `fsevents_stubs` の各ビルドコマンドから `-target aarch64-macos` を削除（コンパイラのデフォルトターゲットに委ねる）。
   - macOS 固有フラグ（`-Wl,-undefined,dynamic_lookup`）や Framework のリンク指定を、`OS=$(uname -s); if [ "$OS" = "Darwin" ]; then ...` で分岐させる。
2. **`fsevents_stubs.zig` の扱い**:
   - `fsevents` は macOS (Darwin) 限定の機能であり、Linux では機能しない。Linuxでのコンパイルエラーを防ぐため、OS 判定 (`uname -s`) によって `Darwin` 以外の場合はダミーのオブジェクトファイル（中身が空）を生成するか、無害なZigコードだけをビルドアクションとして実行するロジックを組む。

## Verification Plan
