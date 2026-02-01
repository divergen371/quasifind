# Quasi-find

Quasi-find (findもどき)は、型付き DSL を用いてファイルシステムを検索する、OCaml 製のコマンドラインツールです。Unix の `find` コマンドの代替を目指していますが、より表現力の高いクエリ言語を提供します。

## 特長

- **型付き DSL**: `size > 10MB` や `mtime < 7d` のように、型安全な式で検索条件を記述できます。
- **高速な走査**: `Eio` を用いた並列走査により、大規模なディレクトリツリーも効率的に検索できます。
- **正規表現**: ファイル名やパスに対して PCRE 正規表現 (`=~`) を利用可能です。
- **直感的な単位**: `KB`, `MB`, `GB` や `s` (秒), `m` (分), `h` (時間), `d` (日) などの単位を直接扱えます。

## パフォーマンス

OCaml 5 のマルチコア並列処理と低レベル最適化により、Rust 製の高速検索ツール `fd` と同等の速度を実現しています。

| ツール                   | 実行時間 (平均) | 速度比 (vs find) | 備考                     |
| ------------------------ | --------------- | ---------------- | ------------------------ |
| **quasifind (Parallel)** | **1.34s**       | **5.0x**         | `fd` と同等              |
| **fd** (Rust)            | 1.32s           | 5.1x             | 非常に高速               |
| **quasifind (DFS)**      | 1.86s           | 3.6x             | シングルスレッドでも高速 |
| **find** (Unix)          | 6.71s           | 1.0x             | 基準                     |

### 高速化の技術的詳細 (Technical Highlights)

Quasifind は OCaml 5 の並列処理能力を最大限に引き出すため、以下の最適化を行っています。

1. **Multicore Parallelism & Work Stealing**:
   OCaml 5 の `Domain` と `Eio` を活用し、CPU コア数に応じた並列走査を行います。
   タスク分配にはロックフリーな Work-Stealing Deque (`Saturn`) を採用し、ディレクトリの偏り（巨大なサブツリーなど）があってもコアを遊ばせない動的なロードバランシングを実現しています。

2. **Native Readdir w/ d_type**:
   標準の `Sys.readdir` はファイル名のみを返し、ファイル種別（ディレクトリかファイルか）を知るために追加の `lstat` が必要でした。
   Quasifind は C 拡張を用いて `dirent` 構造体の `d_type` フィールドを直接取得することで、多くのシステムで `lstat` をスキップし、システムコール発行数と GC 圧力を大幅に削減しています。

3. **Lazy Stat Optimization**:
   クエリ式を静的に解析し、ファイルサイズや更新日時などのメタデータが不要な場合（例: `name =~ /\.ml$/` のみの場合）、`lstat` 呼び出しそのものを省略します。
   これにより、Rust 製の `fd` と同等の「名前検索なら爆速」という挙動を実現しました。

4. **Mmap & Zero-Copy Regex**:
   `content =~ /.../` によるファイル内容検索において、ファイルを `mmap` でメモリにマッピングし、C言語の正規表現エンジン (`regex.h`) を直接適用する最適化を導入しています。
   これにより、巨大なファイルをOCamlのヒープに読み込むコスト（アロケーションとGC）を回避し、`grep` や `ripgrep` に迫るスループットを実現しています（レガシーな読み込み方式と比較してCPU効率が約8倍向上）。

### `fd` との違い (.gitignore の扱い)

`fd` と `quasifind` の最大の挙動の違いは、`.gitignore` ファイルの扱いです。

- **fd**: 探索中に各ディレクトリの `.gitignore` を動的に読み込み、その階層以下のルールを適用します。これにより Git の管理外ファイルを正確に隠せますが、ファイル読み込みのオーバーヘッドが発生します。
- **quasifind**: パフォーマンスと明確さを優先し、**静的な除外リスト**（デフォルトで `.git`, `_build`, `node_modules` など）のみを使用します。サブディレクトリ内の `.gitignore` は読み込みません。
  - プロジェクト固有の除外ルールがある場合は、設定ファイル (`config.json`) の `ignore` リストに追加してください。

## インストール

```bash
dune build
dune install
```

## 使い方

```bash
quasifind [DIR] "EXPR" [OPTIONS]
```

### 使用例 (Cookbook)

#### 基本的な検索

カレントディレクトリから、名前が `.log` で終わるファイルを検索（正規表現）:

```bash
quasifind . 'name =~ /\.log$/'
```

サイズが 10MB 以上かつ更新が 7 日以内のファイルを検索:

```bash
quasifind . 'size > 10MB && mtime < 7d'
```

#### 高度な検索

`_build` ディレクトリを除外して検索（パスに対する正規表現）:

```bash
quasifind . 'name == "main.exe" && path =~ /^(?!.*_build\/)/'
```

※ 注: 隠しファイル（`.`で始まる）はデフォルトで除外されます。`_build` は隠しファイルではないため、上記のように正規表現で弾くか、無視リスト機能で弾くようにします（将来実装予定）。

ファイルタイプを指定して検索（ディレクトリのみ）:

```bash
quasifind . 'type == dir && name =~ /^test_/'
```

#### 履歴とインタラクティブ検索

履歴から過去のコマンドを検索・再実行（`fzf` 推奨）:

```bash
quasifind history --exec
```

履歴の一覧を表示:

```bash
quasifind history
```

**組み込みのファジー検索もそれなりに快適に動作しますが、しばしばTUIの崩れが発生するためFZFを推奨します。**

#### コマンド実行

見つかった各ファイルに対して `ls -l` を実行（`{}` はパスに置換されます）:

```bash
quasifind . 'size > 1MB' -x "ls -l {}"
```

見つかった全てのログファイルをまとめて `tar` で圧縮（バッチ実行）:

```bash
quasifind . 'name =~ /\.log$/' -X "tar czf logs.tar.gz {}"
```

**注意**: `-X` オプションは、見つかったファイルを引数としてコマンドを一度だけ実行します。そのため、`{}` は全パス（スペース区切り）に置換されます。
ドライラン機能はまだ実装してないので、検索結果をよく確認してから実行オプションを使用してください。特に `rm` や `rm -rf` などの破壊的コマンドを実行する場合は、十分に注意してください。

#### オプション活用

隠しファイルも含めて検索（`--hidden` / `-H`）:

```bash
quasifind . 'name == ".gitignore"' -H
```

並列度 8 で高速に検索（`-j`）:

```bash
quasifind /data 'size > 1GB' -j 8
```

探索深さを 2 階層までに制限（`-d`）:

```bash
quasifind . 'true' -d 2
```

- **フィールド**: `name`, `path`, `type`, `size`, `mtime`, `perm`, `content`, `entropy`, `suid`, `sgid`
- **演算子**: `==`, `!=`, `<`, `<=`, `>`, `>=`, `=~` (正規表現)
- **論理演算**: `&&` (AND), `||` (OR), `!` (NOT)
- **値**:
  - 文字列: `"sample.txt"`
  - 正規表現: `/^test_.*\.ml$/`
  - ファイルタイプ: `file`, `dir`, `symlink`
  - サイズ: `123`, `10KB`, `1.5GB`
  - 時間: `10s`, `5m`, `24h`, `7d`
  - 権限: `0o755`, `644` (8進数: `0o`接頭辞推奨)
  - エントロピー: `7.5` (浮動小数点数)

### 詳細機能

#### アグレッシブ探索 (Aggressive Exploration)

`quasifind` は通常のファイル検索だけでなく、高度なセキュリティ調査やフォレンジック調査にも使用できます。

1. **コンテンツスキャン (`content`)**
   ファイルの中身を読み取り、正規表現でマッチングします。

   ```bash
   # eval(base64...) を含むPHPファイルを検索
   quasifind /var/www 'name =~ /\.php$/ && content =~ /eval\(base64/' --stealth
   ```

2. **エントロピー解析 (`entropy`)**
   ファイルのシャノンエントロピー (0.0 - 8.0) を計算します。暗号化されたファイルや圧縮されたペイロードの発見に役立ちます。

   ```bash
   # エントロピーが高く (7.5以上)、サイズが1MB以上の疑わしいファイルを検索
   quasifind /tmp 'entropy > 7.5 && size > 1MB'
   ```

3. **Ghostファイル検出 (`--check-ghost`)**
   削除されたものの、プロセスによってまだ開かれているファイル（Filelessマルウェアの痕跡など）を検出します。
   ※ `--suspicious` モードでは自動的に実行されます。
   ※ `--suspicious` 単体で実行した場合、デフォルトのルールセット（または `rules.json`）が自動的に適用されます。追加の条件を指定したい場合は `quasifind . --suspicious 'size > 1GB'` のように記述してください。

#### ステルスモード (`--stealth`)

自己隠蔽を行いながら検索を実行します。

- **プロセス偽装**: プロセス名を `[kworker/0:0]` などのシステムプロセス風に偽装し、`ps` や `top` で目立たなくします。
- **タイムスタンプ復元**: `content` や `entropy` のスキャンでファイルを読み込んでも、アクセス日時 (`atime`) を即座に復元し、痕跡を残しません（Anti-Forensics）。

#### 怪しいファイル探索 (`--suspicious`)

組み込みのヒューリスティックルールを用いて、侵害の兆候があるファイルを自動的に検出します。

- 隠し実行ファイル (`.exe`, `.sh` など)
- 危険な権限 (777, SUID)
- `/tmp` 配下の巨大ファイル
- 削除されたのに開かれているファイル (Ghost)

```bash
quasifind / --suspicious --stealth
```

#### ルール自動更新と外部インテリジェンス (`--update-rules`)

Quasifind は、外部の信頼できるセキュリティリスト（SecLists など）から最新の脅威情報（WebShellの拡張子リストや危険なファイル名リスト）を取得し、**自動的に検知ルールに変換して取り込む**機能を持っています。

```bash
# 最新のルールを取得して更新
quasifind --update-rules
```

これにより、手動で複雑な正規表現を書かなくても、コミュニティの知見を活用した検知が可能になります。更新されたルールは `~/.config/quasifind/rules.json` に保存され、`--suspicious` モード実行時に自動的に適用されます。

### オプション

- `-d DEPTH`, `--max-depth=DEPTH`: 探索する最大深度を指定します。
- `-h`: ヘルプを表示します。
- `-H`, `--hidden`: 隠しファイル・ディレクトリ（.で始まるもの）も含めて検索します（デフォルトでは除外されます）。
- `-j JOBS`, `--jobs=JOBS`: 並列実行するジョブ数（スレッド数）を指定します。デフォルトは 1 です。
- `-L`, `--follow`: シンボリックリンクを追跡します。
- `-x CMD`, `--exec=CMD`: 各検索結果に対してコマンドを実行します。`{}` はパスに置換されます。
- `-X CMD`, `--exec-batch=CMD`: すべての検索結果を引数としてコマンドを一度だけ実行します。`{}` は全パス（スペース区切り）に置換されます。
- `-E PATTERN`, `--exclude=PATTERN`: 指定したパターン（glob）にマッチするファイルを除外します。複数指定可能。
- `-p NAME`, `--profile=NAME`: 保存したプロファイルを読み込んで実行します。
- `--save-profile=NAME`: 現在の検索オプションをプロファイルとして保存します。
- `-w`, `--watch`: ウォッチモード。ファイルシステムの変更を監視し、条件にマッチする新規/変更ファイルを通知します。
- `--interval=SECONDS`: ウォッチモードのスキャン間隔（秒）。デフォルトは 2 秒。
- `--stealth`: ステルスモード。プロセス名を偽装し、ファイルアクセス痕跡（atime）を消去します。
- `--suspicious`: 怪しいファイルを自動検出するプリセットモードです。
- `--check-ghost`: Ghostファイル（削除済みだが開かれているファイル）を検出します（単体で使用可能）。
- `--update-rules`: 信頼できる外部ソースから最新の検出ルールをダウンロード・更新します。
- `--reset-rules`: ヒューリスティックルール (`rules.json`) をデフォルトの状態にリセットします。
- `--reset-config`: 設定ファイル (`config.json`) をデフォルトの状態にリセットします。
- `--log=FILE`: ウォッチモード等のイベントログをファイルに出力します。
- `--webhook=URL`: イベント発生時に指定URLへPOSTリクエストを送信します。
- `--email=ADDR`: イベント発生時にメールを送信します（要sendmail）。
- `--slack=URL`: Slack Incoming Webhook URLへ通知を送信します。

### 正規表現について

`name` および `path` フィールドに対して、`=~` 演算子を用いて正規表現によるマッチングが可能です。

- **構文**: `/pattern/` の形式で記述します。中身は PCRE (Perl Compatible Regular Expressions) 互換の構文をサポートしています（OCaml `re` ライブラリを使用）。
- **フラグ**: 現在フラグ指定（`i` など）はサポートしていません。デフォルトで大文字小文字を区別します。
- **エスケープ**: スラッシュ `/` をパターンに含める場合は `\/` とエスケープしてください。

**例**:

- 拡張子が `.ml` または `.mli`: `name =~ /\.(ml|mli)$/`
- 先頭が `test_` で始まる: `name =~ /^test_/`
- 特定ディレクトリ `_build` を含まないパス: `path =~ /^(?!.*_build\/).*$/` (否定先読みなどが使えるかは `re` の PCRE サポート状況に依存しますが、基本的な互換性はあります)

## 設定ファイル (Configuration)

`~/.config/quasifind/config.json` (または `XDG_CONFIG_HOME/quasifind/config.json`) に設定ファイルを配置することで、動作をカスタマイズできます。

**※ 初回実行時に、自動的にデフォルト設定ファイルが生成されます。**

```json
{
  "fuzzy_finder": "auto",
  "ignore": ["_build", ".git", "node_modules", "**/*.o"],
  "email": "alert@example.com",
  "webhook_url": "https://example.com/hook",
  "slack_url": "https://hooks.slack.com/services/...",
  "rule_sources": [
    {
      "name": "SecLists Web Extensions",
      "url": "https://raw.githubusercontent.com/.../web-extensions.txt",
      "kind": "extensions"
    }
  ]
}
```

- **fuzzy_finder**: ヒストリ検索時のファジーファインダーを指定します (`auto` / `fzf` / `builtin`)。
- **ignore**: 検索から常に除外するパターン（Glob形式）のリストです。
- **email**: Watchモード通知用のメールアドレス（デフォルト: `null`）。指定すると `--email` 未指定時にも通知が飛びます。
- **webhook_url**: 通知用 Webhook URL（デフォルト: `null`）。
- **slack_url**: Slack 通知用 Webhook URL（デフォルト: `null`）。
- **rule_sources**: `--update-rules` 実行時に参照する外部ソースのリスト。`kind` には `"extensions"` (拡張子リスト) または `"filenames"` (ファイル名リスト) を指定します。

## シェル連携 (Shell Integration)

`quasifind history --exec` は選択されたコマンドを標準出力に出力します。
シェルの機能と組み合わせることで、選択したコマンドを入力バッファに挿入することができます。

### Zsh

`.zshrc` に以下のエイリアスを追加することをお勧めします。

```zsh
# qh: 履歴から選択してコマンドラインに挿入
alias qh='print -z $(quasifind history -e)'
```

## テスト

テストは [Alcotest](https://github.com/mirage/alcotest) と [QCheck](https://github.com/c-cube/qcheck) (Property-Based Testing) を使用しています。

### テスト実行

```bash
dune runtest
```

### テストカバレッジ

| モジュール            | テストタイプ           | テスト数       |
| --------------------- | ---------------------- | -------------- |
| Parser/Typecheck/Eval | ユニットテスト         | 6              |
| Entropy               | ユニットテスト         | 2              |
| Traversal             | ユニットテスト         | 4              |
| Content               | ユニットテスト         | 2              |
| Ghost                 | モックテスト           | 3              |
| Rules                 | ユニットテスト         | 5              |
| Suspicious            | ユニットテスト         | 4              |
| Exec                  | ユニットテスト         | 4              |
| Profile               | JSON往復テスト         | 2              |
| History               | JSON往復テスト         | 3              |
| Config                | JSON往復テスト         | 3              |
| RuleConverter         | ユニットテスト         | 3              |
| Interactive           | ユニット + スモーク    | 4              |
| Stealth               | スモークテスト         | 3              |
| Watcher               | ユニット + スモーク    | 6              |
| Size/Time Props       | プロパティベーステスト | 2 (2000ケース) |

**注**: **スモークテスト** はシステム依存の関数（`is_available`, `is_atty`, 通知関数など）に対して、クラッシュしないことのみを確認するテストです。実際の戻り値や副作用は検証していません。

## Appendix: ビルド・インストールガイド

### 必要要件 (Prerequisites)

- **OCaml**: 5.0.0 以上 (5.2.0 推奨)
- **Opam**: OCaml パッケージマネージャ
- **Dune**: ビルドシステム

### OS別セットアップ手順

#### macOS

Homebrew を使用してインストールします。

```bash
# 1. Opamのインストール
brew install opam

# 2. Opamの初期化
opam init -y --shell=zsh
eval $(opam env)

# 3. OCaml 5.x 環境の作成 (既に最新が入っている場合はスキップ可)
opam switch create 5.2.0
eval $(opam env)

# 4. 依存パッケージのインストールとビルド
opam install . --deps-only --with-test -y
dune build
```

#### Linux (Ubuntu/Debian)

```bash
# 1. 必要なツールのインストール
sudo apt update
sudo apt install -y opam build-essential bubblewrap unzip

# 2. Opamの初期化
opam init -y --disable-sandboxing
eval $(opam env)

# 3. OCaml 5.x 環境の作成
opam switch create 5.2.0
eval $(opam env)

# 4. 依存パッケージのインストールとビルド
opam install . --deps-only --with-test -y
dune build
```

#### Windows

Quasifind は Unix 系のシステムコール (`mmap`, `dirent` の `d_type`, `lstat` など) に依存しているため、**WSL2 (Windows Subsystem for Linux)** 上での実行を強く推奨します。

1.  **WSL2 のインストール**: PowerShell (管理者) で `wsl --install` を実行し、Ubuntu をセットアップします。
2.  **Ubuntu 上でのセットアップ**: 上記の「Linux (Ubuntu/Debian)」の手順に従ってください。

※ 純粋な Windows 環境 (MinGW/MSVC) でのビルドは現在サポートしていません。

## ライセンス

MIT License
