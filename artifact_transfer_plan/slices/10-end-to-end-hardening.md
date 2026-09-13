# Slice 10 — end-to-end hardening

## Purpose

Verify complete structured transfer with context-owned ArtifactRecord storage
and ID-only persistent runtime state.

## Status

Not started.

## Work

1. Run all current Nim tests.
2. Run registry, materialization, decoder, protocol, and lifecycle tests.
3. Run generated macro tests under default memory management.
4. Run under ARC and ORC if supported.
5. Run with threads and panics enabled.
6. Run deterministic fake end-to-end chains.
7. Run real Codex end-to-end with task-local state variables.
8. Inspect generated source for scalar, variant, sequence, option, and Location
   types; confirm no ArtifactRecord references.
9. Remove unconditional schema/debug echo calls.
10. Document final registry, ID, Location, and cleanup contracts.
11. Update PROGRESS.md with commands, results, and remaining issues.

## Final test matrix

- compile-only interface tests;
- generated lowering tests;
- scheduler execution tests;
- registry registration and lookup tests;
- input materialization tests;
- output decoder and publication tests;
- dynamic tool protocol tests;
- fake transport tests;
- real Codex integration test;
- shutdown/reader tests;
- chained ID transfer tests;
- branch/join tests;
- failure and cleanup tests.

## Done when

Every runtime-held artifact has one context-table record. Persistent scheduler
state contains only IDs. Active processing still uses A. All acceptance
criteria in README.md pass.
