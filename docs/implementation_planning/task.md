# Task List: quasi-find

プロジェクト全体の進捗を管理するタスクリスト。`docs/Proposal.md` の要件に基づく。

- [x] **Phase 1: 計画と基盤整備** <!-- id: 0 -->
  - [x] 実装計画の策定 (`implementation_plan.md`) <!-- id: 1 -->
  - [x] 既存コード (`ast.ml`, `parser.ml`) の現状確認とリファクタリング方針決定 <!-- id: 2 -->
  - [x] プロジェクト構成の整理 (依存関係: `eio_main`, `angstrom`, `ppx_deriving` 等の確認) <!-- id: 3 -->

- [x] **Phase 2: DSL Core (型システムと評価)** <!-- id: 10 -->
  - [x] `Ast` モジュールの拡張 (Typed AST の定義) <!-- id: 11 -->
  - [x] `Typecheck` モジュールの実装 (Untyped AST -> Typed AST) <!-- id: 12 -->
  - [x] `Eval` モジュールの実装 (Typed AST + Entry -> bool) <!-- id: 13 -->
  - [x] テスト: DSLのパース・型チェック・評価の単体テスト <!-- id: 14 -->

- [x] **Phase 3: Traversal Engine (戦略と実行)** <!-- id: 20 -->
  - [x] `Traversal` モジュールのインターフェース定義 (Strategy Pattern) <!-- id: 21 -->
  - [x] 基本実装: シーケンシャル DFS <!-- id: 22 -->
  - [x] `Planner` (Minimal A) の実装: path prefix の抽出 <!-- id: 23 -->
  - [x] **Eio** による並列走査実装 (Producer-Consumer / Stream) <!-- id: 24 -->

- [x] **Phase 4: CLI と統合** <!-- id: 30 -->
  - [x] CLI 引数解析 (cmdliner 推奨) <!-- id: 31 -->
  - [x] Main ループの実装 (Parse -> Typecheck -> Plan -> Traverse -> Eval -> Print) <!-- id: 32 -->
  - [x] エラーハンドリングと出力フォーマットの整備 <!-- id: 33 -->

- [x] **Phase 5: 検証とドキュメント** <!-- id: 40 -->
  - [x] 結合テスト (実際のファイルシステムを用いたテスト) <!-- id: 41 -->
  - [x] `README.md` の整備 (find との違い、使い方) <!-- id: 42 -->
  - [x] 最終確認 (Walkthrough) <!-- id: 43 -->
