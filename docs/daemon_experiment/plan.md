# Quasifind Daemon (Experimental) Design Plan

## 概要 (Overview)

「常に最新のファイルシステム状態をメモリ上に保持し、爆速で検索結果を返す」常駐型検索サーバー (`quasifind daemon`) の実験計画です。

## 目標 (Goals)

1.  **超高速応答**: ファイル名や基本的なメタデータ検索を、ディスク走査なし（メモリ参照のみ）でミリ秒単位で完了させる。
2.  **省メモリ**: 全ファイル情報を愚直に持つのではなく、Radix Tree (Trie) や共有構造を用いてメモリ使用量を抑える。
3.  **リアルタイム性**: OSのイベント通知 (FSEvents/inotify) をフックして、メモリ上のツリーを即座に更新する。
4.  **堅牢性**: OCamlの型システムとEioの構造化並行性を活かし、クラッシュしないサーバーを作る。

## アーキテクチャ (Architecture)

### 1. In-Memory Data Structure (The "Brain")

`lib/quasifind/vfs.ml` (Virtual File System) を新設。

- **データ構造**: `Path Trie` (Patricia Tree / Radix Tree)
  - キー: パスコンポーネント (ディレクトリ名)
  - 値: メタデータ (mtime, size, perm, inode)
  - **特徴**: 共通の親ディレクトリを持つパスはノードを共有するため、メモリ効率が良い。
- **圧縮**: 文字列（ファイル名）はインターン化（Hashconsing）して、同一のファイル名（例: `main.ml` や `dune`）の実体をメモリ上で1つにする。
- **Root Scope (Multi-Root)**:
  - 初期状態: 起動時のカレントディレクトリ (`.`) をルートとしてインデックス化。
  - 動的追加: 実行中に監視対象ディレクトリを追加可能（LSPのWorkspace Foldersに相当）。
  - 除外: `.gitignore` や設定で指定されたパスはメモリに乗せない。

### 2. Event Loop & Watcher

`lib/quasifind/daemon.ml`

- **Eio** ベースのメインループ。
- **Watcher**: 既存の `Watcher` モジュールを流用/拡張し、変更イベント (`New`, `Modified`, `Deleted`) を受け取る。
- **Updater**: イベントを受け取り、メモリ上の Trie を**非破壊的**に更新する（古いツリーへの参照を持っている検索クエリは影響を受けない）。

### 3. IPC Server (Client-Server Communication)

- **通信方式**: Unix Domain Socket (`/tmp/quasifind.sock`)
- **プロトコル**: シンプルなバイナリ or JSON Lines
- **クライアント**: `quasifind search --daemon` のように実行されると、自動的にソケットに接続してクエリを投げ、結果を受け取って表示して終了する。

## 実装フェーズ (Phases)

### Phase 1: PoC (Proof of Concept) - Completed

- [x] メモリ上での Trie 構造の定義 (lib/quasifind/vfs.ml)
- [x] 初回スキャンで Trie を構築するロジック (lib/quasifind/daemon.ml)
- [x] メモリ使用量の計測 (文字列インターン化で削減)

### Phase 2: Live Updates - Completed

- [x] `Watcher` からのイベントで Trie を更新するロジック (New/Modified/Deleted)
- [x] 整合性の検証（実際のディスクとメモリ上の状態がズレないか）

### Phase 3: Client-Server - Completed

- [x] Unix Domain Socket サーバーの実装 (lib/quasifind/ipc.ml)
- [x] 検索クエリを受け取り、Trie を探索して返すロジック (Vfs.fold + Eval.eval)
- [x] CLI への統合 (`quasifind search --daemon` command)

### Phase 4: Advanced Search & Optimization

- [ ] **Full Regex Support**: IPCプロトコルで正規表現パターンを転送し、サーバー側でコンパイル・実行できるようにする。
- [ ] **Adaptive Radix Tree (ART)**: `vfs.ml` の `Map` ベースの Trie を ART (Adaptive Radix Tree) に置き換え、メモリ効率とキャッシュ局所性を向上させる。
- [ ] **Hybrid Search (Content/Entropy)**:
  - メモリ上のVFSでパス・メタデータによる高速フィルタリングを行う。
  - 候補ファイルに対してのみ、サーバー側（またはクライアント側？）でディスク読み込みを行い、Content/Entropy判定を行う。
- [ ] **Persistent Cache (Fast Restart)**:
  - 終了時にVFS（または対象ディレクトリのメタデータ）をディスクにシリアライズ保存。
  - 次回起動時にロードし、起動停止中の変更分を `Watcher` (または `mtime` チェック) で差分更新して高速起動。

### Phase 5: CLI & UX Refinement

- [ ] **CLI Option Cleanup**:
  - `follow_symlinks` や `include_hidden` など、デーモン起動時に決定されるオプションと、クエリ時に指定可能なオプションを整理。
  - 無効なオプションが指定された場合に警告またはエラーを表示。
  - `--exec` 等のクライアント側での実行サポート。
