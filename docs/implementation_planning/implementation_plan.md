# 実装計画: 設定ファイル機能 (Phase 8)

## 目標

`quasifind` の動作をカスタマイズするための設定ファイル機能を追加する。
主な要件：

1. ファジー検索のバックエンド選択 (`auto`, `fzf`, `builtin`)
2. グローバルな検索除外パターン

## 設定ファイル設計

### 場所

`XDG_CONFIG_HOME/quasifind/config.json`
(デフォルトは `~/.config/quasifind/config.json`)

### フォーマット

JSON形式。

```json
{
  "fuzzy_finder": "auto", // "auto", "fzf", "builtin"
  "ignore": ["_build", ".git", "node_modules", "**/*.o"]
}
```

## Proposed Changes

### [New Module] `Config` (`lib/quasifind/config.ml`)

- `type t` 定義
- `load : unit -> t` implementation (with default fallback)

### [Modify] `Interactive` (`lib/quasifind/interactive.ml`)

- `select` 関数にて、`Config.t` の設定に基づいて分岐するロジックを追加。
- 既存の `check_fzf_availability` との設定値の優先順位決定。
  - `auto`: 既存ロジック（fzfあれば使う）
  - `fzf`: 強制的にfzf（なければエラーまたは警告してbuiltin? -> エラーか警告が良いが、fallbackが無難か）
  - `builtin`: 強制的にbuiltin TUI

### [Modify] `Traversal` (`lib/quasifind/traversal.ml`)

- `traverse` 関数にて、ディレクトリ走査時に `config.ignore` パターンにマッチするファイル/ディレクトリをスキップするロジックを追加。
- glob パターンのマッチングには `dune` が依存している `re` ライブラリのGlob機能などが使えるか確認。ない場合は `Re.Glob` を使用。

### [Modify] `Main` (`bin/main.ml`)

- 起動時に `Config.load()` を呼び出し、各モジュールに渡す。

## Verification Plan

- 設定ファイルを作成し、`ignore` に指定したディレクトリが検索結果に出ないことを確認。
- `fuzzy_finder` を `builtin` に固定し、`fzf` があってもTUIが起動することを確認。
