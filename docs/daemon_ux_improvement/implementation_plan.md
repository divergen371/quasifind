# Implementation Plan: Daemon 出力改善とメタデータ修正

## 目的
1.  `quasifind daemon` 使用時の出力の混ざり（`duneerying daemon...` 等）の解消。
2.  デーモン経由の検索結果でファイルタイプ（色付け）や権限が正しく反映されない問題の修正。

---

## Proposed Changes

### 1. 出力インターリーブの修正
#### [MODIFY] [main.ml](file:///Users/atsushi/OCaml/quasifind/bin/main.ml)
- `[Info] Querying daemon...\r` を `[Info] Querying daemon...\n` に変更。`\r` による同じ行への上書きを防ぐ。

### 2. デーモン・クライアント間のメタデータ完全同期
#### [MODIFY] [daemon.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/daemon.ml)
- 検索結果の JSON に `type` (string) と `perm` (int) を追加。
- `size` を `Intlit` で送り、`Int64` の精度を維持。

#### [MODIFY] [ipc.ml](file:///Users/atsushi/OCaml/quasifind/lib/quasifind/ipc.ml)
- `json_to_response` 内でのエントリ復元を修正。
- `type` から `Ast.file_type` を、`perm` から権限値を復元するように変更。
- `Intlit` を使用して `Int64` を正しく処理。

---

## Verification Plan

### 1. 出力表示の確認
- `quasifind . 'name == "dune"' --daemon` を実行し、結果が混ざらずに表示されるか確認。

### 2. メタデータの確認
- `--format=table` や `--color=always` を付けてデーモン検索を実行。
- ディレクトリが青く表示されるか、サイズや権限が正しく表示されるか確認。

### 3. ビルド確認
- `dune build` が通ることを確認。
