# Artifact transfer restoration plan

## Goal

Restore structured LLM artifact transfer in current Vecherinka runtime.

Each model call must:

1. Receive typed inline input in prompt instructions.
2. Receive every input `Location` payload inside an isolated working directory.
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

## Revised architecture

Generated `Artifact` remains a data-only tagged union. Compile-time lowering
continues to construct and process `A` values without knowing runtime storage.

Runtime owns one artifact registry per `RuntimeContext`:

```nim
type ArtifactRecord*[A] = object
  data*: A
  meta*: ArtifactMeta

RuntimeContext[A].artifacts*: Table[ArtifactID, ArtifactRecord[A]]
```

`ArtifactRecord` is stored only in `RuntimeContext.artifacts`. Its key and
`meta.id` must match. An `A` may exist independently before registration; a
registration operation assigns or confirms its `ArtifactID`, attaches its
`ArtifactMeta`, and inserts the record.

Persistent runtime state stores references:

- `Activation` stores an input `ArtifactID`.
- `WorkNode` stores optional input/output `ArtifactID` values.
- `JoinState` stores result-slot IDs and original-input ID.
- `PendingModel` stores input ID plus reserved output identity/root.
- `WorkPlan` stores final output ID.
- events carry IDs, reservation metadata, or transport data, never copied
  artifact records.

At an execution boundary, the runtime resolves an ID to `ArtifactRecord`,
unwraps `data` as local `A`, and runs existing flow/model/lift code. Newly
created `A` values register when they become runtime-held. Pass-through paths
reuse their existing ID. Generated `Flow[A]` values, raw flow payloads, and
compile-time pack/unpack logic do not reference `ArtifactRecord`.

The record wrapper replaces paired `A` plus `ArtifactMeta` in runtime state;
it does not replace `A` in generated flow definitions or active computation.

## Registration and identity rules

- Initial input registers before the entry activation is queued.
- `fk_raw` registers its independently generated value when execution reaches
  the runtime handoff.
- `fk_it` and lift destructuring register newly produced values before they are
  queued or stored.
- `fk_so` pass-through reuses the current ID; a child-produced value follows
  normal registration rules.
- Fanout branches reuse the input ID.
- Join coalesce/construct results register as new values.
- Valid model output registers after schema validation and completion checks. Its fresh
  working root is reserved earlier for materialization.
- Failed or rejected model candidates never enter the artifact table.

`ArtifactID` is unique within one `RuntimeContext`. The table is main-thread
owned, append-oriented storage for the lifetime of that context. Reader
threads never access it.

`Location` remains a runtime-relative reference. This is required for joins
whose result can contain locations originating from multiple artifact roots.
The input record's metadata identifies provenance and the source root;
materialization resolves the location from the common runtime directory.
Current plan keeps path policy prompt-owned; no new runtime Location verifier is
part of this registry change.

## Current codebase snapshot

Already present:

- `ArtifactMeta`, runtime/run roots, and fresh model/join artifact directories;
- context-owned `ArtifactRecord` registry with `ArtifactID` lookup and
  registration invariants;
- ID propagation through activations, continuations, joins, pending models,
  nodes, final output, and runtime events;
- one-channel scheduler with typed activations retained in `pending_ready`;
- generated submit boundary carrying input `A`, `ArtifactMeta`, runtime root,
  working root, and materialized input;
- Codex POSIX readers, main-thread JSON ownership, shutdown joining, and
  existing dynamic-tool plumbing.

Still missing:

- resolved-record input materialization rework;
- schema-valid typed output decoding and record publication checks;
- generated `finish_work` tool/callback integration;
- artifact-aware real Codex transport and full failure/end-to-end coverage.

## Preserved boundaries

Keep `Flow[A]`, lazy activation, `Resume`, joins, generated tagged artifact
payloads, injected `LlmTransport`, and main-thread ownership.

Do not change generated `Flow[A]` storage to records. Do not replace current
scheduler with historical callback runtime. Port artifact behavior into current
runtime boundaries.

The generated submit adapter may continue receiving `input: A` and metadata as
ordinary processing arguments. Only persistent runtime storage changes to IDs
and registry records.

## Slice order

| Slice | Work | Status | Gate |
| --- | --- | --- | --- |
| 0 | Baseline and revised registry contracts | rework | Existing tests still pass; target invariants recorded |
| 1 | Registry, record creation, and ID-based runtime state | complete | All persistent artifact state uses IDs; records live in context table |
| 3 | Input materialization against resolved records | rework | Nested input renders/copies; generated lowering remains stable |
| 4 | Output schema, decoder, and record publication | partial | Valid output is registered; invalid output is not |
| 5 | Generated submit integration | partial | Minimal comptime change; transport receives resolved `A` data |
| 6 | `finish_work` event protocol | not started | Candidate validation/publish/acknowledgement is retry-safe |
| 7 | Real Codex transport | partial | Agent receives correct root; event loop uses IDs |
| 8 | Composition and ID transfer | rework | Fanout/lift/join chains preserve registry references |
| 9 | Failure lifecycle and cleanup | partial | No dangling IDs, records, pending work, or unsafe roots |
| 10 | End-to-end hardening | not started | Full registry and transfer matrix passes |

Slices may be committed independently. Each slice must leave current tests
green plus its own gate.

## Non-goals

- Generic serialization of arbitrary Nim input values.
- Passing absolute filesystem paths to model.
- Passing mutable artifact-directory ownership between calls.
- Moving JSON parsing into reader threads.
- Replacing current flow lowering or runtime ownership model with the
  historical callback runtime.
- Making generated `Flow[A]` values depend on runtime records.
- Optimizing copies with links, snapshots, or content-addressed storage.

## Final acceptance criteria

- Every runtime-held artifact has exactly one `ArtifactRecord` in the context
  table, keyed by its ID.
- Work nodes, joins, activations, pending models, and final output use IDs.
- Active computation still uses ordinary `A` values.
- Generated flows and compile-time pack/unpack remain data-only.
- Generated model submit materializes real input from a resolved record.
- Prompt includes inline input, strong runtime-relative `Location` instructions,
  output schema, and directory restriction.
- `finish_work` schema derives from actual output type.
- Invalid schema returns useful retry feedback and publishes no record.
- Valid output becomes typed `A`, then one registered artifact record.
- Chained calls copy previous locations into their own roots.
- Existing scheduler continuation/join/lift behavior remains intact.
- Readers remain transport-only.
- No malformed output reaches continuation.
