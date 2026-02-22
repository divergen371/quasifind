# Task List: Daemon 出力改善とメタデータ修正

## 1. 出力インターリーブ修正
- [x] `main.ml` の `\r` を解除

## 2. メタデータ同期 (Daemon -> IPC -> CLI)
- [x] `daemon.ml` で `type`, `perm`, `size(Intlit)` を送るように修正
- [x] `ipc.ml` で上記を正しくパースして `Eval.entry` を復元するように修正

## 3. 検証
- [x] 出力の混ざりがないことを確認
- [x] デーモン経由でも色付き出力・テーブル表示が正しいことを確認
