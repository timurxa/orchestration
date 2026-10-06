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
  transport = nil, logger = nil, database_path = Path(""))
resume_solve(database_path,
  prompt_templates = default_agent_prompt_templates,
  transport = nil, logger = nil)
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
directory receives `parallel-research.jsonl` and a `run-*` directory containing
the SQLite database. Model-call workspaces are created separately under the
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
It stores versioned serialized artifact values (including complete Blob and
BlobTree bytes), predecessor edges, model-attempt state, and scheduler
checkpoints. A default database is placed at
`run-*/vecherinka.sqlite3`; pass `database_path` to choose a stable path for
later resumption. Keep the SQLite WAL/SHM files with the database while it is
open.

Artifact values are materialized in a temporary model-call workspace only
while an agent is working. The runtime reads submitted file bytes back into
the typed output before committing the artifact and checkpoint. Optional JSONL
logs and `tools/artifact_graph.py` are diagnostic views, not required to resume.
Runtime logs can include serialized `finish_work` arguments, but they are not a
complete or canonical artifact store; SQLite is authoritative. Legacy
path-based provenance APIs and the `vecherinka_provenance_poc_runner` are
separate from the SQLite execution path and do not describe the current storage
contract.

Implementation map: lowering and generated codecs are in
`src/api/vecherinka_comptime.nim`; artifact persistence, model boundaries, and
execution are in `src/api/vecherinka_runtime.nim`; the schema and transactional
store operations are in `src/api/vecherinka_store.nim`; checkpoint format and
restore are in `src/api/vecherinka_checkpoint.nim` and
`src/api/vecherinka_checkpoint_adapter_impl.nim`. Projection and lift grammars
are in `src/api/it_projection.nim` and
`src/api/lift_pattern_typed.nim`.
