# 実装計画: 履歴とファジー検索機能 (Phase 7)

## 目標

`quasifind` の実行履歴（コマンドと検索結果）を保存し、後からインタラクティブに検索・再利用できるようにする。

## 技術選定と設計変更

### 1. データ保存: JSONL vs SQLite

**結論: JSONL (Metadata) + Plain Text (Results)**

- **理由**:
  - **可搬性**: 外部ライブラリ (SQLite3 C bindings) への依存を避け、`dune build` だけで完結させたい。
  - **Unix哲学**: 履歴ファイルがテキストであれば、`grep` や `jq` などの既存ツールでも解析可能。
  - **パフォーマンス**: コマンド履歴（数千件程度）ならメモリ展開可能。結果リスト（数万行以上）は別ファイル (`~/.local/share/quasifind/results/<uuid>.txt`) に書き出し、必要時のみ読み込むことでメインのJSONLを軽量に保つ。

### 2. インタラクティブ検索: FZF vs Built-in

**結論: FZF優先 + 高精度Built-in (`Smith-Waterman` + `Bit-Parallel`)**

ユーザーの要望（高精度・実装複雑度許容・BK-Treeの検討）に基づき、以下の選定を行いました。

- **BK-Tree (Burkhard-Keller Tree) について**:
  - **特性**: レーベンシュタイン距離（編集距離）に基づく検索に特化しています。「スペルミス（typo）」を見つけるのには最強ですが、「省略入力（`quasifind` -> `qf`）」のような **Subsequence Matching（部分列一致）** には不向きです。
  - **判断**: コマンド履歴やファイルパス検索では「省略入力」のニーズが高いため、BK-Tree単体ではユーザー体験が良くないと判断します。

- **採用アルゴリズム: Smith-Waterman (Local Alignment) with Affine Gap Penalty**:
  - **特性**: バイオインフォマティクスでDNA配列アライメントに使われる高精度アルゴリズム。
  - **利点**:
    - 部分列一致だけでなく、単語の区切り（`/` や `_` の直後）や大文字小文字の一致にボーナスを与えることで、人間の直感に極めて近いランキングが可能。
    - 編集距離（Typo）も許容する設定が可能。
  - **最適化**:
    - 素朴な実装 `O(MN)` は遅いため、ビット並列化（Bit-vector algorithm）や、前処理フィルタリング（Trigram index等）を組み合わせて高速化を図ります。
  - **フォールバック**: FZFがない環境でも、これより「質」の高い検索を提供することを目指します。

## Proposed Changes

### [New Module] `History` (`lib/quasifind/history.ml`)

- `add : cmd:string array -> results:string list -> unit`

- `select : ?query:string -> string list -> string option`
  - `check_fzf_availability : unit -> bool`
  - `run_fzf : string list -> string option`
  - `run_builtin : string list -> string option` (簡易TUI)
- TUI実装は変更なし（ANSIエスケープシーケンス使用）

## Proposed Changes

### [New Module] `History` (`lib/quasifind/history.ml`)

- `add : cmd:string array -> results:string list -> unit`
  - コマンドとメタデータを `history.jsonl` に追記。
  - 結果リストを `results/<uuid>.txt` に保存。
- `load : unit -> entry list`
- `GC` (Garbage Collection): 古い履歴や結果ファイルの掃除機能（今回は簡易実装またはスキップ）。

### [New Module] `Interactive` (`lib/quasifind/interactive.ml`)

- `select : ?query:string -> string list -> string option`
  - `check_fzf_availability : unit -> bool`
  - `run_fzf : string list -> string option`
  - `run_builtin : string list -> string option` (簡易TUI)

### [New Module] `Fuzzy_matcher` (`lib/quasifind/fuzzy_matcher.ml`)

- `match_score : pattern:string -> candidate:string -> int option`
- 候補リストを受け取り、スコア順にソートするロジック。

### [Modify] `bin/main.ml`

- `quasifind history --exec`: 選択して再実行
- `quasifind history --results`: 選択して過去の結果を表示

## Verification Plan

- 手動テスト: コマンド実行後に履歴ファイルが増えているか確認。
- 手動テスト: `quasifind history` で過去のコマンドが表示されるか。
