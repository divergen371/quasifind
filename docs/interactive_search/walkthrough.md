# Interactive Search Integration Walkthrough

## Summary
Interactive file selection Mode (`quasifind -i` or `--interactive`) has been fully integrated into the quasifind CLI.
It retrieves all matched files into a list, buffers them, and then prompts user selection through built-in TUI (default) or `fzf`.
A single selection leads either to piping back into standard output (convenient for downstream commands like `vim $(quasifind -i .)`) or, if the `-x` / `--exec` configuration is specified, executing that specific templated command solely on the selected file.
A bug in the built-in fuzzy scoring algorithm was discovered and fixed, improving default TUI ranking behavior significantly.
The builtin preview also properly handles limiting file reads and neutralizing terminal corrupting binary characters automatically via Unix utilities.

## Changes Made
- Modified `bin/main.ml`: Added `-i` & `--interactive` as a cmdliner argument. `search` function now accepts `interactive_mode` to activate buffering instead. Default Interactive algorithm was updated to `Builtin` when matching directly from `bin/main.ml`.
- Fixed `lib/quasifind/fuzzy_matcher.ml`: Fixed sign algebra error that was mistakenly applying gap extension *bonuses* instead of *penalties*, leading to disconnected results ranking highly. Query ranks accurately.
- Added interactive collection behavior: Results are gathered in a list (`interactive_candidates`) safely during the `Eio` stream read instead of being directly printed.
- Configured selection behavior: Passing gathered candidates to `Interactive.select`, overriding the output format options. `--exec` argument logic behaves correctly (executing *only* on the selection) when present.
- Improved fallback for previews: Replaced naive `cat` with `head -n 100 {} 2>/dev/null | cat -v || echo "Not a readable file"` in standard interaction flow to prevent lag on big files, fatal terminal escapes sequence corruption upon encountering raw binary objects, and stderr leaks on directories.
- Disambiguated TUI visual layout: Added a bold `[ Preview: filename.ext ]` header on the first line of the builtin preview pane. This prevents user confusion where the right pane preview content was mistakenly thought to be a per-row descriptor rather than applying entirely to the currently selected active row.
- Added documentation: the README.md now explains `-i` option, presenting cookbook examples combining `-i` with shell pipelines & `quasifind -i -x`. (The Japanese README wasn't found in current directory).

## Tests Validated
1. Verified `-i` CLI parsing correctly filters and waits for `Builtin/fzf` selection in TTY testing mode (`dune exec -- quasifind -i . 'name =~ /.*\.ml$/' < /dev/tty > /dev/tty`).
2. Confirmed `-i` correctly interacts with `-x` flag so single instances process the `-x "echo {}"` template via manual command testing.
3. Tests run without regressions (`dune build`, `dune runtest`). Cmdliner parameter tests themselves aren't actively tested via ALCOTEST.
4. Added programmatic unit scoring tests directly assessing relative `ast.ml` VS `fsevents_stubs.c` string evaluation to standard test loops in `test/test_interactive.ml`.
