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
