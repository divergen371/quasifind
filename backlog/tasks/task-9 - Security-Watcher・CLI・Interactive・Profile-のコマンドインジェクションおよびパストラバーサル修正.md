---
id: TASK-9
title: 'Security: Watcher・CLI・Interactive・Profile のコマンドインジェクションおよびパストラバーサル修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T16:10:00Z'
labels:
  - security
  - cli
  - watcher
  - interactive
  - bug
milestone: m-0
dependencies: []
references:
  - lib/quasifind/watcher.ml
  - bin/main.ml
  - lib/quasifind/interactive.ml
  - lib/quasifind/profile.ml
  - https://github.com/divergen371/quasifind/issues/9
priority: high
type: bug
ordinal: 9000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
外部コマンド呼び出しや JSON 組み立て、ファイル名解決にコマンドインジェクション・JSON インジェクション・パストラバーサルの脆弱性が存在する。

観測事実:
1. watcher.ml (L69-113, L195-204): `send_webhook`, `send_email`, `send_slack`, `send_heartbeat`, integrity alert がファイルパス・URL・件名等を無エスケープで JSON 文字列およびシェル文字列 (`curl ... '%s'`) へ展開しており、ファイル名にシングルクォート等が含まれると任意コマンド実行や JSON 破損を起こす。
2. bin/main.ml (L66, L367, L426-437, L463): `--integrity` の `shasum` 呼び出し、`-c` の `content =~ "%s"` 無エスケープ埋め込み、`quote_arg` の特殊文字 (`$`, `` ` ``, `;`, `|`, `&`, `\\n` 等) 漏れ、`history preview` の `Sys.executable_name` 未クォート。
3. interactive.ml (L14, L203): `run_fzf` の `preview_cmd` がシングルクォートでしか囲まれておらず、`TUI.get_preview` は `Str.global_replace` 使用により置換後パス内の `\\1` 等を後方参照として誤解釈する。
4. profile.ml (L58-59): プロファイル名に `../` 等が含まれても制限せず読み書きを行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Watcher の通知・ハッシュ確認がシェル経由ではなく直接プロセス起動 (Eio.Process/Unix.create_process) または厳格クォート、かつ Yojson による JSON 生成へ置き換えられること
- [ ] #2 bin/main.ml の -c 埋め込み、--integrity、quote_arg、history preview が特殊文字を含むパス・入力に対して安全であること
- [ ] #3 Interactive.run_fzf / TUI.get_preview でシングルクォートやバックスラッシュを含むパス・コマンドが安全に扱われること
- [ ] #4 Profile.save / load が英数字・ハイフン・アンダースコア等に限定する等パストラバーサルを拒否すること
<!-- AC:END -->
