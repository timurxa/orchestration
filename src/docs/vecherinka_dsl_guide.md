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
  transport = nil, database_path = Path(""),
  finish_work_retry_limit = 4)
resume_solve(database_path,
  prompt_templates = default_agent_prompt_templates,
  transport = nil, finish_work_retry_limit = 4)
```

`initial_budget` is required. The defaults apply to all arguments after it.
`finish_work_retry_limit` controls follow-up turns after a completed turn omits
`finish_work`; it defaults to four retries. Set it to zero to fail immediately.
Negative values are rejected.
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

Each handoff must have the same Nim type at both ends. Transparent aliases are
the same type and are accepted. Named and positional tuples are different
types, even when their fields have the same values; convert them explicitly in
`so` when a boundary needs a different tuple type. `fan` applies the same rule
to branch inputs and outputs. The compiler checks these boundaries before
artifact values are serialized. SQLite artifact envelopes also retain type
keys, so stale or malformed stored values still fail during decoding.

- `fan(flow1, flow2, ...)` runs same-domain branches on the same input and
  returns a tuple in source order. Use `fan`, not internal `fanout`.
- `it(Type)` by itself is the zero-cost identity flow `Type ~> Type`. Use it
  to pass an input through unchanged, including as a `fan` branch; do not
  write an identity `so` that returns `pure(input)`.
- `it(Tuple)[0, 1]` projects selected tuple items;
  `it(Object)[field]` projects fields. These selectors change the output
  type to the selected value or tuple. Use nested selector groups for nested
  projections. Index and field selectors cannot mix in one group; a range
  must be the only selector and stay in bounds. Chain groups to follow a path,
  such as `it((Input, Plan))[1][topics]`.
- `so(A, B, input) do: ...` runs local routing and returns
  `FlowSpec[void, B]`; return `pure(value)` for a direct result. The callback
  receives typed input (including full Blob bytes), and `so_budget` also
  receives a `BudgetContext` snapshot. These callbacks must be deterministic
  and side-effect free: resume may replay them to rebuild a dynamic graph.
  They cannot access artifact or workspace paths. Only model-call workspaces
  materialize Blobs.
- `lift(here)[flow]`, `lift(seq[here])[flow]`, and
  `lift(Option[here])[flow]` apply a flow while preserving the outer shape.
  Supported wrapper forms are deliberately restricted; do not assume
  `lift(Box[here])` works. `here` is a placeholder; `_` is not.

If `summarize` has type `Request ~> Summary`, this preserves the request and
returns it beside the summary:

```nim
fan(it(Request), summarize)
```

Use `so` when local code must compute or update a value, construct a required
object or named tuple, or choose a flow from typed data. Do not use `so` just
to forward tuple items or select object fields. Use `it(Type)` for identity
and `it` projections for those cases; use `fan` when several projections from
the same input must be collected into a positional tuple. A `so` conversion
may still be needed when the destination specifically requires a different
named or positional tuple type. Use `pure(value)` inside `so` for a real
deterministic computation that cannot be expressed as a projection. When a
projection is used once, inline it at the composition site instead of defining
a pass-through flow just to name it.

For example, to change `(CodebaseInput, SystemInventory)` into
`(CodebaseInput, seq[SystemUnit])`, project both outputs directly:

```nim
fan(
  it((CodebaseInput, SystemInventory))[0],
  it((CodebaseInput, SystemInventory))[1][units])
```

To flatten selected values from a nested tuple, use one projection branch per
output rather than a `so` callback that indexes and rebuilds the tuple:

```nim
fan(
  it(((A, B), C))[0][0],
  it(((A, B), C))[0][1],
  it(((A, B), C))[1])
```

Keep `so` when the operation changes data or selects the next flow. For
example, checking a completeness flag and returning either an early report or
the rest of a workflow is routing; copying fields out of the input is not.

These composite surface forms have implementation support. Checkpoint restore
rebuilds dynamic `so` graphs from their saved input and budget snapshot before
resolving saved flow keys.

## Design workflows as algorithms

Express a workflow as a typed transformation from input to output. Keep the
intermediate artifact types and fields to the information later steps need;
avoid parallel copies of the same draft, inventories, or prose when one typed
value can carry the required state. A workflow is an algorithm over data, not
a roster of agent roles.

### Keep workflow behavior independent of the launch environment

Do not let workflow meaning or file selection silently depend on the process's
current directory, a source directory's basename, a temporary workspace name,
or incidental host state. Make source, output, and database locations explicit
inputs. Resolve or require absolute paths once at the CLI boundary; do not
reinterpret relative paths later in a flow.

Treat `BlobTree` entry paths as relative to the tree root. Its
`suggestedFilename` is only a materialization name and must never become a
component of a source file's identity. Tell model steps the path convention
explicitly and, where practical, provide the exact file manifest as typed
input. Model workspace paths are temporary staging paths and must not escape
into durable workflow state.

Run deterministic preflight checks before model calls: validate path
normalization, uniqueness, required-file coverage, and unsupported filesystem
entries. If compatibility requires accepting a prefixed path, remove only a
known exact prefix and then recheck uniqueness and complete coverage; reject
ambiguous or missing paths before dispatching dependent work. Do not ask later
LLM steps to repair an implicit path convention.

Check this boundary by invoking the workflow from different working
directories with the same absolute inputs. The normalized source manifest and
selected per-system files should be identical. A changed launch directory must
not change the selected codebase, report destination, or durable database.

Use `fan` when independent functions consume the same input and their results
are needed together. Use `lift(seq[here])[flow]` to apply one operation to
independent sequence items. Use `it(...)` to pass an input unchanged or project
only the fields later steps need.
Parallel branches reduce elapsed time when work is independent, but each model
branch adds a model call; do not add branches solely to increase the agent
count.

Use typed model outputs for decisions that control later work. An enum, option,
boolean, or small record makes the decision explicit. Use `so` to inspect that
typed value and choose a flow, for example to skip work, retry a bounded repair,
or leave an unresolved case for the final result. Prefer fixed composition
when every run follows the same path. Keep `so` callbacks deterministic and
side-effect free so resume can rebuild the same graph from saved inputs.

For example, have a review flow return a typed `needs_repair: bool` and
`findings: seq[Finding]`. A following `so` can send the review and findings to
the repair flow when `needs_repair` is true, or return the accepted result with
`pure` otherwise. This makes the review data determine the graph directly;
there is no separate dispatcher agent interpreting prose. Keep only the fields
needed by later steps, and use an enum or separate typed collections when
different finding classes take different routes.

Choose the smallest composition that expresses the algorithm: `>>>` for fixed
steps, `fan` for independent same-input work, `lift` for repeated work over a
supported wrapper, and `so` for data-dependent routing. Do not use a model call
to make a decision that a deterministic `so` condition can make from typed
fields.

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
temporary workspace. A worker may read and write anywhere available to its OS
user. For output, it may return an absolute path or a path relative to the
call workspace; relative paths may use parent traversal. Vecherinka rejects
missing paths, symbolic links, and file/directory type mismatches, then reads
the submitted bytes into the value. A returned path is only a local reference
for that call; downstream nodes receive the Blob bytes. Repeated input
basenames get `-1`, `-2`, etc.

Use `string` for small inline content and `Blob` for file transfer. For
example, an output field `patch_text: string` contains patch text; a
`report_file: Blob` names an accessible file. Use
`BlobTree` when preserving a directory layout or empty directories matters.
Do not return file contents in a path field. Artifact leaves reject refs,
pointers, procedures, sets, `JsonNode`, `Table`, `char`, and `cstring`.

## Running the formalizer

For the bounded parallel proposal-to-Typst workflow, see the
[formalizer workflow guide](vecherinka_formalizer_guide.md).

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
runtime call exits. Child threads use Codex's `danger-full-access` sandbox
with their per-call workspace as cwd; filesystem access is limited by the OS
user's permissions, not by that cwd. Source
lookup is not configured by this workflow; current-source research requires
search-capable tools in the child app-server environment.

The public solve API has no timeout or cancellation. A stalled request can
wait indefinitely. Invalid `finish_work` data is rejected and returned to the
agent as a tool error, so it may correct the result in the same turn. If the
turn ends without a valid `finish_work`, the runtime sends up to
`finish_work_retry_limit` follow-up turns on the same agent thread asking it to
submit the completed result. If all retries end without a valid submission,
the plan fails.

## Running the TUI demo

[`vecherinka_tui_demo.nim`](../examples/vecherinka_tui_demo.nim) is a small
local planning workflow for watching the TUI: it creates a draft, sends that
draft to parallel safety and logistics reviews, then synthesizes one plan. It
makes four `gpt-6-luna` low-effort model calls and needs no web search.

Run it from a disposable worktree because generated agents can write in their
working directory. From the repository root, create the worktree once and copy
the example into it:

```bash
git worktree add --detach ~/areas/temp/vecherinka-tui-demo HEAD
cp src/examples/vecherinka_tui_demo.nim \
  ~/areas/temp/vecherinka-tui-demo/src/examples/
```

In Terminal 1, compile and start a run with a unique database path:

```bash
cd ~/areas/temp/vecherinka-tui-demo
export PATH="/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS:$PATH"
export CODEX_HOME="/Users/alex/areas/productive/orchestration/.codex-task-state"
export CODEX_SQLITE_HOME="$CODEX_HOME"
DB_PATH="$PWD/run-demo-$(date +%Y%m%d-%H%M%S)-$$.sqlite3"
nim c -r --panics:on --threads:on --path:src/api \
  --out:/tmp/vecherinka_tui_demo \
  src/examples/vecherinka_tui_demo.nim "$DB_PATH"
```

Copy the printed `SQLite database:` path. In Terminal 2, wait for that file to
appear and open it in the viewer built at the main repository:

```bash
DB_PATH="paste-the-printed-database-path-here"
while [ ! -f "$DB_PATH" ]; do sleep 0.2; done
sleep 1
/Users/alex/areas/productive/orchestration/tools/vecherinka-tui "$DB_PATH"
```

The left pane shows the actual work occurrences, including the draft,
independent review calls, and synthesis. Follow stored incoming/outgoing edges;
press `c` on a model occurrence to open the conversation for its exact request.
Keep the database path and its SQLite sidecars together until the run ends.

## Durable storage and inspection

The per-run `vecherinka.sqlite3` database is the canonical record of the run.
Schema version 8 stores versioned serialized artifact values (including
complete Blob and BlobTree bytes), ordered predecessor edges, runtime work
occurrences and causal edges, model attempts, Codex worker sessions, exact
app-server JSON messages, execution generations, and scheduler checkpoints.
A default database is placed at
`run-*/vecherinka.sqlite3`; pass `database_path` to choose a stable path for
later resumption. Keep the SQLite WAL/SHM files with the database while it is
open.

Artifact values are materialized in a temporary model-call workspace only
while an agent is working. The runtime reads submitted file bytes back into
the typed output before committing the artifact and checkpoint. There is no
separate Vecherinka JSONL logging path. `tools/vecherinka-tui <database>` reads
the occurrence DAG, artifacts, attempts, and worker conversations from SQLite.
The TUI does not display reusable flow-definition topology. Conversation JSON
remains available in `conversation_event` and can be joined to `worker_session`,
`model_attempt`, and the exact `work_occurrence.request_id`. The `VecherinkaReader.poll` API
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
Schema-7 runs retain their artifact/checkpoint history, but cannot recover the
missing history of pure work and repeated reference instances. The TUI marks
their occurrence DAG unavailable; it never infers occurrences from static
workflow definitions. `run_metadata.history_started_at_ns` marks when
inspectability history begins for this database.

Implementation map: lowering and generated codecs are in
`src/api/vecherinka_comptime.nim`; artifact persistence, model boundaries, and
execution are in `src/api/vecherinka_runtime.nim`; the schema and transactional
store operations are in `src/api/vecherinka_store.nim`; checkpoint format and
restore are in `src/api/vecherinka_checkpoint.nim` and
`src/api/vecherinka_checkpoint_adapter_impl.nim`. Projection and lift grammars
are in `src/api/it_projection.nim` and
`src/api/lift_pattern_typed.nim`.

### Reading work and conversation history

The main tables are:

- `work_occurrence`: one scheduled/executed instance of model, reference, raw,
  iterator, SO, fanout, lift, or join work. `work_id` identifies the instance;
  `flow_key` describes the code location without merging repeated instances.
- `work_edge`: causal occurrence edges with relation and branch/join position.
  Every edge points from a lower ID to a higher ID, which proves the graph is
  acyclic.
- `artifact` and `predecessor`: complete serialized values and ordered data
  lineage.
- `model_attempt`: one logical model request, including its flow key,
  input artifact, reserved and committed output artifact, model profile, and
  current status.
- `run_execution`, `worker_session`, and `conversation_event`: process runs,
  Codex sessions and their generations, and append-only protocol/state events.

For example, this query maps model occurrences to attempts, worker sessions, and
messages:

```sql
SELECT w.work_id, w.kind, w.state, w.flow_key, a.request_id,
       s.session_id, s.generation, s.thread_id,
       e.event_id, e.direction, e.kind AS event_kind, e.write_state, e.raw_json
FROM work_occurrence AS w
JOIN model_attempt AS a ON a.request_id = w.request_id
LEFT JOIN worker_session AS s ON s.request_id = a.request_id
LEFT JOIN conversation_event AS e
  ON e.session_id = s.session_id OR e.request_id = a.request_id
WHERE w.kind = 'model'
ORDER BY w.work_id, s.generation, e.event_id;
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
