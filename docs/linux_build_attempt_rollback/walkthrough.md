# 作業完了確認 (Walkthrough) - Linux ビルド互換性の検討と macOS 専用化の決定

## 概要
Quasifind を Linux 環境でもビルド可能にするための試行を行いましたが、システムレベルの C 構造体 (`struct stat`) の差異や Zig クロスコンパイル環境でのリンクの複雑性が判明しました。これに伴い、保守コストとパフォーマンスの観点から **Linux 対応を放棄 (Abandoned) し、macOS (Apple Silicon) 専用ツールとして開発を継続する** ことを決定しました。

## 実施内容

### 1. Linux ビルドの試行と課題の特定
- Docker (Ubuntu 22.04 + Zig 0.14.0) を用いた Linux ビルド環境の構築。
- `lib/dune` での OS 条件分岐 (`uname -s`) の実装。
- **発生した課題**:
    - `struct stat` のフィールド名 (`st_mtimespec` vs `st_mtim`) やマクロ (`st_mtime`) の解決が Zig の `@cImport` 経由では困難。
    - 共有ライブラリ生成時のリンカフラグ (`-undefined dynamic_lookup`) が Linux に存在せず、OCaml ランタイム関数の参照解決が複雑化。

### 2. コードのロールバック
- Linux 対応のために一時的に加えた `lib/dune` および `lib/quasifind/dirent_stubs.zig` の変更を破棄。
- macOS 最適化が施された元の正常動作するコード状態に復元 (`git restore`)。
- テスト用の `Dockerfile.test` を削除。

### 3. README とドキュメントの更新
- `README.md` に **macOS (Apple Silicon) 専用** である旨の警告を追記。
- なぜ Linux 対応を断念したのかについての技術的な詳細（CレイヤーのOS間格差、リンカの依存問題など）を明記し、今後の開発方針を明確化。
- Linux および Windows (WSL) 向けのインストール手順を削除。

## 検証結果

- **macOS (ホスト)**: `dune build` および `dune runtest` が正常に通過し、既存の最適化が維持されていることを確認。
- **README**: ユーザーによる内容確認とコミット・プッシュを完了。

## 今後の展望
- バックエンドのマルチプラットフォーム対応にリソースを割く代わりに、当初の目的である **GUI ファイルマネージャーの検索エンジン** としてのフロントエンド開発・連携に注力します。
