# Artifact transfer progress

Last updated: Slice 0 complete; Slice 1 planning.

## Baseline

Branch: `master`

Pre-existing dirty files:

- `file.txt`
- `src/vecherinka_comptime.nim`
- `src/vecherinka_tests`
- untracked `artifact_transfer_plan/`
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

Next action: Slice 1 implementation plan below.

## Current slice

Slice 1 — artifact metadata and run-root allocation.

Status: not started.

## Slice status

- [x] Slice 0 — baseline and contracts
- [ ] Slice 1 — metadata and run-root allocation
- [ ] Slice 2 — safe path helpers
- [ ] Slice 3 — input materialization walker
- [ ] Slice 4 — output schema and decoder
- [ ] Slice 5 — generated submit integration
- [ ] Slice 6 — `finish_work` event protocol
- [ ] Slice 7 — real Codex transport
- [ ] Slice 8 — composition and multi-root transfer
- [ ] Slice 9 — failure lifecycle and cleanup
- [ ] Slice 10 — end-to-end hardening

## Working log

### Known facts

- Current generated submit only unpacks typed input, stringifies context, installs debug tool, and sends `LlmCallSpec`.
- Current generated materializer returns debug/default values.
- Current generated pack/unpack carries typed payload only.
- Current `debug_tool_registry` has empty input schema and nil callback.
- Current default transport is deterministic; it does not create agent or send prompt.
- Current Codex runtime already supports dynamic tool registration, thread creation, delayed turn eligibility, and tool acknowledgement.
- Current readers already route framed events to main owner.
- Historical artifact behavior exists in commit `f2ad7bc`.

### Open issues to watch

- Nim closure `{.gcsafe.}` captures and lifetime across copied dynamic tools.
- Generated macro support for distinct wrappers around `Location`.
- Generated tagged output schema discriminator behavior.
- Safe copying when destination parents or source components are symlinks.
- Distinguishing scheduler model ID from Codex tool request ID.
- Turn completion without `finish_work`.
- Merging branch roots with colliding relative paths.
- Existing dirty worktree files: preserve unrelated user changes.

### Decision log

- Use metadata sidecar, not generated artifact wrapper, to minimize changes to current `Flow[A]` structure.
- Keep deterministic transport as explicit test seam.
- Validate output centrally after callback event reaches main owner.
- Never silently choose one branch root when a join combines distinct roots.

### Slice 0 contracts

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

### Slice 1 implementation plan

1. In `src/vecherinka_runtime.nim`, add `ArtifactID`/`ArtifactMeta`; add `run_dir`, `next_artifact_id`, borrowed `CodexRuntime` owner, and request-keyed pending agent-start records to `RuntimeContext`.
2. In `execute_flows`, capture canonical CWD as immutable source root; create unique `run-*` below it; pass run root to `init_codex_runtime`; allocate `artifact-N` below run root. Entry metadata uses CWD, never run root.
3. Add metadata fields to `Activation`, `WorkNode`, `PendingModel`, `JoinState`, `RuntimeEvent`, and copied `GlobalEvent` fields. Update `deliver_resume` and every ready-queue path. `fk_it`, `fk_so`, raw, and lift preserve incoming metadata; joins preserve same root and explicitly reject distinct roots until Slice 8.
4. Change `Flow.fk_model.submit` to receive input metadata. Allocate fresh output metadata per model request, carry it with completion event, record input/output metadata on node/pending state, and keep generated typed artifact union unchanged.
5. Update generated submit adapters and fake callbacks for new boundary/event fields only. Keep parsing, Codex mutation, and scheduler ownership on main thread; defer real agent-start behavior to Slice 7.
6. Add focused runtime tests for entry CWD metadata, two fresh model roots, `it`, `so`, raw continuation, node input/output metadata, event fields, same-root join behavior, distinct-root rejection, and unchanged source root. Run baseline matrix plus Slice 1 tests.

### Per-slice record template

```text
Slice:
Status: not started | active | blocked | complete
Files changed:
Tests run:
Result:
Issues:
Next action:
```
