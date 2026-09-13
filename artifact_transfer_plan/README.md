# Artifact transfer restoration plan

## Goal

Restore structured LLM artifact transfer in current Vecherinka runtime.

Each model call must:

1. Receive typed inline input in prompt instructions.
2. Receive every input `Location` payload inside isolated working directory.
3. Receive output JSON schema through `finish_work`.
4. Return only schema-valid typed output.
5. Use runtime-relative `Location` paths; never emit absolute or `..` paths;
   modify only the assigned working directory.
6. Produce output that next flow operation can consume through existing scheduler.

Source references:

- Design guide: `structured_llm_artifact_transfer_guide.md`.
- Historical implementation: `f2ad7bc:src/bezkonza_impl.nim`.
- Current generated lowering: `src/vecherinka_comptime.nim`.
- Current scheduler/event boundary: `src/vecherinka_runtime.nim`.
- Current Codex protocol owner: `src/codex_runtime.nim`.
- Current IPC constraints: `codex_runtime_posix_ipc_guide.md`.

## Current codebase snapshot

Implemented:

- metadata sidecar: `ArtifactMeta`, runtime/run roots, fresh model and join
  artifact directories;
- metadata propagation through activations, continuations, joins, pending
  models, nodes, and runtime events;
- one-channel scheduler: typed activations live in `pending_ready`, while
  `gek_ready` carries only an ID; runtime loop performs one blocking channel
  read;
- generated submit boundary carrying `input_meta`, `runtime_dir`, and
  `working_dir`; deterministic injected transport remains available;
- Codex POSIX readers, main-thread JSON ownership, shutdown joining, and
  existing dynamic-tool plumbing.

Still missing:

- recursive input materialization and path-based `Location` copying;
- typed output decoding;
- generated `finish_work` tool/callback integration;
- artifact-aware real Codex transport and full failure/end-to-end coverage.

## Design choices

### Preserve current runtime shape

Keep `Flow[A]`, lazy activation, `Resume`, joins, generated tagged artifact payloads, injected `LlmTransport`, and main-thread ownership.

Do not replace current scheduler with historical callback runtime. Port artifact behavior into current boundaries.

### Metadata sidecar

Current generated artifact union contains typed values only. Add sidecar metadata instead of making every generated artifact type contain filesystem state:

```nim
type ArtifactID* = uint64

type ArtifactMeta* = object
  id*: ArtifactID
  artifact_dir*: Path
```

Thread metadata beside typed values through activations, model state, joins, and completion events.

This keeps generated `Artifact` pack/unpack logic type-focused. `artifact_dir`
identifies the physical working directory for one model call. `Location`
strings are relative to the common runtime directory, so values from different
artifact directories remain directly composable.

### One fresh root per model call

Each model call gets a fresh destination root. Materialization copies payloads
into that root. Model output keeps that root. The source tree is not a
sandboxed immutability contract: the model is instructed to modify only its
working artifact directory. The `run-*` directory is intentionally created
under the program CWD and should be ignored by Git.

Initial input uses current process working directory as source root and as the
runtime-relative `Location` base. Runtime-created output roots live below one
run directory under that CWD.

### Main-thread coordination

Reader threads only frame stdout/stderr and enqueue events. Main owner performs:

- JSON parsing;
- Codex state mutation;
- dynamic-tool routing;
- schema parsing;
- tool acknowledgement;
- artifact delivery.

Dynamic tool callback queues a copied candidate event. It does not capture `WorkPlan` or mutate scheduler state.

### Two request IDs

Keep separate:

- scheduler model request ID, used to find pending model work;
- Codex server request ID, used to acknowledge `finish_work` call.

Never overload current `RuntimeEvent.request_id` for both.

## Slice order

| Slice | Work | Status | Gate |
| --- | --- | --- | --- |
| 0 | Baseline, contracts, progress tracking | complete | Existing tests compile/pass; no source behavior change |
| 1 | Artifact metadata and run-root allocation | complete | Metadata survives raw, `it`, `so`, joins; isolated roots verified |
| 3 | Compile-time materialization walker | not started | Nested input renders and copies correctly |
| 4 | Output schema and decoder | partial | Valid/invalid structured outputs handled without defaults |
| 5 | Generated submit integration | partial | Fake transport receives real materialized spec |
| 6 | `finish_work` event protocol | not started | Invalid calls retry; valid calls acknowledge and complete |
| 7 | Real Codex transport | partial | Thread-start ordering and working-directory isolation verified |
| 8 | Transfer through composition | complete | Multi-root routing is covered by runtime-relative locations; physical copying remains in Slices 3 and 5 |
| 9 | Failure lifecycle and cleanup | partial | Turn failure, process exit, missing completion, shutdown safe |
| 10 | End-to-end hardening | not started | Full test matrix, docs, progress closeout |

Slices may be committed independently. Each slice must leave current tests green plus its own gate.

## Non-goals

- Generic serialization of arbitrary Nim input values.
- Passing absolute filesystem paths to model.
- Passing mutable artifact directory ownership between calls.
- Moving JSON parsing into reader threads.
- Replacing current flow lowering or runtime ownership model with the
  historical callback runtime.
- Optimizing copies with links, snapshots, or content-addressed storage.

## Detailed execution plan

See `slices/00` through `slices/10`.

## Final acceptance criteria

- Generated model submit materializes real input.
- Prompt includes inline input, strong runtime-relative `Location` instructions,
  output schema, and directory restriction.
- `finish_work` schema derives from actual output type.
- Tagged output variants use discriminator-aware schema.
- Invalid schema returns useful retry feedback.
- Valid output becomes typed generated artifact.
- Every successful model output has fresh artifact metadata.
- Chained call copies previous locations into its own root.
- Existing scheduler continuation/join/lift behavior remains intact.
- Readers remain transport-only.
- No malformed output reaches continuation.
- Prompt instructions strongly constrain `Location` paths and working-directory ownership.
