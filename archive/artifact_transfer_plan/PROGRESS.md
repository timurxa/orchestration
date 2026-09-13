# Artifact transfer progress

Last updated: 2026-09-13; revised Slice 1 complete toward context-owned
ArtifactRecord storage.

## Architecture revision

Previous Slice 1 and Slice 3 records describe old sidecar behavior. They remain
historical evidence, not completion gates for revised architecture.

Target:

    type ArtifactRecord*[A] = object
      data*: A
      meta*: ArtifactMeta

    RuntimeContext[A].artifacts*: Table[ArtifactID, ArtifactRecord[A]]

ArtifactRecord is stored only in RuntimeContext.artifacts. Persistent runtime
state stores ArtifactID references. Active handlers resolve an ID, use ordinary
A locally, and register newly created A values before storing or queuing IDs.
Generated Flow[A], generated Artifact payloads, and compile-time pack/unpack
remain record-free.

Revised order: registry and ID state; materialization; output decoding and
publication; finish_work and real transport; composition, failure lifecycle,
and end-to-end hardening.

Current slice: revised Slice 3 — input materialization against resolved records.

## Slice 0 baseline

Branch: `master`

Pre-existing dirty files at baseline:

- `file.txt`
- `src/vecherinka_comptime.nim`
- `src/vecherinka_tests`
- `artifact_transfer_plan/` plan files
- untracked `structured_llm_artifact_transfer_guide.md`

No source files changed during Slice 0. Progress document is only file changed by this task.

Baseline commands, all pass:

```text
nim c -r --panics:on --threads:on -o:/tmp/vecherinka_runtime_execution_test-slice0 src/vecherinka_runtime_execution_test.nim
nim c -r --panics:on --threads:on -o:/tmp/vecherinka_runtime_model_test-slice0 src/vecherinka_runtime_model_test.nim
nim c -r --panics:on --threads:on -o:/tmp/vecherinka_interface_test-slice0 src/vecherinka_interface_test.nim
nim c -r --panics:on --threads:on -o:/tmp/vecherinka_runtime_ipc_test-slice0 src/vecherinka_runtime_ipc_test.nim
```

Result: execution, model lowering, interface, and IPC tests pass. Existing warnings only.

## Slice 0 record

Status: complete.

Files changed: this progress document only; no source or test files.

Issues: pre-existing dirty worktree recorded above.

Next action: revised Slice 1 implementation.

## Revised Slice 1 record

Status: complete.

Files changed: `src/vecherinka_runtime.nim`,
`src/vecherinka_runtime_execution_test.nim`.

Result: `RuntimeContext.artifacts` now owns `ArtifactRecord[A]` values. Initial,
raw, projection, lift, join, and valid model values register there. Activations,
nodes, joins, pending models, ready work, and final output retain `ArtifactID`
references only. Runtime handlers resolve IDs into local `A` values; generated
`Flow[A]` lowering remains record-free. Duplicate IDs, unknown IDs, and table
key/metadata mismatches fail explicitly.

Tests run: execution, model lowering, interface, IPC, materialization, and
typed-lift tests; all compile and pass with finite `gtimeout` limits.

Gate: passed. Next action: revised Slice 3 input materialization.

## Slice 1 record

Status: complete.

Files changed: `src/vecherinka_runtime.nim`, `src/vecherinka_comptime.nim`, `src/vecherinka_runtime_execution_test.nim`.

Tests run: execution, model lowering, interface, IPC, and generated integration tests. All pass.

Result: metadata now follows activations, continuations, joins, pending models, nodes, and runtime events. `execute_flows` creates unique `run-*` roots under program CWD. Runtime allocates each model's fresh `artifact-N` working root before calling `submit`, and passes that directory plus input metadata into the submit boundary. Joins accept distinct roots and allocate fresh output metadata; `Location` values will resolve from the common runtime directory.

Issues: existing compiler warnings only.

Next action: Slice 3 input materialization.

## Scheduler/event unification record

Status: complete.

Files changed: `src/vecherinka_runtime.nim`, runtime execution tests, and the
runtime plan.

Result: removed the ready deque and both scheduler drain layers. Typed
activations now live in `WorkPlan.pending_ready`; `gek_ready` carries only a
numeric ID through the shared channel. `run_work_plan` performs one blocking
`recv_global_event` per iteration. Existing runtime, generated, interface, and
IPC tests pass.

This is scheduler infrastructure, not artifact transfer. It does not advance
input materialization, output decoding, or real Codex transport.

## Plan adjustment: path validation removed

Slice 2 is removed. No runtime path-validation helpers, traversal checks,
symlink checks, or output `Location` verifier are planned. The model receives
strong instructions to use runtime-relative `Location` paths, never emit
absolute or `..` paths, and modify only its assigned working directory.

Multi-root transfer design is complete: `Location` values use paths relative to
the common runtime directory, so copying by location path does not require
merging or selecting artifact metadata roots. Physical copy/materialization
work remains in Slices 3 and 5.

## Previous implementation status

The records below describe work completed before architecture revision. Slices
1, 3, and 8 require rework against ArtifactRecord and ArtifactID contracts.

## Slice 3 record

Status: complete.

Files changed: `src/vecherinka_comptime.nim`, `src/vecherinka_runtime.nim`,
and `src/vecherinka_materialization_test.nim`.

Tests run: focused materialization test plus execution, model lowering,
interface, IPC, and generated integration tests. All pass under finite
`gtimeout` limits.

Result: generated model submits now walk scalar, enum, object, tuple, variant,
sequence, option, and distinct wrapper inputs through a callback-based
compile-time walker. Active variant branches only are visited; sequence paths
are one-based; absent options render explicitly. `Location` payloads resolve
against the common runtime directory, must pass `Path.isRelativeTo`, copy into
the fresh working directory by basename, and receive numeric suffixes on
collision. Empty, missing, outside-root, and destination-contained sources
fail before transport submission.

Issues: existing compiler warnings only.

Next action: Slice 4 output schema and decoder.

## Revised slice status

- [~] Slice 0 — baseline and registry contracts
- [x] Slice 1 — artifact registry and ID-based runtime state
- [~] Slice 3 — input materialization from resolved records
- [~] Slice 4 — output schema and decoder
- [~] Slice 5 — generated submit integration
- [ ] Slice 6 — `finish_work` event protocol
- [~] Slice 7 — real Codex transport
- [~] Slice 8 — composition and ID transfer
- [~] Slice 9 — failure lifecycle and cleanup
- [ ] Slice 10 — end-to-end hardening

`[~]` means prerequisite or partial behavior exists; slice gate not met.

## Working log

### Known facts

- Current generated submit unpacks typed input, materializes it, stringifies
  context, installs debug tool, and sends `LlmCallSpec`.
- Current generated output materializer returns debug/default values.
- Current generated pack/unpack carries typed payload only.
- Current generated lowering computes and echoes output JSON schema, but does
  not yet build the final output decoder/tool protocol.
- Current `LlmCallSpec` carries `input_meta`, `runtime_dir`, `working_dir`,
  and generated `materialized_input`; it does not yet carry a generated output
  decoder.
- Current `debug_tool_registry` has empty input schema and nil callback.
- Current default transport is deterministic; it does not create agent or send prompt.
- Current Codex runtime already supports dynamic tool registration, thread creation, delayed turn eligibility, and tool acknowledgement.
- Current readers already route framed events to main owner.
- Current scheduler routes initial and resumed activations as `gek_ready`
  events, with typed payload retained in `WorkPlan.pending_ready`.
- Current execution tests cover metadata propagation, fresh model/join roots,
  sequential models, dynamic model flows, distinct-root joins, generated
  transport, and reader lifecycle.
- Current runtime has no ArtifactRecord table. Activations, nodes, joins, and
  pending state still store A plus ArtifactMeta or Option[A].
- Generated Flow[A] is compile-time data and must remain independent of runtime
  records.
- Runtime handlers may resolve ArtifactID to A locally; that is not persistent
  artifact storage.
- Historical artifact behavior exists in commit `f2ad7bc`.

### Open issues to watch

- Nim closure `{.gcsafe.}` captures and lifetime across copied dynamic tools.
- Generated macro support for distinct wrappers around `Location`.
- Generated tagged output schema discriminator behavior.
- Materialize runtime-relative `Location` values into each model's working
  directory by path; path policy is prompt-owned, not runtime-validated.
- Distinguishing scheduler model ID from Codex tool request ID.
- Turn completion without `finish_work`.
- Clearing or retaining pending ready activations on terminal shutdown.
- Existing dirty worktree files: preserve unrelated user changes.

### Decision log

- Use context-owned ArtifactRecord values and ArtifactID references. Keep
  generated Flow[A] and active computation on A.
- Reserve model output roots before submission, but publish ArtifactRecord only
  after typed output validation succeeds.
- Keep deterministic transport as explicit test seam.
- Handle output/tool protocol centrally after callback event reaches main owner;
  rely on model instructions for `Location` path discipline.
- Multi-root joins need no root merge or selection: runtime-relative locations
  keep every branch payload addressable.

### Historical Slice 0 contracts (superseded)

```nim
type ArtifactID* = uint64

type ArtifactMeta* = object
  id*: ArtifactID
  artifact_dir*: Path

type ModelMaterialization*[A] = object
  ok*: bool
  value*: Option[A]
  error*: string
```

Fixture plan: scalar field; nested object; `Location`; `seq[Location]`; `Option[Location]`; tagged output variant. Add fixtures with Slice 1 tests; no test-source changes in Slice 0.

### Historical Slice 1 implementation plan (superseded)

1. In `src/vecherinka_runtime.nim`, add `ArtifactID`/`ArtifactMeta`; add the program-CWD `runtime_dir`, `run_dir`, `next_artifact_id`, borrowed `CodexRuntime` owner, and request-keyed pending agent-start records to `RuntimeContext`.
2. In `execute_flows`, capture canonical CWD as the runtime-relative Location base; create unique `run-*` below it; pass run root to `init_codex_runtime`; allocate `artifact-N` below run root. Entry metadata uses CWD, never run root.
3. Add metadata fields to `Activation`, `WorkNode`, `PendingModel`, `JoinState`, `RuntimeEvent`, and copied `GlobalEvent` fields. Update `deliver_resume` and every ready-queue path. `fk_it`, `fk_so`, raw, and lift preserve incoming metadata; joins accept all roots and create fresh output metadata.
4. Change `Flow.fk_model.submit` to receive input metadata plus the pre-created working directory. Allocate fresh output metadata before submit, record input/output metadata on node/pending state, and keep generated typed artifact union unchanged.
5. Update generated submit adapters and fake callbacks for new boundary/event fields only. Keep parsing, Codex mutation, and scheduler ownership on main thread; defer real agent-start behavior to Slice 7.
6. Add focused runtime tests for entry CWD metadata, two fresh model roots, submit working-directory plumbing, `it`, `so`, raw continuation, node input/output metadata, event fields, same-root joins, distinct-root joins, fresh join metadata, and unchanged source root. Run baseline matrix plus Slice 1 tests.

### Per-slice record template

```text
Slice:
Status: not started | active | partial | blocked | complete
Files changed:
Tests run:
Result:
Issues:
Next action:
```
