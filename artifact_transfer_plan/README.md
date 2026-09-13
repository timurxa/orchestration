# Artifact transfer restoration plan

## Goal

Restore structured LLM artifact transfer in current Vecherinka runtime.

Each model call must:

1. Receive typed inline input in prompt instructions.
2. Receive every input `Location` payload inside isolated working directory.
3. Receive output JSON schema through `finish_work`.
4. Return only schema-valid typed output.
5. Return only `Location` values pointing to existing files/directories below its artifact directory.
6. Produce output that next flow operation can consume through existing scheduler.

Source references:

- Design guide: `structured_llm_artifact_transfer_guide.md`.
- Historical implementation: `f2ad7bc:src/bezkonza_impl.nim`.
- Current generated lowering: `src/vecherinka_comptime.nim`.
- Current scheduler/event boundary: `src/vecherinka_runtime.nim`.
- Current Codex protocol owner: `src/codex_runtime.nim`.
- Current architecture constraints: `vecherinka_runtime_system_plan.md` and `codex_runtime_posix_ipc_guide.md`.

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

This keeps generated `Artifact` pack/unpack logic type-focused. `Location` strings remain relative references inside `artifact_dir`.

### One fresh root per model call

Input artifact remains immutable. Each model call gets a fresh destination root. Materialization copies payloads into that root. Model output keeps that root.

Initial input uses current process working directory as source root. Runtime-created output roots live below one run directory.

### Main-thread validation

Reader threads only frame stdout/stderr and enqueue events. Main owner performs:

- JSON parsing;
- Codex state mutation;
- dynamic-tool routing;
- schema parsing;
- `Location` verification;
- tool acknowledgement;
- artifact delivery.

Dynamic tool callback queues a copied candidate event. It does not capture `WorkPlan` or mutate scheduler state.

### Two request IDs

Keep separate:

- scheduler model request ID, used to find pending model work;
- Codex server request ID, used to acknowledge `finish_work` call.

Never overload current `RuntimeEvent.request_id` for both.

## Slice order

| Slice | Work | Gate |
| --- | --- | --- |
| 0 | Baseline, contracts, progress tracking | Existing tests compile/pass; no source behavior change |
| 1 | Artifact metadata and run-root allocation | Metadata survives raw, `it`, `so`, joins; isolated roots verified |
| 2 | Safe path helpers | Traversal, absolute path, symlink, missing path tests pass |
| 3 | Compile-time materialization walker | Nested input renders and copies correctly |
| 4 | Output schema, location contract, decoder | Valid/invalid structured outputs handled without defaults |
| 5 | Generated submit integration | Fake transport receives real materialized spec |
| 6 | `finish_work` event protocol | Invalid calls retry; valid calls acknowledge and complete |
| 7 | Real Codex transport | Thread-start ordering and working-directory isolation verified |
| 8 | Transfer through composition | Chained model, fanout, lift, and root merge behavior verified |
| 9 | Failure lifecycle and cleanup | Turn failure, process exit, missing completion, shutdown safe |
| 10 | End-to-end hardening | Full test matrix, docs, progress closeout |

Slices may be committed independently. Each slice must leave current tests green plus its own gate.

## Non-goals

- Generic serialization of arbitrary Nim input values.
- Passing absolute filesystem paths to model.
- Passing mutable artifact directory ownership between calls.
- Moving JSON parsing into reader threads.
- Rewriting flow lowering or scheduler architecture.
- Optimizing copies with links, snapshots, or content-addressed storage.

## Detailed execution plan

See `slices/00` through `slices/10`.

## Final acceptance criteria

- Generated model submit materializes real input.
- Prompt includes inline input, location contract, output schema, and directory restriction.
- `finish_work` schema derives from actual output type.
- Tagged output variants use discriminator-aware schema.
- Invalid schema or filesystem result returns useful retry feedback.
- Valid output becomes typed generated artifact.
- Every successful model output has fresh artifact metadata.
- Chained call copies previous locations into its own root.
- Existing scheduler continuation/join/lift behavior remains intact.
- Readers remain transport-only.
- No malformed output reaches continuation.
- No unsafe location escapes artifact root.

