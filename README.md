# Quasi-find

Quasi-find (findもどき)は、型付き DSL を用いてファイルシステムを検索する、OCaml + Zig 製のコマンドラインツールです。Unix の `find` コマンドの代替を目指していますが、より表現力の高いクエリ言語を提供します。

## 特長

- **型付き DSL**: `size > 10MB` や `mtime < 7d` のように、型安全な式で検索条件を記述できます。
- **高速な走査**: `Eio` を用いた並列走査により、大規模なディレクトリツリーも効率的に検索できます。
- **デーモンモード**: VFSをメモリ常駐させ、ファイルシステムの変更をリアルタイム追跡。繰り返しクエリが爆速に。
- **正規表現**: ファイル名やパスに対して PCRE 正規表現 (`=~`) を利用可能です。
- **直感的な単位**: `KB`, `MB`, `GB` や `s` (秒), `m` (分), `h` (時間), `d` (日) などの単位を直接扱えます。

## パフォーマンス

OCaml 5 のマルチコア並列処理と **Zig FFI** による低レベル最適化（SIMD、ゼロコピー、AST プッシュダウンフィルタリング）により、Rust 製の高速検索ツール `fd` を大幅に上回る速度を実現しています。

> ベンチマーク環境: 45万ファイル (37.5万実ファイル + 7.5万ディレクトリ) の合成ツリー
> パターン: `name =~ /[0-9]\.jpg$/` (約10万件ヒット)

| ツール                             | 実行時間 (平均) | 速度比 (vs find) | 備考                             |
| ---------------------------------- | --------------- | ---------------- | -------------------------------- |
| **quasifind (Daemon)** 🚀          | **302ms**       | **22.8x**        | VFS常駐 + TSV IPC ストリーミング |
| **quasifind (Parallel 「8並列」)** | 1.35s           | 5.1x             | `fd` とほぼ同等                  |
| **fd** (Rust)                      | 1.29s           | 5.3x             | 高速だが Daemon モードに大差     |
| **quasifind (DFS)**                | 1.88s           | 3.7x             | シングルスレッドでも高速         |
| **find** (Unix)                    | 6.90s           | 1.0x             | 基準                             |

### 高速化の技術的詳細 (Technical Highlights)

Quasifind は OCaml 5 の並列処理能力を最大限に引き出すため、以下の最適化を行っています。

1. **Multicore Parallelism & Work Stealing**:
   OCaml 5 の `Domain` と `Eio` を活用し、CPU コア数に応じた並列走査を行います。
   タスク分配にはロックフリーな Work-Stealing Deque (`Saturn`) を採用し、ディレクトリの偏り（巨大なサブツリーなど）があってもコアを遊ばせない動的なロードバランシングを実現しています。

2. **Native Readdir w/ d_type (Zig FFI)**:
   標準の `Sys.readdir` はファイル名のみを返し、ファイル種別（ディレクトリかファイルか）を知るために追加の `lstat` が必要でした。
   Quasifind は **Zig FFI** を用いて `dirent` 構造体の `d_type` フィールドを直接取得することで、多くのシステムで `lstat` をスキップし、システムコール発行数と GC 圧力を大幅に削減しています。

3. **Lazy Stat Optimization**:
   クエリ式を静的に解析し、ファイルサイズや更新日時などのメタデータが不要な場合（例: `name =~ /\.ml$/` のみの場合）、`lstat` 呼び出しそのものを省略します。
   これにより、Rust 製の `fd` と同等の「名前検索なら爆速」という挙動を実現しました。

4. **Mmap & Zero-Copy Regex (Zig SIMD)**:
   `content =~ /.../` によるファイル内容検索において、ファイルを `mmap` でメモリにマッピングし、**Zig 実装の SIMD 最適化正規表現エンジン** を直接適用する最適化を導入しています。
   これにより、巨大なファイルをOCamlのヒープに読み込むコスト（アロケーションとGC）を回避し、`grep` や `ripgrep` に迫るスループットを実現しています（レガシーな読み込み方式と比較してCPU効率が約8倍向上）。

5. **Daemon TSV IPC Streaming**:
   デーモンモードでは、検索結果を JSON ではなく **TSV (タブ区切り)** フォーマットでシリアライズし、**64KB の `Buffer.t` チャンクバッファ**に蓄積してから一括送信します。
   これにより、数万回の `Yojson.Safe.to_string` アロケーションと `writev` システムコールを数十回に削減し、IPC 通信のオーバーヘッドを事実上ゼロにしています。

6. **SIMD Hybrid Content Search (Zig NEON)**:
   `content =~ /.../` や `content == "..."` によるファイル内容検索で、**Zig の `@Vector` / ARM NEON SIMD** と **KMP/BMH ハイブリッドアルゴリズム**を組み合わせた高速スキャンを実装しています。
   16バイト幅で先頭+末尾バイトを同時比較する NEON pre-filter と、Boyer-Moore-Horspool skip table により、`grep -rl` の **3.7倍高速**な content 検索を実現しています。

7. **Hybrid Filter Push-down (AST → Zig)** 🆕:
   OCaml の型付き AST から、名前ベースのフィルタ条件（完全一致、拡張子サフィックス等）を静的に抽出し、Zig FFI レイヤーにプッシュダウンします。
   Zig 側で `strncmp`/`strcmp` によるゼロアロケーション・フィルタリングを実行し、条件に合致しないエントリは `caml_alloc` をスキップして即座に破棄します。
   これにより OCaml ヒープへのオブジェクト生成を 95%以上削減し、GC 圧力を劇的に低減させています。

8. **Extensive Parallel Scalability Tuning**:
   並列モード (`-j N`) 実行時の性能を極限まで引き上げるため、以下の最適化を施しています：
   - **ブロッキングセクションのバッチ化**: C(Zig)層での `readdir` 呼び出しごとに発生していた OCaml ドメインロックの着脱（`caml_enter/leave_blocking_section`）を、バッチチャンク全体で1回に集約し、数千回の Mutex 操作オーバーヘッドを完全に除去しました。
   - **初期タスクの事前分配**: トラバーサル開始時、ルートディレクトリの子階層をメインスレッドが全ワーカーのキューへラウンドロビン分配することで、ワーカー0へのアクセス集中を防ぎ、起動0秒後から全コアがフル稼働します。
   - **スピンバックオフ (Domain.cpu_relax)**: アイドル状態のワーカーがビジーウェイトしてメモリバスと CPU キャッシュを破壊しないよう、OCaml 5 固有の `Domain.cpu_relax()` (x86: `PAUSE`, ARM: `YIELD`) と `Eio.Fiber.yield` を組み合わせたハイブリッド・バックオフプロトコルを実装しています。

> [!NOTE]  
> **macOS での並列性能と VFS ロックについて**
> Quasifind のシングルスレッドは極めて高速化されているため、macOS 環境において並列オプション (`-j 8`等) を指定しても **2倍〜3倍程度の速度向上**に留まることがよくあります。
> これは、並列にシステムコール (`readdir` や `stat`) を発行すると、OS カーネル内部で **VFS (Virtual File System) レイヤのロック競合 (Contention)** が発生し、各スレッドがカーネル内で順番待ち（System タイムの肥大化）を引き起こすためです（Rust製 `fd` 等の極限最適化ツールでも同等の限界に直面します）。逆に言えば、シングルスレッド実行の時点で既に macOS のファイルシステム探索限界速度に近いパフォーマンスが出ていることを意味します。Linux 環境では並列スケールがより素直に反映される場合があります。
> この制約を回避するためにSpotlightから着想を得てデーモンモードを実装したという意図があります。

> [!NOTE]  
> **Linux 環境での並列性能について**  
> Linux 環境では、macOS とは異なりカーネルレベルでの VFS ロック競合が緩和されているため、Quasifind の並列オプション (`-j N`) はより素直にスケールします。CPU コア数に応じてスレッド数を増やすことで、**ほぼ線形に近い性能向上**が期待できます。これは、OCaml 5 の並列処理能力と Zig FFI による低レベル最適化が最大限に活かされる環境です。
> ちなみにApple Silicon搭載のMacOS Tahoeでは`-j 4`で実行すると
>
> ```
> Time (mean ± σ):     634.3 ms ±  28.5 ms    [User: 308.9 ms, System: 2124.6 ms]
> Range (min … max):   618.1 ms … 712.2 ms    10 runs
> ```
>
> という結果になります→並列実行時のコア数指定を廃止し自動選択するように変更しました。

### `fd` との違い (.gitignore の扱い)

`fd` と `quasifind` の最大の挙動の違いは、`.gitignore` ファイルの扱いです。

- **fd**: 探索中に各ディレクトリの `.gitignore` を動的に読み込み、その階層以下のルールを適用します。これにより Git の管理外ファイルを正確に隠せますが、ファイル読み込みのオーバーヘッドが発生します。
- **quasifind**: パフォーマンスと明確さを優先し、**静的な除外リスト**（デフォルトで `.git`, `_build`, `node_modules` など）のみを使用します。サブディレクトリ内の `.gitignore` は読み込みません。
  - プロジェクト固有の除外ルールがある場合は、設定ファイル (`config.json`) の `ignore` リストに追加してください。

## ⚠️ 現在の課題と仕様上の注意 (Caveats)

現行バージョンの `quasifind` は、強力なクエリエンジン（ASTパースによる型付きDSL）を搭載していますが、**人間のエンジニアが純粋なターミナル CLI ツールとして手動で叩くには非常に使いづらい**という課題があります。

1. **クォーテーションのネストとエスケープ**: シェル上で DSL をパースさせるため、式全体を `' '` で囲みつつ内部の文字列を `" "` で囲む必要があり、正規表現のエスケープ等を含めるとタイポを誘発しやすくなっています。
2. **引数とパースの厳格さ**: `[DIR] [EXPR]` という引数順序や、DSL内の空白などのレキサー規則が極めて厳格であり、少しでも既存の `find` の感覚でフラグベースの入力（`-name` 等）を行うと即座に Syntax Error で弾かれます。

現在の開発フェーズでは **「AI に最適化された GUI ファイルマネージャーのバックエンド検索エンジン」** としての役割に特化して割り切っており、将来的に人間向けの「シンタックスシュガーオプション（`-name`等を透過的にDSLへ変換する層）」を追加することでこの体験を改善する予定です。

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

検索結果からファイルをインタラクティブに選択して操作:

```bash
# 結果から一つ選んでパスを表示 (vim $(quasifind -i .) 等に便利)
quasifind -i . 'name =~ /\.ml$/'

# 選択したファイルにのみコマンドを実行
quasifind -i . 'size > 10MB' -x "ls -lh {}"
```

履歴の一覧を表示:

```bash
quasifind history
```

**組み込みのファジー検索もそれなりに快適に動作しますが、しばしばTUIの崩れが発生するためFZFを推奨します。**

#### 組み込みファジーマッチャーのアルゴリズム解説

quasifind の組み込みファジー検索は、**Smith-Waterman アルゴリズム**をベースに、ファイルパス検索向けにチューニングした独自実装 (`fuzzy_matcher.ml`) を使用しています。

##### Smith-Waterman アルゴリズムとは？

元々は DNA・タンパク質の配列アライメントのために開発されたアルゴリズムです。2つの文字列の**局所的に最も類似した部分**を動的計画法で高精度に探索します。`fzf` などの著名なファジーファインダーも同様の考え方を採用しています。

quasifind では、バイオインフォマティクス用途と異なり「クエリ全体が候補の**部分列 (subsequence)** であること」を前提として、アライメントの向きを修正しています。

##### スコアリングのパラメータ

| パラメータ           | 値    | 意味                                            |
| -------------------- | ----- | ----------------------------------------------- |
| `score_match`        | `+10` | クエリと候補の文字が一致                        |
| `score_mismatch`     | `-1`  | 不一致（使用箇所は限定的）                      |
| `boundary_bonus`     | `+5`  | 単語境界 (`/`, `_`, `-`, `.` 等の直後) での一致 |
| `camel_bonus`        | `+5`  | キャメルケースの大文字での一致                  |
| `gap_open_penalty`   | `-3`  | ギャップ（スキップ）の開始ペナルティ            |
| `gap_extend_penalty` | `-1`  | ギャップ延長のペナルティ（1文字毎）             |

##### DP (動的計画法) の詳細

```
DP[i][j] = クエリの i 番目の文字が、候補の j 番目の文字に対応する時の最良スコア
```

クエリの各文字 `query[i]` について:

1. **連続マッチ（Contiguous）**: `query[i]` が `candidate[j]` に一致し、かつ直前の一致が `candidate[j-1]` にある場合、`+5` の連続性ボーナスを追加。連続した部分文字列のマッチを高く評価します（例: `ml` → `.ml$` の `.ml` 部分）。

2. **ギャップマッチ（Gapped）**: `query[i]` が `candidate[j]` に一致するが、間にスキップがある場合。ギャップ開始ペナルティ (`-3`) とギャップ延長ペナルティ (`-1 × スキップ文字数`) を適用します。

両方の候補のうちスコアが高い方を `DP[i][j]` として採用します。

##### 境界ボーナスの役割

パス文字列 `src/lib/fuzzy_matcher.ml` に対して `fm` を検索する場合：

- `fuzzy_matcher` の先頭 `f` は `/` の直後 → **+5 境界ボーナス**
- `fuzzy_Matcher` の大文字 `M` → **+5 キャメルケースボーナス**（大文字へのマッチ）

これにより、パスの末尾・ディレクトリ名の先頭・キャメルケース区切りなど、人間が「ここが重要な区切り」と感じる部分でのマッチが高スコアになります。

##### 部分列チェックによる事前刈り込み

スコア計算（O(M×N) の DP）の前に、クエリが候補の**部分列かどうかを O(M+N) で確認**します。部分列でない場合は即座に `None` を返し、DP のコストを回避します。大量の候補を絞り込む際の重要な最適化です。

##### ランキングロジック

```ocaml
(* スコアで降順ソート。スコアが同じ場合は候補の文字列長が短い方を優先 *)
List.sort (fun (s1, c1) (s2, c2) ->
  if s1 <> s2 then compare s2 s1
  else compare (String.length c1) (String.length c2)
) scored
```

スコアが同じ場合、文字列が短い候補を優先します。これにより、同等のマッチ質なら冗長なパスより短いパスが上位に来ます。

#### コンテンツ検索 (grep alternative)

`content` フィールドを使うと、**`grep -rl` の代替**として使えます。
ARM NEON SIMD + KMP/BMH ハイブリッドアルゴリズムにより `grep -rl` の約 **3.7倍高速**です。

ファイル内容に "TODO" を含むファイルを検索:

```bash
quasifind -j 8 . 'content =~ /TODO/'
```

正規表現で特定パターンを含む ML ファイルだけを検索:

```bash
quasifind -j 8 . 'content =~ /raise\s+Invalid/ && name =~ /\.ml$/'
```

最近変更されたファイルで特定の文字列が残っていないか確認:

```bash
quasifind -j 8 . 'content == "FIXME" && mtime < 7d'
```

> **`grep` との違い**: `quasifind` は名前・サイズ・日時のフィルタを content 検索と**同時に適用**できるため、
> `find | xargs grep` のようなパイプが不要です。1コマンドで `find` + `grep` を統合しつつ、両方より高速です。

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
   quasifind /var/www 'name =~ /\.php$/ && content =~ /eval\(base64/'
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

#### 怪しいファイル探索 (`--suspicious`)

組み込みのヒューリスティックルールを用いて、侵害の兆候があるファイルを自動的に検出します。

- 隠し実行ファイル (`.exe`, `.sh` など)
- 危険な権限 (777, SUID)
- `/tmp` 配下の巨大ファイル
- 削除されたのに開かれているファイル (Ghost)

```bash
quasifind / --suspicious
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
- `-i`, `--interactive`: 検索結果をインタラクティブなUI (fzf / builtin) に渡し、選択されたファイルを出力またはコマンド実行します。
- `-j JOBS`, `--jobs=JOBS`: 並列実行するジョブ数（スレッド数）を指定します。デフォルトは 1 です。
- `-L`, `--follow`: シンボリックリンクを追跡します。
- `-x CMD`, `--exec=CMD`: 各検索結果に対してコマンドを実行します。`{}` はパスに置換されます。
- `-X CMD`, `--exec-batch=CMD`: すべての検索結果を引数としてコマンドを一度だけ実行します。`{}` は全パス（スペース区切り）に置換されます。
- `-E PATTERN`, `--exclude=PATTERN`: 指定したパターン（glob）にマッチするファイルを除外します。複数指定可能。
- `-p NAME`, `--profile=NAME`: 保存したプロファイルを読み込んで実行します。
- `--save-profile=NAME`: 現在の検索オプションをプロファイルとして保存します。
- `-w`, `--watch`: ウォッチモード。ファイルシステムの変更を監視し、条件にマッチする新規/変更ファイルを通知します。
- `--interval=SECONDS`: ウォッチモードのスキャン間隔（秒）。デフォルトは 2 秒。
- `--suspicious`: 怪しいファイルを自動検出するプリセットモードです。
- `--check-ghost`: Ghostファイル（削除済みだが開かれているファイル）を検出します（単体で使用可能）。
- `--update-rules`: 信頼できる外部ソースから最新の検出ルールをダウンロード・更新します。
- `--reset-rules`: ヒューリスティックルール (`rules.json`) をデフォルトの状態にリセットします。
- `--reset-config`: 設定ファイル (`config.json`) をデフォルトの状態にリセットします。
- `--log=FILE`: ウォッチモード等のイベントログをファイルに出力します。
- `--webhook=URL`: イベント発生時に指定URLへPOSTリクエストを送信します。
- `--email=ADDR`: イベント発生時にメールを送信します（要sendmail）。
- `--slack=URL`: Slack Incoming Webhook URLへ通知を送信します。
- `--daemon`: デーモンモードを使用します（下記参照）。

### デーモンモード (Daemon Mode) 🚀 New!

デーモンモードは、VFS (Virtual File System) をメモリ上に常駐させ、ファイルシステムの変更をリアルタイムで追跡することで、**大幅に高速化されたクエリ**を実現します。

#### 起動と使用

```bash
# デーモンを起動（バックグラウンドで実行）
quasifind daemon &

# デーモン経由で検索（通常の検索と同じ構文）
quasifind . 'name =~ /\.ml$/' --daemon
quasifind . 'content =~ /TODO/' --daemon
quasifind . 'entropy > 7.5' --daemon
```

#### 特徴

- **Adaptive Radix Tree (ART)**: 高速なパス検索のための最適化されたツリー構造
- **Persistent Cache**: シャットダウン時にVFSを `~/.cache/quasifind/daemon.dump` に保存し、再起動時に復元
- **Hybrid Search**: メタデータ（名前、サイズ、時刻）はVFSから即座に取得し、コンテンツ/エントロピーはディスクにフォールバック
- **Full Regex Support**: 正規表現クエリもIPC経由で完全にサポート

#### デーモン管理

```bash
# ステータス確認
quasifind stats --daemon

# 停止（IPCソケット経由）
echo '{"type":"shutdown"}' | nc -U ~/.cache/quasifind/daemon.sock
```

> [!NOTE]
> デーモンモードは現在 **実験的機能** です。フィードバックをお待ちしています。

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
| Watcher               | ユニット + スモーク    | 6              |
| **ART (Daemon)**      | ユニットテスト         | 5              |
| **VFS (Daemon)**      | ユニットテスト         | 5              |
| **IPC (Daemon)**      | ユニットテスト         | 5              |
| Size/Time Props       | プロパティベーステスト | 2 (2000ケース) |

**注**: **スモークテスト** はシステム依存の関数（`is_available`, `is_atty`, 通知関数など）に対して、クラッシュしないことのみを確認するテストです。実際の戻り値や副作用は検証していません。

## Appendix: ビルド・インストールガイド

### 必要要件 (Prerequisites)

- **OCaml**: 5.0.0 以上 (5.2.0 推奨)
- **Zig**: 0.14 以上 (0.15.x 推奨) — FFI スタブのビルドに必要
- **Opam**: OCaml パッケージマネージャ
- **Dune**: ビルドシステム

### OS別セットアップ手順

#### macOS

Homebrew を使用してインストールします。

```bash
# 1. Opamのインストール
brew install opam zig

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

# 2. Zigのインストール (https://ziglang.org/download/)
# snap, asdf, もしくは公式バイナリでインストール

# 3. Opamの初期化
opam init -y --disable-sandboxing
eval $(opam env)

# 4. OCaml 5.x 環境の作成
opam switch create 5.2.0
eval $(opam env)

# 5. 依存パッケージのインストールとビルド
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
