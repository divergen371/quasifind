---
id: TASK-7
title: 'Regex_cache / Intern: 例外発生時の Mutex アンロック漏れによるデッドロック修正'
status: To Do
assignee: []
created_date: '2026-11-18T13:03:00Z'
updated_date: '2026-11-18T14:28:00Z'
labels:
  - concurrency
  - regex
  - bug
milestone: m-0
dependencies: []
references:
  - lib/quasifind/regex_cache.ml
  - lib/quasifind/intern.ml
  - https://github.com/divergen371/quasifind/issues/7
priority: high
type: bug
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スレッドセーフキャッシュでロック解除に `Fun.protect` が使われておらず、例外発生時に永久デッドロックを引き起こす。

観測事実:
- lib/quasifind/regex_cache.ml (L8-19): `Mutex.lock mutex` の後で `Re.compile (Re.Pcre.re pattern)` を呼び、無効なパターン等で例外が発生すると `Mutex.unlock mutex` が実行されずロックが解放されない。以降の呼び出し（特に Daemon / IPC / 並列処理）が永久にハングする。
- lib/quasifind/intern.ml (L12-35): 同様に `Mutex.lock` / `Mutex.unlock` を裸で使用している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Regex_cache.compile および Intern.intern が Fun.protect ~finally:(fun () -> Mutex.unlock mutex) を用いて例外時も確実にロック解放すること
- [ ] #2 不正正規表現を Regex_cache.compile に渡して例外捕捉した後でも、次回以降の Regex_cache.compile が正常動作するテストが追加されること
<!-- AC:END -->
