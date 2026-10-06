# Vecherinka DSL guide

Vecherinka is a typed Nim DSL that lowers workflow declarations into a
`solve` procedure. Read this with the [budgeting contract](vecherinka_budgeting_spec.md)
and [run instructions](../../AGENTS.md). Source is authoritative; composite
surface workflows are not all covered by end-to-end tests.

Generated `solve` procedures use SQLite as the durable artifact store and
checkpoint each scheduler transition. The generated `resume_<solve>` procedure
restores an interrupted run from the same database. Blob values are
materialized only in a temporary model workspace.

## Smallest workflow

```nim
{.experimental: "callOperator".}
import std/[macros, paths]
import vecherinka # compile with --path:src/api

type
  Input = object
    request: string
  Output = object
    response: string

const model = "gpt-6-luna".low

expandMacros: vecherinka(solve):
  > answer Input ~> Output {.entry.}:
    model[Input, Output]("Answer the request. Put the answer in response.")

let result = solve(Input(request: "Say hello"), 100.0)
```

`expandMacros:` is Nim syntax. A flow has the form `> name A ~> B {.entry.}:`;
exactly one non-`void` entry is required. Model endpoints must match exactly.
The generated signature is:

```nim
solve(input, initial_budget,
  prompt_templates = default_agent_prompt_templates,
  transport = nil, database_path = Path(""))
resume_solve(database_path,
  prompt_templates = default_agent_prompt_templates,
  transport = nil)
```

`initial_budget` is required. The defaults apply to all arguments after it.
An empty `database_path` creates `run-*/vecherinka.sqlite3` under the current
directory. Pass a path to retain and resume a specific run. `solve` raises
`ValueError` if execution fails or returns no output; `resume_solve` raises if
the database is missing, incompatible, or already terminal.
Generated wrappers encode typed artifacts as serialized strings for the
low-level SQLite runtime. Direct `create_sqlite_run` and `resume_sqlite_run`
calls currently accept only those serialized-string artifacts.

## Composition and data

`first >>> second` composes `A ~> B` with `B ~> C`; `value >>> flow` seeds a
flow with a raw `A`. Use `pure(value)` for a zero-cost local value. There are no
implicit conversions, field matching, tuple flattening, or automatic
projection.

- `fan(flow1, flow2, ...)` runs same-domain branches on the same input and
  returns a tuple in source order. Use `fan`, not internal `fanout`.
- `so(A, B, input) do: ...` runs local routing and returns
  `FlowSpec[void, B]`; return `pure(value)` for a direct result. The callback
  receives typed input (including full Blob bytes), and `so_budget` also
  receives a `BudgetContext` snapshot. These callbacks must be deterministic
  and side-effect free: resume may replay them to rebuild a dynamic graph.
  They cannot access artifact or workspace paths. Only model-call workspaces
  materialize Blobs.
- `it(Tuple)[[0, 1]]` projects selected tuple items;
  `it(Object)[[field]]` projects fields. Use nested selector groups for nested
  projections. Index and field selectors cannot mix in one group; a range
  must be the only selector and stay in bounds.
- `lift(here)[flow]`, `lift(seq[here])[flow]`, and
  `lift(Option[here])[flow]` apply a flow while preserving the outer shape.
  Supported wrapper forms are deliberately restricted; do not assume
  `lift(Box[here])` works. `here` is a placeholder; `_` is not.

These composite surface forms have implementation support. Checkpoint restore
rebuilds dynamic `so` graphs from their saved input and budget snapshot before
resolving saved flow keys.

## Profiles, prompts, and output contracts

Use `"model".none`, `.low`, `.medium`, `.high`, `.xhigh`, or `.max` to choose
reasoning effort (`minimal` aliases `none`). Supported profiles and budget
estimates are in the budgeting contract.

`AgentPromptTemplates` customizes developer instructions, goal, turn prompt,
and finish description. `checked_prompt(text, "name", ...)` validates literal
templates. Supported substitutions are `$task`, `$input`, `$working_dir`,
`$runtime_dir`, `$model`, and `$effort`; `$$` escapes `$`. The directory
variables describe temporary model-call staging only. The finish description
is passed through without substitution.

Model output is parsed against the declared output type via `finish_work`.
Prefer named object fields. Supported round-trip shapes include scalars,
enums, plain objects, named tuples, sequences, options, Blobs, BlobTrees, supported
variants, distinct values, and constrained integers. Some variant/array cases
and positional-tuple round trips are not established; Schematic support alone
does not prove Vecherinka support.

When the output schema is not object-shaped, `finish_work` receives the value
under an `args` property so its tool arguments remain an object. For example, a
root `string` uses `{"args":"..."}`, and a root `Blob` uses
`{"args":"relative-file.txt"}`; object-shaped outputs keep their named fields
directly. The runtime decodes this wrapper back to the declared Nim type before
storing the artifact.

## Files and `Blob`

`Blob` carries a suggested filename and the complete file bytes. `BlobTree`
carries canonical relative paths, complete file bytes, and empty directories.
These are workflow values; a filesystem path is never their stored identity.
Typed input is also written to `vecherinka_model_input_materialization.txt`
in the call's workspace; read it for exact values. Prompt text and JSON schema
are control data, not workflow input or output.

Before a model call, Vecherinka materializes input Blobs and BlobTrees into its
temporary workspace. For output, the model returns a workspace-relative file
path for a `Blob` or directory path for a `BlobTree`. Vecherinka rejects
absolute paths, traversal, symbolic links, missing paths, and file/directory
type mismatches, then reads the submitted bytes into the value. A returned
path is only a local reference for that call; downstream nodes receive the
Blob bytes. Repeated input basenames get `-1`, `-2`, etc.

Use `string` for small inline content and `Blob` for file transfer. For
example, an output field `patch_text: string` contains patch text; a
`report_file: Blob` names a file created in the current workspace. Use
`BlobTree` when preserving a directory layout or empty directories matters.
Do not return file contents in a path field. Artifact leaves reject refs,
pointers, procedures, sets, `JsonNode`, `Table`, `char`, and `cstring`.

## Running the research example

From the repo root, after following the state setup in [AGENTS.md](../../AGENTS.md):

```bash
PATH="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS:$PATH" \
CODEX_HOME="$PWD/.codex-task-state" \
CODEX_SQLITE_HOME="$PWD/.codex-task-state" \
nim c -r --panics:on --threads:on --path:src/api \
  src/examples/vecherinka_parallel_research.nim
```

It prints a recommendation, rationale, sources, and caveats. The current
directory receives a `run-*` directory containing the SQLite database.
Model-call workspaces are created separately under the
system temporary directory, used only for staging, and removed when the
runtime call exits. Run from an isolated disposable checkout. Child threads use
Codex's `workspace-write` sandbox with their per-call workspace as cwd. Source
lookup is not configured by this workflow; current-source research requires
search-capable tools in the child app-server environment.

The public solve API has no timeout or cancellation. A stalled request can
wait indefinitely. Invalid `finish_work` data is rejected and returned to the
agent as a tool error, so it may correct the result in the same turn. If the
turn ends without a valid `finish_work`, the plan fails.

## Durable storage and inspection

The per-run `vecherinka.sqlite3` database is the canonical record of the run.
Schema version 7 stores versioned serialized artifact values (including
complete Blob and BlobTree bytes), ordered predecessor edges, the static and
activated workflow graph, model attempts, Codex worker sessions, exact
app-server JSON messages, execution generations, and scheduler checkpoints.
A default database is placed at
`run-*/vecherinka.sqlite3`; pass `database_path` to choose a stable path for
later resumption. Keep the SQLite WAL/SHM files with the database while it is
open.

Artifact values are materialized in a temporary model-call workspace only
while an agent is working. The runtime reads submitted file bytes back into
the typed output before committing the artifact and checkpoint. There is no
separate Vecherinka JSONL logging path. `tools/artifact_graph.py <database>`
renders workflow nodes, artifact lineage, model input/output links, and worker
sessions from SQLite. Conversation JSON remains available in
`conversation_event` and can be joined to `worker_session`, `model_attempt`,
and `workflow_node` by their stable IDs. The `VecherinkaReader.poll` API
provides a query-only connection for live checkpoint and event polling; direct
SQL readers can inspect the rest of the schema.

`conversation_event.raw_json` contains the exact app-server JSON message body
on one line, excluding the newline used as transport framing. Incoming records
are persisted before parsing. Outgoing records are persisted before write and
then marked `write_returned` or `write_raised`; these labels describe the local
pipe write only, not remote receipt. Codex does not expose hidden reasoning.
The database may contain prompts, model inputs, tool arguments, and outputs;
protect it with the same care as the workflow's source data.
`outcome_unknown` means the prior process stopped before recording the local
write result. A second resume is rejected while the current owner's heartbeat
is newer than 30 seconds; stale ownership may be taken over after that window.
The old owner is fenced from subsequent SQLite transitions. A reader can
compare `heartbeat_at_ns` with its own clock, but must treat staleness as
advisory because a paused process can also miss heartbeats.
Runs created before schema 7 retain their artifact/checkpoint history, but the
new schema does not invent graph activations, worker sessions, or conversation
messages that were never recorded. Static graph rows become available when a
compatible workflow is resumed. `run_metadata.history_started_at_ns` marks
when inspectability history begins for this database.

Implementation map: lowering and generated codecs are in
`src/api/vecherinka_comptime.nim`; artifact persistence, model boundaries, and
execution are in `src/api/vecherinka_runtime.nim`; the schema and transactional
store operations are in `src/api/vecherinka_store.nim`; checkpoint format and
restore are in `src/api/vecherinka_checkpoint.nim` and
`src/api/vecherinka_checkpoint_adapter_impl.nim`. Projection and lift grammars
are in `src/api/it_projection.nim` and
`src/api/lift_pattern_typed.nim`.

### Reading graph and conversation history

The main tables are:

- `workflow_node` and `workflow_edge`: stable flow keys and typed topology
  edges. `expansion_id = 0` is the static graph; nonzero values identify
  activated `so` graphs.
- `workflow_expansion`: the parent flow, input artifact, selected root, and
  canonical topology signature for each `so` activation.
- `artifact` and `predecessor`: complete serialized values and ordered data
  lineage.
- `model_attempt`: one logical model request, including its workflow node,
  input artifact, reserved and committed output artifact, model profile, and
  current status.
- `run_execution`, `worker_session`, and `conversation_event`: process runs,
  Codex sessions and their generations, and append-only protocol/state events.

For example, this query maps model nodes to attempts, worker sessions, and
messages:

```sql
SELECT n.flow_key, a.request_id, s.session_id, s.generation, s.thread_id,
       e.event_id, e.direction, e.kind, e.write_state, e.raw_json
FROM workflow_node AS n
JOIN model_attempt AS a ON a.flow_key = n.flow_key
LEFT JOIN worker_session AS s ON s.request_id = a.request_id
LEFT JOIN conversation_event AS e
  ON e.session_id = s.session_id OR e.request_id = a.request_id
ORDER BY a.request_id, s.generation, e.event_id;
```

Artifact lineage is available directly from `predecessor`:

```sql
SELECT p.artifact_id, p.position, p.predecessor_id,
       a.operation, a.flow_kind, a.request_id
FROM predecessor AS p
JOIN artifact AS a ON a.artifact_id = p.artifact_id
ORDER BY p.artifact_id, p.position;
```

A live Nim observer can open a second connection and page conversation events
without taking ownership of the workflow database:

```nim
let reader = open_vecherinka_reader(database_path)
defer: reader.close()
var cursor = 0'i64
while true:
  let page = reader.poll(cursor)
  # Refresh UI from page.snapshot; append page.events.
  cursor = page.last_event_id
```

Poll again on the application's normal refresh interval. The reader enables
SQLite `query_only`, uses a bounded busy timeout, and holds a read transaction
only while capturing one consistent snapshot and event page. Checkpoint payloads
are versioned JSON snapshots; decoded table values remain the durable source
for artifacts, graph edges, sessions, and messages.
