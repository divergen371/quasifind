---
id: TASK-14
title: 'ART / VFS / Exec / History: ART縮小再圧縮・VFS絶対パスと保存安全性・Execバッチ分割・History上限管理'
status: To Do
assignee: []
created_date: '2026-11-18T13:04:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - art
  - vfs
  - exec
  - history
  - enhancement
milestone: m-1
dependencies: []
references:
  - lib/quasifind/art.ml
  - lib/quasifind/vfs.ml
  - lib/quasifind/exec.ml
  - lib/quasifind/history.ml
  - bin/main.ml
  - https://github.com/divergen371/quasifind/issues/14
priority: medium
type: enhancement
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コアデータ構造・コマンド実行・履歴管理の信頼性および大規模データ耐性を改善する。

観測事実:
1. art.ml (L66-72 remove_child): `Large` ノードから子が削除されて 4 個以下になっても `Small` に降格しないため、残り 1 子になっても `try_compress` が発火せず Patricia 圧縮が効かない。
2. vfs.ml (L20-23, L110-127): `split_path` が絶対パスの先頭 `/` や `./` を除去するため相対/絶対パス情報が欠落し、VFS 出力と通常走査出力が食い違う。また `save` が原子的書き込みを行わず、`load` がバージョン不一致以外の例外時に `ic` を閉じずにリークする。
3. exec.ml (L27-36): `run_batch` が大量マッチ時に `ARG_MAX` を超えて失敗する可能性があり、終了コード非ゼロ時に即例外中断する。
4. bin/main.ml (L158) / history.ml (L86-106): 検索のたびに全結果をメモリリスト保持し `~/.local/share/quasifind/results/` へ無制限にファイルを生成する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Art.remove_child が small_limit 以下で Small へ戻し try_compress が機能すること
- [ ] #2 Vfs がルートプレフィックス（絶対パス / ./ 相対）を保持し、Vfs.save が一時ファイル+rename で原子的保存され、Vfs.load が Fun.protect/finally で確実にチャネルを閉じること
- [ ] #3 Exec.run_batch が引数長制限を考慮した分割実行（xargs 相当）に対応すること
- [ ] #4 History の結果保存件数・ファイル数の上限またはローテーション方針が実装されること
<!-- AC:END -->
