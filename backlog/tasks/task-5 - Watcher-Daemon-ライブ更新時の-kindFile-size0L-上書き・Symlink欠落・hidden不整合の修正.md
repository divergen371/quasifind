---
id: TASK-5
title: 'Watcher / Daemon: ライブ更新時の kind=File / size=0L 上書き・Symlink欠落・hidden不整合の修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - daemon
  - watcher
  - vfs
  - bug
milestone: m-0
dependencies: []
references:
  - lib/quasifind/watcher.ml
  - lib/quasifind/daemon.ml
  - lib/quasifind/vfs.ml
  - lib/quasifind/vfs.mli
  - https://github.com/divergen371/quasifind/issues/5
priority: high
type: bug
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Daemon のライブ更新および初期スキャン時に、VFS へ誤ったメタデータが登録・上書きされる重大バグがある。

観測事実:
1. watcher.ml (L11-15, L229, L236, L247): `file_state` が `path, mtime, perm` のみ保持し `kind` と `size` を持たないため、`on_new`/`on_modified` へ `kind = Ast.File; size = 0L` のダミー値を渡している。結果、Daemon 上で新規作成・更新されたディレクトリの kind が File になり、ファイルの size が 0L に破壊される。
2. watcher.ml (L235): `file.mtime > old_file.mtime` のみ比較しており、`perm` の変更や `mtime` 巻き戻し (`<>`) を検知できない。また正常終了時に `log_channel` が閉じられない。
3. daemon.ml (L58-63): `update_vfs_insert` が `Ast.Symlink` を `File` に変換している (`Vfs.insert` が ``[`Dir | `File]`` のみ受容)。
4. daemon.ml (L82, L86): `include_hidden = false` 固定のため `quasifind --daemon --hidden` でも隠しファイルが VFS に存在せず 0 件になる。また `spawn = None` のため初期スキャンでマルチドメインを活用できていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Watcher.file_state が kind と size を保持し、on_new / on_modified に実測メタデータが渡ること
- [ ] #2 Watcher が perm 変更および mtime の前後変化 (<>) を検知し、正常終了時に log_channel をクローズすること
- [ ] #3 Vfs.insert および Daemon が Symlink を正しく Ast.Symlink として保持すること
- [ ] #4 Daemon の VFS が hidden ファイルも保持（またはクライアントの --hidden に応答可能）し、初期スキャンで適切に並列実行されること
<!-- AC:END -->
