# Intention: SQLite-backed runs, artifacts, and resumption

Status: implementation integrated; verification and workflow fault checks are
in progress. This file keeps the original impact analysis and records the
implemented design and reversals below.

## Intention

Make a per-run SQLite database the canonical record of artifacts and as much
execution state as is needed to continue an interrupted workflow. Store typed
artifact values in a versioned serialized form, store complete file contents in
SQLite, and persist the work graph and its current execution checkpoint.

Keep the local-filesystem boundary only where Codex needs a working directory.
That directory is temporary staging: materialize Blob inputs from SQLite, let
the model use local paths, then import submitted output bytes back into
SQLite. A run directory may still contain the database and temporary
workspaces, but it is not the artifact store.

Keep `codex_json` unchanged: it already models and serializes `workspace-write`.
The thread sandbox default in `codex_runtime` has been changed from
`danger-full-access` to `workspace-write`, because unrestricted child writes
are incompatible with trusting SQLite as canonical state. Each child receives
its per-call working directory as cwd.
For workflow-level resume, restore the last committed Vecherinka checkpoint;
retry an in-flight model step from its stored input if the same Codex thread
cannot be reattached.

## Implemented model

Generated `solve` wrappers create a SQLite-backed run; generated
`resume_<solve>` wrappers reopen its database and restore the latest checkpoint.
Every artifact is a versioned serialized `string` envelope in SQLite. The
generated codec serializes typed values, including complete Blob and BlobTree
bytes. Runtime memory is a lazy cache. Durable runs do not create artifact
directories; only an LLM call gets a temporary workspace where Blob values are
materialized and submitted files are read back before committing the output.

The database stores workflow metadata, artifacts and ordered predecessor IDs,
model-attempt state, and a versioned scheduler checkpoint. Generated flow keys
and a source manifest identify static code. Checkpoints store stable flow keys,
budget state, ready work, joins, model invocations, counters, outputs, and
dynamic `so` expansion recipes. Resume replays those path-free callbacks from
the saved serialized input and exact budget snapshot, then checks the generated
flow keys before restoring. `so` callbacks therefore have a deterministic,
side-effect-free contract. Model submission remains at-least-once across an
uncertain interruption; a committed result is stored with its checkpoint
before the tool success response is sent.

The old non-durable `execute_flows` entry points have been removed. Use the
generated `solve`/`resume_<solve>` pair or the explicit
`create_sqlite_run`/`resume_sqlite_run` low-level API. `codex_json` remains
unchanged; `codex_runtime` changes only the child sandbox selection to the
already-supported `workspace-write` mode.

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

[`Location`](../api/vecherinka_comptime.nim#L34) originally meant “path
relative to `RuntimeContext.runtime_dir`,” not content. The DSL now rejects it
as an artifact type and directs authors to content values. `Blob` means
“durable file content available from this run's SQLite store,” not a
user-visible filesystem reference. The complete bytes live in the DB. File
paths remain local references only in the temporary model workspace.

The legacy runtime allowed a `Location` to name either a file or a directory.
`BlobTree` preserves directory layouts using normalized relative paths and
complete file bytes, including empty directories. Tree rules cover traversal,
symlinks, file/directory conflicts, and duplicate basenames when materialized
into the model workspace. Executable bits and other filesystem metadata are
not part of the current content contract.

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
- `create_agent` currently requests `workspace-write`
  ([codex_runtime.nim](../api/codex_runtime.nim#L886)); the agent cwd is the
  per-call workspace and the canonical run DB is its parent. The effective
  filesystem boundary still needs integration verification against the actual
  app-server before workspace confinement is treated as proven.
- Active callbacks also contain process-local pointers and generated
  materializer procedures. These must be recreated by Vecherinka, not written
  into SQLite as pointers.

`codex_json.SandboxMode` already includes `sm_workspace_write`
([codex_json.nim](../api/codex_json.nim#L42)), so requesting that mode required
no JSON type change. A fake-server test confirms the request is serialized.
The effective filesystem boundary still needs integration verification against
the app-server in use, especially that a model process cannot write the sibling
run database.

Therefore persist Vecherinka invocation/attempt state, not `CodexRuntime`,
`Process`, reader threads, channels, or tool-binding pointers. Recreate the same
ordinary Codex client and retry an uncommitted model step. Only if the required
behavior is to continue the *same active Codex thread/turn* should we
investigate a narrow reattach/reconcile hook in `codex_runtime`; only change
`codex_json` if the protocol operation needed for that hook is absent. Whether
the external app-server supports such a hook is not established by this source
audit.

## Original impact map (historical)

| Surface | Current contract | Reformulation needed |
| --- | --- | --- |
| Run creation/API | Every call creates a new run directory and DB; no public resume selector. | Separate create from resume. Provide a run ID and a resume entry point that validates workflow/version, loads the checkpoint, and returns the persisted final output when already complete. Keep the existing solve call as the new-run path if source compatibility matters. |
| Workflow lowering | `Flow` is a runtime object graph containing closures/procs, roots, continuations, and branch data. | Emit stable node/implementation keys and a deterministic static manifest. Rebuild executable procs from the current binary; save only IDs/config and dynamic continuation state. Version the manifest and reject incompatible resume. |
| Scheduler and joins | `WorkPlan` queues, invocations, join slots, flags, counters, and active pools are memory-only. | Serialize a versioned checkpoint DTO in SQLite after every logical transition. Persist budgets and dynamic branch choices. Advance checkpoint and artifacts in the same transaction; reconstruct `WorkPlan` on resume. |
| Typed values | `ArtifactRecord[A].data` lives in a table in RAM; compile-time pack/unpack is not serialization. | Generate versioned encode/decode for supported types: inline values, objects, variants, tuples, sequences, options, fixed arrays, distinct wrappers, and Blob references. Persist root input and every generated/model/join value. |
| Files and `Location` | `Location` used to be a runtime-relative path, but the DSL now rejects it as artifact data. Blob and BlobTree values carry full bytes; model inputs are materialized in the call workspace and outputs are read into Blob values. | Persist those complete values in SQLite and remove durable run-relative paths. Keep file paths only in the temporary model workspace. |
| Model and submitter APIs | `LlmCallSpec`, `LlmOutput`, `ModelSubmitter`, prompts, and Codex cwd use `runtime_dir`/`working_dir`. | Keep the required cwd/path for Codex. Make it explicitly temporary staging. Materialize Blob inputs there, import outputs before accepting `finish_work`, and remove launch-root paths from durable contracts. Persist enough model-attempt data to retry. |
| Filesystem isolation | `create_agent` now sends `sm_workspace_write`; `codex_json` already serializes this mode. | Verify the installed app-server confines a child to its call workspace before relying on this boundary. If it does not, place the DB outside an enforced sandbox or use a storage broker. |
| `so` and context | `so` gets input plus optional `Path`s and/or a `BudgetContext`; `working_dir` is the input artifact's directory. There is no `ctx` identifier or artifact access facade. | Keep `so` as a pure typed transformation/routing callback. It receives complete Blob bytes through its input and never gets a filesystem path or storage handle. Keep the read-only `BudgetContext` separate. File staging belongs only at the LLM boundary. Require replay-safe local behavior because an uncommitted callback can run again after interruption. |
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

## Migration decisions

The alternatives were reviewed against the current runtime and Nim type system
before implementation:

1. **SQLite owns artifact bytes.** Filesystem object stores and run-local blob
   caches are rejected as canonical storage because they leave a second source
   of truth. Serialized values and complete file bytes live in the run DB.
   Temporary paths are derived workspaces used only while an LLM call runs.
2. **`Blob` is the durable file value.** Replace path-valued `Location` in
   workflow data with a Blob/content representation. Model tool output still
   uses workspace-relative filenames; the runtime validates and reads those
   files before it commits the typed Blob value. Existing directory-valued
   locations require a corresponding canonical tree representation rather
   than silently changing the contract to files only.
3. **Use a versioned checkpoint snapshot.** Event replay would have to capture
   every scheduler mutation and safely replay callbacks. Fully normalized
   scheduler tables would duplicate the current `WorkPlan` structure. A
   versioned data-only checkpoint row is the smaller recovery representation;
   SQLite transactions publish artifacts and the next checkpoint together.
4. **Persist identities and data, never Nim pointers.** Static flow keys come
   from deterministic lowering order and are included in the workflow
   manifest. Checkpoints store keys and scheduler data, then rebuild static
   code from the running binary. A dynamic `so` expansion stores its parent
   key, input artifact ID, exact budget snapshot, expansion ID, and resulting
   node keys; resume replays the path-free callback and verifies those keys.
   `so` callbacks must be deterministic and side-effect free. Model work is
   never replayed as a graph builder and retains its explicit at-least-once
   retry semantics.
5. **Use generated direct constructors for typed decoding.** `jsonutils` and
   Schematic cannot decode the entire existing artifact shape set: range
   fields inside variants trigger default-initialization failures, and
   Schematic misses nested variants and fixed arrays. Generate the decoder
   from the existing `ArtifactNode` metadata and construct complete Nim
   values without `default(T)`. Keep the tool output schema separate from this
   storage codec.
6. **Keep the Codex protocol stable absent proof.** Workflow
   resume retries an interrupted model step from its committed input; it does
   not promise same-thread Codex reattachment. Source inspection proved that
   `codex_runtime` requested `danger-full-access`. The existing `codex_json`
   enum already supported `workspace-write`, so the minimal necessary runtime
   change selects that mode. Leave the remaining Codex protocol and runtime
   unchanged unless resume requirements prove otherwise.

The primary checkpoint promise is recovery from the last committed scheduler
transition. SQLite cannot make an external model call or arbitrary callback
exactly-once. An interrupted, uncommitted model request may be retried and
incur another call; this must be recorded as at-least-once behavior. A durable
received response is committed before tool success is acknowledged.

### Alternatives considered and not selected

- **Store blobs in an adjacent content-addressed directory:** simpler large
  file I/O and deduplication, but violates the requirement that SQLite fully
  contain artifact data.
- **Keep `Location` and rewrite it to a private blob-cache path:** reduces
  source changes, but makes a path look like the durable value and hides the
  storage boundary from workflow authors. `Blob` makes the value semantics
  explicit.
- **Serialize every runtime Flow node and closure:** would require a second
  recursive IR, typed raw-value codecs, callback factories, and capture
  identities. The current path-free `so` contract lets resume rebuild only
  committed dynamic expansions from their origins with less machinery.
- **Replay the whole workflow from the beginning:** avoids restoring scheduler
  state but repeats committed model calls, breaks budget accounting, and does
  not meet interrupted-process resume.

Reverse callback replay if a workflow needs effectful or nondeterministic
`so` behavior. Such a workflow would need a canonical serialized graph
descriptor or a narrower DSL that makes the decision data explicit. Reverse
the per-run DB choice only if cross-run deduplication or shared artifact
querying becomes a required product feature.

## Progress and decision log

2026-10-05:

- Added `vecherinka_blob.nim` value types for complete file bytes and canonical
  directory trees, with safe import/materialization helpers. Added a
  versioned SQLite store that keeps serialized artifact payloads, complete
  file bytes, ordered predecessor edges, model-attempt state, and checkpoints.
  Store transactions atomically commit artifacts and a checkpoint sequence.
- Chose a versioned checkpoint snapshot over replaying all scheduler events or
  normalizing every scheduler structure into tables. A snapshot mirrors the
  existing `WorkPlan`; it does not duplicate that model in a second schema.
- Reversed the original `Location` preservation idea: a path-valued workflow
  artifact cannot be canonical SQLite data. `Blob`/`BlobTree` values carry the
  bytes, while model output remains a temporary workspace-relative path until
  the runtime imports it.
- Independent review found `BlobTree` validation also needed to reject a file
  used as an ancestor directory. That validation and a regression test were
  added. Store creation and resume were also made distinct operations so a
  resume cannot silently initialize or reset an existing database.
- Focused Blob and store tests pass. The runtime still creates fresh runs,
  stores typed artifacts and scheduler state in memory, and does not call the
  new store. The migration is therefore not yet resumable.
- Changed child threads from `danger-full-access` to the already-supported
  `workspace-write` sandbox. CLI-generated app-server schema confirmed the
  mode; a fake-server test confirms the runtime sends it. `codex_json` needed
  no change. This scopes writes to the per-call cwd; the database will live in
  the parent run directory, outside that cwd.
- Added a standalone versioned checkpoint DTO with stable flow-key slots,
  flattened destinations, ordered scheduler data, canonical JSON encoding,
  and malformed-state validation. Its tests pass, but runtime conversion and
  restore are not implemented yet.
- Compared checkpoint restore with deterministic replay from the root. Replay
  appeared smaller, but independent reviews found that it must also stabilize
  activation identity, completion ordering, budget charging, artifact IDs,
  dynamic `so` choices, and callback side effects. Keep checkpoint restore as
  the default; reconsider replay only for a DSL subset that can enforce pure,
  deterministic callbacks and stable activation IDs.
- The remaining graph question is how checkpointed flows created by `so` are
  rebound to code after restart. The current direction is to identify each
  lowered flow node and store a data-only `so` origin (callback key, input
  artifact, and the budget snapshot used for selection). Resume can recreate
  only that selected callback graph; it must never serialize a Nim closure.
  This can be reversed if a simpler canonical dynamic-flow representation
  proves practical.
- A separate store audit found that workflow execution still relies on RAM,
  artifact folders, and a provenance-only database; `execute_flows` always
  starts fresh, and tool success is acknowledged before the output artifact is
  registered. These are integration blockers, not completed migration work.
- Tightened the `so` migration target: callbacks consume and return typed
  values, including Blob bytes, and do not materialize artifact files. This
  removes dependence on ephemeral artifact directories and makes replay
  behavior clearer. Codex workspaces remain the only Blob materialization
  boundary.
- Replaced duplicated generated `solve`/`resume` graph expressions with one
  generated flow-builder procedure. This reduces generated code and keeps the
  graph construction path identical on create and resume.
- Wired generated wrappers to `create_sqlite_run` and `resume_sqlite_run`;
  removed the non-durable `execute_flows` entry points. The run database holds
  serialized artifacts and checkpoint state; runtime artifact directories
  are created only for model-call staging.
- Selected dynamic `so` origin replay after comparing it with canonical
  topology serialization. The checkpoint now includes expansion IDs, parent
  flow keys, input artifact IDs, exact budget snapshots, and generated node
  keys. Resume rebuilds each expansion in order and rejects key mismatches.
  Checkpoint format version 2 records this state.
- Removed `Path` overloads from `so` and changed `Flow.execute` to receive only
  serialized input plus `BudgetContext`. The only former path-taking example
  now returns a Blob value directly.
- Verified the direct dynamic-`so` restore path, model-result commit-before-ACK
  ordering, pending-model retry, codec round trips, static key generation, and
  generated path-free `so` compilation with focused suites. Ran the four-topic
  parallel research workflow in an isolated disposable worktree using the
  supplied local Codex state, app-bundled Codex CLI 0.160.0, and GPT-6 Luna at
  low effort. The system CLI 0.146 rejected `gpt-6-luna` because its model
  catalog did not include it; selecting the newer existing CLI through `PATH`
  allowed the run. One first attempt ended when a child omitted `finish_work`;
  the retry committed all six model attempts, persisted 13 artifacts, and
  reached a `finished` checkpoint. Its SQLite database contains serialized
  artifact payloads and no per-artifact directories. Official SQLite WAL and
  DuckDB concurrency documentation were spot-checked against the report's
  source claims; the example itself has no web-search tool, so the remaining
  report citations were not independently re-fetched.
- The runtime Luna mapping to `gpt-6-luna` is now verified end to end with the
  app-bundled CLI. No `codex_runtime` or `codex_json` change was needed to select
  the newer executable; `codex_runtime` already resolves `codex` through PATH.
- Simplified the new artifact format to one canonical serialized payload. Blob
  and BlobTree bytes already round-trip inside that payload, so schema 6 no
  longer creates or reads the unused `artifact_file` side table. Opening a
  schema-5 run advances its schema marker while retaining any legacy table and
  rows; those rows were not part of generated workflow storage.

Potential reversal: callback replay relies on the documented purity contract,
which Nim cannot enforce for arbitrary callback bodies. If users need
effectful or nondeterministic `so` callbacks, replace replay recipes with a
canonical dynamic graph descriptor and generated callback factories.

Keep `codex_json` unchanged. The only demonstrated `codex_runtime` change is
selecting its already-supported `workspace-write` child sandbox so model calls
run in their temporary staging directory.
