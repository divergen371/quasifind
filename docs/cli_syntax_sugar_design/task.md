# CLI Syntax Sugar Implementation Tasks

- [x] Cmdlinerフラグの追加 (-n, --iname, -e, -t, -s, -m, -c)
- [x] DSL文字列生成ロジックの実装
- [x] 推論ロジックの実装（-s, -c 使用時の type == file 自動付与）
- [x] パーサーのバックスラッシュ処理の修正
- [x] Zig側のプッシュダウンフィルタのバグ修正（ディレクトリをフィルタ対象から除外）
- [x] 動作確認とデバッグ出力のクリーンアップ
- [x] Implement query string builder `build_sugar_expr`
  - Translate glob/extension to regex
  - Implicitly add `type == file` for size and content
  - Append all conditions with `&&`
- [x] Integrate converter into `search` function
  - Combine generated syntax sugar string with explicit `expr_str` if present
- [x] Test the new flags with `dune exec`
- [x] Create walkthrough.md with verification results
