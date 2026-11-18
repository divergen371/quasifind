---
id: TASK-2
title: 'Zig FFI (search_stubs): NEON SIMD の 1バイト・オーバーリードおよび POSIX ERE/PCRE 不一致の修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - zig-ffi
  - simd
  - regex
  - bug
milestone: m-0
dependencies: []
references:
  - lib/quasifind/search_stubs.zig
  - lib/quasifind/eval.ml
  - https://github.com/divergen371/quasifind/issues/2
priority: high
type: bug
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
content 検索用の Zig スタブに境界外読み出しバグと正規表現仕様の不一致がある。

観測事実:
1. search_stubs.zig (L138 simd_memmem_neon): ループ条件 `i + 31 + nlen - 1 <= hlen` の `- 1` により、u=1 の `haystack[offset + nlen - 1 .. offset + nlen - 1 + 16]` が `hlen` を最大 1 バイト超過してアクセスする（例: nlen=4, hlen=34 で index 34 を読む）。ページ境界ファイルで SIGSEGV/SIGBUS の原因となる。
2. search_stubs.zig (L238 ac_lite_search_neon): 同様に `i + 15 + plen - 1 <= hlen` の `- 1` により 1 バイト・オーバーリードが発生する。
3. search_stubs.zig (L286 caml_search_regex): `c.regcomp(..., REG_EXTENDED | REG_NOSUB | REG_NEWLINE)` を使用しているため、PCRE 構文（\s, \d, \w, (?:...), (?i), 先読み等）が POSIX ERE として誤解釈（例: \s が文字 s にマッチ）され、OCaml 側 Re.Pcre と結果が食い違う。
4. search_stubs.zig (L290-315, L356-380): fstat 後の `S_ISREG` チェックが無く特殊ファイルを開いてしまうほか、caml_search_regex 側に 256MB 上限チェックが無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 simd_memmem_neon および ac_lite_search_neon の境界条件から誤った - 1 を除去し、任意のファイル長（特に 16/32/4096 バイト境界）で範囲外読み出しが発生しないこと
- [ ] #2 content =~ /.../ で \s, \d, \w, (?i) などの PCRE パターンが POSIX ERE による誤マッチを起こさず OCaml 側 Re.Pcre と一致する結果を返すこと（PCRE2 導入または非 POSIX 構文の Fallback 判定）
- [ ] #3 通常ファイル以外 (S_ISREG 偽) や上限超過ファイルが安全に処理・フォールバックされること
<!-- AC:END -->
