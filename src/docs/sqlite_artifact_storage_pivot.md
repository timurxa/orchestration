# Intention: SQLite-backed runs, artifacts, and resumption

Status: design impact audit; implementation remains unchanged.

## Intention

Make a per-run SQLite database the canonical record of artifacts and as much
execution state as is needed to continue an interrupted workflow. Store typed
artifact values in a versioned serialized form, store complete file contents in
SQLite, and persist the work graph and its current execution checkpoint.

Keep the existing filesystem boundary where Codex or a subprocess needs a
working directory. Those directories are temporary staging areas: materialize
inputs from SQLite, let the process use paths, then import submitted outputs
back into SQLite. A run directory may still contain the database and temporary
workspaces, but it is not the artifact store.

Keep `codex_json` unchanged unless exact Codex-thread reattachment proves to
need a protocol operation that its current types do not represent. One narrow
`codex_runtime` change is already indicated: the current agent gets full
filesystem access, which is incompatible with trusting SQLite as canonical
state. Use an effective workspace-only boundary or keep DB access behind a
parent-process broker. For workflow-level resume, restore the last committed
Vecherinka checkpoint; retry an in-flight model step from its stored input if
the same Codex thread cannot be reattached.

## Current design and gap

Today, typed `A` values live only in `RuntimeContext.artifacts`; files live in
`artifact-N` directories; SQLite stores run key/value metadata and artifact
paths/lineage only. The `WorkPlan` also exists only in memory. It contains the
ready queue, joins, continuations, model invocations, budget ledger, result,
and terminal flags. Its `Flow` values contain Nim procedures and closures, so
the current plan cannot be serialized directly.

`execute_flows` always creates a new `run-*` directory and database, registers
input artifact ID 0 against the launch directory, runs the plan, and closes
Codex. Reopening the current provenance DB resets run status/timestamps rather
than resuming. Thus durable artifact bytes alone would not resume the workflow.

Sources: [run lifecycle](../api/vecherinka_runtime.nim#L2229),
[`WorkPlan` state](../api/vecherinka_runtime.nim#L348),
[artifact storage](../api/vecherinka_runtime.nim#L316),
[provenance schema](../api/vecherinka_provenance.nim#L40),
[provenance initialization](../api/vecherinka_provenance.nim#L98).

## Simplest target model

Use SQLite as the authority and keep runtime objects as rebuildable working
state:

1. **Run and workflow definition.** Persist a run ID, workflow ID/version,
   schema/codec version, static node manifest, edges/configuration, initial
   budget and pool weights, run status, and timestamps. Compile-time lowering
   emits stable node keys and implementation keys. At resume, the running
   binary rebuilds the procedures and binds them to those keys; the database
   stores the graph contract, not Nim closure memory. Canonically encode the
   manifest and hash it: IDs cannot depend on pointer values or allocation
   order, semantically ordered edges must retain their order, and maps must
   have deterministic key order. Require explicit stable DSL keys where the
   current syntax cannot derive them reliably; reject duplicates.
2. **Typed artifacts and blobs.** Persist every typed value as versioned
   serialized data. Introduce `Blob` as a content value: its complete file bytes
   are part of SQLite, even if the stored encoding uses a row ID internally and
   runtime code streams bytes instead of loading the whole file into memory.
   Typed workflow values carry that durable Blob value, never a host path. Keep
   artifact provenance edges separate from a typed value's Blob references.
3. **Workspace import/export.** For a model input, fetch each Blob from SQLite
   and create a local file in the model's temporary working directory. Generate
   `vecherinka_model_input_materialization.txt` there as a derived view of the
   stored typed value and materialized Blob paths. The prompt and `finish_work`
   schema still use workspace-relative paths. On model output, validate those
   paths inside the workspace, read/import the bytes, replace the staging path
   with a durable Blob value, and only then commit the typed output. The model
   never sees or invents database IDs.
4. **Execution checkpoint.** Persist a versioned checkpoint DTO after each
   logical scheduler transition. It contains stable node/invocation IDs rather
   than `Flow` pointers, plus pending-ready IDs and their processing order,
   each invocation's input artifact and pool assignment, recursive tagged
   destinations and pool returns, join kind/count/ordered slots, join
   invocations, model-attempt IDs, pool stacks, budget ledger, next counters,
   output ID, and terminal/error state. Canonically encode the checkpoint too:
   sort unordered maps by stable key but preserve scheduling and join order.
   On process start, rebuild `WorkPlan` from the manifest and checkpoint. The
   in-memory plan is a cache/projection, not the authority.
5. **Atomic transition.** In one short SQLite transaction, commit any produced
   artifact and Blob references, predecessor edges, model-attempt result, and
   the next execution checkpoint. Publish/enqueue work only after commit.
   Acknowledge `finish_work` success only after that commit. Large payload bytes
   may be staged as unpublished rows/chunks first; the transaction marks them
   visible by committing the artifact manifest.

A minimal conceptual schema is therefore `run`, `workflow_node`/`workflow_edge`,
`artifact`, `blob` plus an artifact-to-Blob reference table (and a tree manifest
if needed), `artifact_edge`, `execution_checkpoint`, and `model_attempt`. Use a
serialized checkpoint row instead of normalizing every queue/join field: it is
the smaller first design and can be split into queryable tables if real
inspection needs justify it.

### `Blob` and directory payloads

[`Location`](../api/vecherinka_comptime.nim#L34) currently means “path relative
to `RuntimeContext.runtime_dir`,” not content. `Blob` should mean “durable file
content available from this run's SQLite store,” not a user-visible filesystem
reference. It can be represented internally by a stable ID; the complete bytes
live in the DB. File paths remain local references only at the model or
subprocess boundary.

The runtime currently permits a `Location` to name either a file or a
directory. Preserve that behavior explicitly: either define a `BlobTree`
manifest of normalized relative paths to Blob IDs, or define a single packed
directory Blob format. A single-file Blob type alone would silently narrow the
current contract. Tree rules must cover empty directories, path traversal,
symlinks, permissions/executable bits, and duplicate basenames when materialized
into the model workspace.

Import only files/directories referenced by the workflow input, not the entire
launch directory. Snapshot those external inputs into SQLite before scheduling
or fan-out so every branch sees the same bytes. Store content digests and, if
useful, a redacted source descriptor for audit; never use the original absolute
path as artifact identity.

### Persisting the work graph

The graph is persistable if it is represented as data plus code keys, rather
than as the current runtime object graph:

- **Definition graph:** stable node IDs, node kind, declared input/output type
  and codec IDs, model profile/prompt/output-contract configuration, pool
  metadata, static edges, and a stable key for each local `so` implementation.
- **Execution graph:** dynamic invocations and selected continuations, ready
  work, fan/lift join state and ordered result slots, model attempts, and the
  output/terminal state. The versioned checkpoint DTO records this state.
- **Artifact graph:** committed artifact IDs and ordered predecessor edges,
  separate from definition and execution state.

The DSL currently lowers names and expressions into `Flow` objects with proc
fields for `so`, model submit, projection, fanout, and lift
([runtime flow type](../api/vecherinka_runtime.nim#L67),
[compile-time top-level lowering](../api/vecherinka_comptime.nim#L2813)). Those
pointers must be regenerated from the compiled workflow. Store a workflow
version and canonical manifest fingerprint; reject resume if the binary cannot
provide the same node and type/codec manifest. The fingerprint cannot prove
that a local callback's behavior is unchanged, so require an explicit version
bump when `so` or other implementation semantics change. Do not persist
arbitrary Nim source or pretend a changed callback is compatible. Dynamic `so`
choices must persist the selected node/continuation and any value needed to
make the next transition deterministic.

## Model calls and interruption semantics

Persist a `model_attempt` before submitting work, with a stable invocation key,
input artifact ID, output artifact ID/reservation, profile, prompt/input
snapshot or enough versioned data to reproduce it, and status. Move it through
prepared, submitted, output-received, and committed states. Store the returned
output durably before returning success to the tool caller or making downstream
work ready.

There is an unavoidable boundary around an external model process: a crash can
occur after a request was submitted but before its result was committed. The
simplest first resume policy is at-least-once for that unfinished step: mark the
attempt interrupted/indeterminate, then re-submit from the stored input and
prompt. Committed earlier steps are not repeated. Use the invocation key to
quarantine duplicate or late outputs. If exact once-only cost or continuation of
the same model conversation is required, the external request/session must
support durable idempotency or reattachment; SQLite alone cannot provide that.

`so` callbacks also need a replay contract. Current callbacks can use `Path`
values and perform arbitrary filesystem work. To resume safely, make storage
access explicit and route writes through Blob import/commit APIs; otherwise
require callbacks to be deterministic/idempotent and treat uncommitted workspace
outputs as disposable. External side effects cannot be made atomic with SQLite
without a specific outbox/idempotency protocol.

## Codex boundary: keep stable unless exact thread resume is required

The inspected code proves that this repository currently has no exact
Codex-session resume path:

- [`init_codex_runtime`](../api/codex_runtime.nim#L774) always starts a new
  `codex app-server` and initializes it; it does not attach to a prior process.
- [`deinit_codex_runtime`](../api/codex_runtime.nim#L749) kills that process and
  clears agents, requests, turn aliases, and server-request state.
- [`codex_json.RequestKind`](../api/codex_json.nim#L6) and the runtime calls
  cover initialize, thread start, turn start, goal set, and stop; there is no
  resume/read/reconcile operation in this source.
- `create_agent` currently requests `sm_danger_full_access`
  ([codex_runtime.nim](../api/codex_runtime.nim#L886)); the project instructions
  explicitly say the prompt's working-directory limit is not an OS boundary
  ([AGENTS.md](../../AGENTS.md#L30)). A model process with that access must not
  be trusted with a writable SQLite database that contains canonical artifacts
  and checkpoints.
- Active callbacks also contain process-local pointers and generated
  materializer procedures. These must be recreated by Vecherinka, not written
  into SQLite as pointers.

`codex_json.SandboxMode` already includes `sm_workspace_write`
([codex_json.nim](../api/codex_json.nim#L42)), so requesting that mode appears
not to require a JSON type change. Its effective behavior still needs
verification against the app-server in use, specifically that an agent whose
cwd is a per-artifact workspace cannot write the sibling run database. If it
cannot confine the agent to that workspace, use a parent-process storage broker
or another enforced isolation boundary before relying on SQLite as canonical
state.

Therefore persist Vecherinka invocation/attempt state, not `CodexRuntime`,
`Process`, reader threads, channels, or tool-binding pointers. Recreate the same
ordinary Codex client and retry an uncommitted model step. Only if the required
behavior is to continue the *same active Codex thread/turn* should we
investigate a narrow reattach/reconcile hook in `codex_runtime`; only change
`codex_json` if the protocol operation needed for that hook is absent. Whether
the external app-server supports such a hook is not established by this source
audit.

## Impact map

| Surface | Current contract | Reformulation needed |
| --- | --- | --- |
| Run creation/API | Every call creates a new run directory and DB; no public resume selector. | Separate create from resume. Provide a run ID and a resume entry point that validates workflow/version, loads the checkpoint, and returns the persisted final output when already complete. Keep the existing solve call as the new-run path if source compatibility matters. |
| Workflow lowering | `Flow` is a runtime object graph containing closures/procs, roots, continuations, and branch data. | Emit stable node/implementation keys and a deterministic static manifest. Rebuild executable procs from the current binary; save only IDs/config and dynamic continuation state. Version the manifest and reject incompatible resume. |
| Scheduler and joins | `WorkPlan` queues, invocations, join slots, flags, counters, and active pools are memory-only. | Serialize a versioned checkpoint DTO in SQLite after every logical transition. Persist budgets and dynamic branch choices. Advance checkpoint and artifacts in the same transaction; reconstruct `WorkPlan` on resume. |
| Typed values | `ArtifactRecord[A].data` lives in a table in RAM; compile-time pack/unpack is not serialization. | Generate versioned encode/decode for supported types: inline values, objects, variants, tuples, sequences, options, fixed arrays, distinct wrappers, and Blob references. Persist root input and every generated/model/join value. |
| Files and `Location` | `Location` is a runtime-relative path; inputs are copied into consumer folders and model outputs are canonicalized to run-relative paths. Runtime accepts files and directories. | Replace durable `Location` with `Blob` plus a directory-tree form if needed. Store all content; resolve `Blob` to a local temporary path only at process boundaries. Define immutable snapshot and tree semantics. |
| Model and submitter APIs | `LlmCallSpec`, `LlmOutput`, `ModelSubmitter`, prompts, and Codex cwd use `runtime_dir`/`working_dir`. | Keep the required cwd/path for Codex. Make it explicitly temporary staging. Materialize Blob inputs there, import outputs before accepting `finish_work`, and remove launch-root paths from durable contracts. Persist enough model-attempt data to retry. |
| Filesystem isolation | `create_agent` sends `sm_danger_full_access`; the project instructions state that a prompt's working-directory limit is not enforced. | Before the SQLite DB is canonical, enforce a workspace-only boundary for the model process or broker all store access through the parent. The existing `SandboxMode` type already has `sm_workspace_write`; verify actual enforcement. This is the one currently proven Codex runtime concern; it does not require changing JSON schemas by itself. |
| `so` and context | `so` gets input plus optional `Path`s and/or a `BudgetContext`; `working_dir` is the input artifact's directory. There is no `ctx` identifier or artifact access facade. | Keep pure routing `so` simple. For file work, expose a small storage/workspace context with Blob read, import, and export operations; keep the read-only budget snapshot separate. Eliminate implicit writes to a prior artifact directory. Require replay-safe local behavior. |
| Run/Artifact store | `RuntimeContext` combines in-memory artifacts, paths, provenance store, transport, and protocol state. Registration mutates memory before recording lineage. | Make SQLite authoritative; make memory cache disposable. Commit data, Blob/tree rows, lineage, checkpoint, and attempt status together. Keep cleanup exception-safe. Version/open/create DB modes explicitly. |
| Provenance and logging | Provenance rows key artifacts by path; JSONL carries artifact IDs and `artifact_dir`; logging is optional and non-fatal. | Use stable IDs and ordered predecessor IDs in SQLite. Keep JSONL diagnostic/export only. Preserve duplicate predecessor edges. Update or replace path-dependent event consumers. |
| Consumers and tools | Workflows read `Location` with `readFile`; metaoptimizer scans nested run DBs; graph renderer parses JSONL `artifact.commit` with `artifact_dir`. | Use store reads or deliberate workspace exports. Update metaoptimizer/inspector, provenance POC, `tools/artifact_graph.py`, and event tests to use stable IDs/database queries or a versioned graph export. |
| Compatibility and docs | Old run DBs contain path lineage but no typed values, serialized work graph, or checkpoints. Docs describe folders as payload store and DB as provenance only. | Treat old DBs as legacy read-only provenance. They cannot be fully resumed or reconstructed. Rewrite DSL/run docs, `Location`/Blob contract, model prompts, API examples, and migration instructions with the implementation. |

## Migration sequence

1. **Fix the resume contract.** Define whether resume retries an unfinished model node or must continue the same Codex thread. The default here is to retry uncommitted work and preserve all committed progress. Define workflow versioning and incompatibility behavior.
2. **Add durable codecs and Blob storage.** Encode/decode all allowed `A` variants and store file/tree bytes in SQLite. Keep workspaces as import/export adapters. Snapshot referenced launch inputs before scheduling.
3. **Persist the graph and checkpoint.** Generate stable workflow node manifests; serialize dynamic scheduler state using stable node/artifact IDs. Make each node transition, artifact commit, and checkpoint update atomic.
4. **Add recoverable model-attempt handling.** Record attempts before send; commit model output before acknowledging success; on restart reconcile known results or retry indeterminate attempts under the stated policy.
5. **Add create/resume lifecycle and migrate consumers.** Reopen the same run DB without resetting it, validate code/schema versions, rebuild the plan, and update all readers/tools/prompts.
6. **Prove recovery with fault injection.** Interrupt after input snapshot, local node execution, model submission, output receipt, artifact commit, checkpoint update, and before tool acknowledgement. Verify no committed state is lost and duplicate events cannot double-advance the graph.
7. **Only then consider Codex reattachment.** If workflow-level retry does not meet the required meaning of “resume,” establish the app-server's resume/reconcile capability and make the smallest necessary Codex runtime/protocol change.

## Decisions and limits

- Initial design uses one SQLite database per run. A global/shared database is not needed to meet run resumption.
- Old runs cannot be fully upgraded: their typed values and execution graph were never persisted. Keep a provenance reader or best-effort file importer, but do not promise exact recovery.
- A database checkpoint does not make arbitrary filesystem/network side effects transactional. Local callbacks must be replay-safe or use staged effects with idempotent commit.
- File sizes and fan-out patterns are unknown. Benchmark BLOB and tree import/read latency, memory, WAL growth, and backup size before selecting a chunk threshold. For large streaming imports, stage invisible rows first and publish them with a short transaction.
- The Codex child still needs a filesystem cwd. Existing sandbox settings do not enforce the prompt's directory boundary; the temporary workspace remains a separate execution concern.
- `run-*` may remain as a container for the DB and temporary workspace. It must stop serving as the canonical identity or content path for artifacts.

## Audit limits

This is a static source audit and migration design. No code or tests were changed or run. Exact Codex thread reattachment, workflow version fingerprinting, Blob codec details, tree semantics, and retry cost guarantees need explicit decisions and focused prototypes before implementation.
