---
id: TASK-8
title: 'CLI / Daemon: --daemon + -x 二重実行・ルート無視・ソケット残留と多重起動の修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - daemon
  - cli
  - ipc
  - bug
milestone: m-0
dependencies: []
references:
  - bin/main.ml
  - lib/quasifind/daemon.ml
  - lib/quasifind/ipc.ml
  - https://github.com/divergen371/quasifind/issues/8
priority: high
type: bug
ordinal: 8000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
デーモンモードの CLI 統合および IPC ライフサイクルに複数の不具合が存在する。

観測事実:
1. bin/main.ml (L164, L228): `--daemon` と `-x` (`--exec`) を併用すると、Producer 側 (L228) と Consumer 側 (L164) の両方で `Exec.run_one` が実行され、各ファイルに対してコマンドが 2 回実行される。
2. bin/main.ml (L98): `--profile` ロード時の再帰呼び出しで `daemon_mode` と `integrity` を強制的に `false` で上書きしている。
3. bin/main.ml (L578), daemon.ml, ipc.ml: デーモンは `root = "."` 固定で起動され、IPC クエリに `root_dir` が含まれないため、別ディレクトリを指定して `--daemon` 検索しても無視されデーモンのキャッシュ結果がそのまま返る。
4. daemon.ml / ipc.ml (L200, L228-232): 終了時に `daemon.sock` を `unlink` しないため stale socket が残る。また既存デーモン稼働中でも2つ目の起動がソケットを無条件 `unlink` して乗っ取る。さらに `handle_client` の `max_size:4096` が長いクエリを拒否する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 --daemon -x CMD 実行時に各マッチファイルに対してコマンドが 1 回だけ実行されること
- [ ] #2 --profile と --daemon の併用が維持されること
- [ ] #3 IPC クエリまたはクライアント側で root_dir とデーモン管理ルートの一致/スコープ絞り込みを検証し、範囲外ディレクトリに対して誤結果を返さないこと
- [ ] #4 デーモン終了時に socket が確実に unlink され、二重起動防止（PID/ロックまたは稼働確認）と十分な IPC 受信バッファサイズが確保されること
<!-- AC:END -->
