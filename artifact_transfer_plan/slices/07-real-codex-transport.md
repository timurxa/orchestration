# Slice 7 — real Codex transport

## Purpose

Use current `CodexRuntime` to run one artifact-aware agent turn.

## Files

- `src/vecherinka_runtime.nim`
- `src/codex_runtime.nim`
- transport integration tests

## Work

1. Keep deterministic fake transport available by explicit injection.
2. Add real transport path for `LlmCallSpec`.
3. Create agent with generated dynamic tools.
4. Give agent artifact directory as thread working directory.
5. Store pending thread-start action keyed by agent/model request.
6. Wait for thread-start response.
7. Set explicit goal after thread ID exists.
8. Send actual turn prompt only after thread ID exists.
9. Route tool calls through current dynamic-tool lookup.
10. Route all completion/error events to central runtime.

Current `create_agent` uses runtime-wide `cwd`; add optional per-agent working directory while preserving existing callers.

Do not send prompt from `create_agent` call. Do not send before thread ID.

## Test gate

- synthetic thread-start response triggers pending prompt exactly once;
- no prompt appears before thread ID;
- agent receives correct working directory;
- dynamic tool schema reaches Codex request;
- tool call reaches finish-work event;
- stdout/stderr readers remain independent;
- fake protocol process can run without network;
- real end-to-end run succeeds when local Codex state/network available.

## Done when

One real model call can create files, call `finish_work`, and complete scheduler node.

