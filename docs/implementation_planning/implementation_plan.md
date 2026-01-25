# Implementation Plan - quasi-find

`docs/Proposal.md` (要件定義書・最終完全版) に基づく実装計画。

## Goal Description

Unix `find` コマンドに着想を得たファイル探索ツール **quasi-find** を OCaml で実装する。
DSLによる条件記述、型システムによる検証、そして Eio を用いた並列走査戦略を特徴とする。

## User Review Required

> [!IMPORTANT]
> **Eio のバージョンとバックエンド**
> OCaml 5.x の Eio を使用するため、開発環境および実行環境が OCaml 5.0 以上であることを前提とする。
> 現在の `dune-project` の設定を確認し、必要であれば更新する。

> [!NOTE]
> **既存コードの扱い**
> `lib/quasifind/{ast.ml, parser.ml}` が既に存在する。これらは破壊的変更を含む形で、今回のアーキテクチャに合わせて修正・拡張する。

## Proposed Changes

### 1. Project Configuration

- **[MODIFY]** `dune-project`: 依存関係の追加 (`eio`, `eio_main`, `angstrom`, `ppx_deriving` 等)
- **[MODIFY]** `lib/dune`, `bin/dune`: ライブラリ構成の定義

### 2. DSL Core (Lib)

#### [MODIFY] `lib/quasifind/ast.ml`

- 既存の AST を整理し、Untyped AST と Typed AST の定義を含める。
- GADT等を用いて型安全に表現するか、あるいはレコードで表現するかを決定（シンプルさ優先でバリアント構成を推奨）。

#### [MODIFY] `lib/quasifind/parser.ml`

- Angstrom を用いたパーサの実装。
- 論理演算 (`&&`, `||`, `!`) の結合順序を正しく処理する。

#### [NEW] `lib/quasifind/typecheck.ml`

- Untyped AST を検証し、Typed AST を生成するモジュール。
- 不正な比較（例: `size =~ "regex"`）をコンパイル時に（実行前に）弾く。

#### [NEW] `lib/quasifind/eval.ml`

- Typed AST とファイルエントリ（パス、stat情報）を受け取り、`bool` を返す純粋関数。

### 3. Traversal Strategy (Lib)

#### [NEW] `lib/quasifind/traversal.ml`

- 走査ロジックの抽象化。
- `Planner` (Minimal A): Typed AST から `path` 条件を抽出し、走査の初期パスや除外リストを生成。
- **Eio Integration**: `Eio.Path` 等を用いたファイルシステム操作。
- **Parallelism**: Eio のファイバーを用いた並列再帰走査の実装。

### 4. CLI (Bin)

#### [MODIFY] `bin/main.ml`

- エントリーポイント。
- CLI 引数パース、各モジュールのパイプライン接続。

## Verification Plan

### Automated Tests

- `dune runtest`: 単体テストの実行。
- 特に Parser と Eval のロジックテストを重点的に行う。

### Manual Verification

- 実際に深いディレクトリ階層を持つフォルダ（例: `node_modules` や `.git` 含むプロジェクト）で実行し、`find` コマンドの結果と比較する。
- 並列実行時の挙動（順序の非決定性など）を確認する。
