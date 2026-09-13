# Slice 7 — real Codex transport

## Purpose

Run one artifact-aware agent turn while preserving registry ownership and ID
references.

## Status

Partial. Codex lifecycle and readers exist; real artifact-aware turns are not
integrated.

## Work

1. Keep deterministic fake transport as explicit test seam.
2. Add real transport for LlmCallSpec.
3. Resolve model input ID before generated submit.
4. Create agent with generated dynamic tools and fresh working directory.
5. Store pending thread-start action keyed by model request ID.
6. Wait for thread-start response.
7. Set goal and send prompt only after thread ID exists.
8. Route finish_work calls to central event handling.
9. Publish valid output record, then resume using its ArtifactID.
10. Route transport errors to terminal model failure.

RuntimeContext.artifacts remains main-thread owned. Reader threads only enqueue
copied transport events.

## Test gate

- no prompt appears before thread ID;
- agent receives correct working directory;
- dynamic tool schema reaches Codex request;
- tool call reaches finish-work event;
- successful turn adds exactly one output record;
- stdout/stderr readers remain independent;
- shutdown is safe with pending IDs.
