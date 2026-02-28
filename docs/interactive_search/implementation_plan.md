# Interactive Search (`--interactive` / `-i`)

Quasifindの通常のファイル検索結果から、Interactiveモード（Fuzzy Finder）を用いて直感的にファイルを一つ選び出す機能を追加します。これは履歴検索 (`history --exec`) で好評だったFuzzy Finderを、本チャンのファイル検索にも昇格させるものです。

## Goal
`quasifind -i <EXPR>`（または `--interactive`）オプションを追加し、検索でヒットしたファイル一覧をInteractive TUI（fzfまたはbuiltin）に渡し、ユーザーが絞り込み・選択できるようにする。

## User Review Required
- `quasifind -i` で1つのファイルを選択した後、**標準出力にそのパスを出力する**挙動でよいか。  
  （これにより `vim $(quasifind -i .)` のような使い方が可能になります）
- `-i` と `-x` (`--exec`) が同時に指定された場合、Interactiveモードで選択された**1つのファイル**に対してのみ指定コマンドを実行する、という動作仕様でよいか。

## Proposed Changes

### CLI
#### [MODIFY] [main.ml](file:///Users/atsushi/OCaml/quasifind/bin/main.ml)
- CLI引数に `interactive` (`-i`, `--interactive`) のflagを追加。
- 検索処理の終盤で結果を出力するループ (`Consumer Fiber`) または全体のアグリゲーション後に、`interactive` が true であれば `Interactive.select` を呼び出すロジックを追加。
- (並行処理ストリームの都合上、Interactiveモードの場合はストリームから拾った結果を一旦Listにバッファリングし、全探索完了後にFuzzy Finderを起動する形にします。)
- Interactiveモードでの選択結果に応じた出力（または `--exec` の実行）を行う。

### Documentation
#### [MODIFY] [README.md](file:///Users/atsushi/OCaml/quasifind/README.md)
- `--interactive` (`-i`) オプションの解説を追加。
- 使用例（例: `vim $(quasifind -i . '.ml')` など）を追加。
#### [MODIFY] [README.ja.md](file:///Users/atsushi/OCaml/quasifind/README.ja.md)
- 同じく日本語版ドキュメントにも追加。

## Verification Plan

### Automated Tests
- `test_props.ml` または `test_config.ml` などで、新たに加わる引数のパースが壊れていないかをチェック。
- Interactiveな部分は自動テストが難しいため、内部のロジック（例えば `Interactive.select` の呼び出し準備）に関する単体テストを補助的に確認。

### Manual Verification
1. `dune exec -- quasifind -i . 'name =~ /.*\.ml$/'` を実行し、TUIが起動してOcamlファイル一覧が絞り込めることを確認。
2. 絞り込んでEnterを押すと、そのファイルパスのみが標準出力に出力されることを確認。
3. `fzf` がインストールされている環境とされていない環境（builtinへのフォールバック）の両方で動作確認（すでに履歴機能で実績あり）。
4. `dune exec -- quasifind -i -x "echo {}" . 'name = "main.ml"'` のように `--exec` を組み合わせた際、選択した1ファイルのみに対して echo が実行されるか確認。
