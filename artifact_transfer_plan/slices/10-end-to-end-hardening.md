# Slice 10 — end-to-end hardening

## Purpose

Run complete matrix, remove debug-only behavior from default path, document final contract.

## Status

Not started. Current tests cover runtime scaffolding and generated debug
transport, not complete artifact transfer.

## Work

1. Run all current Nim tests.
2. Run artifact unit tests.
3. Run generated macro tests under default memory management.
4. Run under ARC and ORC if supported.
5. Run with `--threads:on` and `--panics:on`.
6. Run deterministic fake end-to-end chain.
7. Run real Codex end-to-end with task-local state variables.
8. Inspect generated source for representative scalar, variant, sequence, option, and location types.
9. Remove unconditional schema/debug `echo` calls.
10. Update guide or adjacent runtime plan with final deviations from historical implementation.
11. Update `PROGRESS.md` with test commands, results, remaining issues.

## Final test matrix

- compile-only interface tests;
- generated lowering tests;
- scheduler execution tests;
- input materialization tests;
- output decoder tests;
- dynamic tool protocol tests;
- fake transport tests;
- real Codex integration test;
- shutdown/reader tests;
- chained artifact transfer tests;
- branch/join tests.

## Done when

All acceptance criteria in `README.md` pass. `PROGRESS.md` marks every
completed slice and records that multi-root routing is already provided by
runtime-relative `Location` paths.
