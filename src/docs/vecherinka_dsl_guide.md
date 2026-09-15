# Vecherinka DSL: concise guide

This guide describes the DSL implemented in this repository. Source and
passing tests are authoritative. Each feature is labelled:

- **Proven**: active end-to-end or focused tests cover it.
- **Implementation-backed**: lowering/runtime support exists, but no complete
  active surface test covers the full feature.
- **Inference**: behavior follows generated code but is not pinned by a test.

## 1. Smallest useful flow

```nim
{.experimental: "callOperator".}
import std/[macros, paths]
import vecherinka  # compile with --path:src/api

type
  Input = object
    request: string
  Output = object
    response: string

const model = "gpt-5.6-luna".medium

expandMacros: vecherinka(solve):
  > answer Input ~> Output {.entry.}:
    model[Input, Output]("Answer the request. Put answer in response.")

let result = solve(Input(request: "Say hello"))
```

`expandMacros:` is Nim's macro-expansion directive, not Vecherinka syntax.
The flow header is:

```nim
> flow_name Domain ~> Codomain {.entry.}:
  flow_expression
```

Rules:

- Importing `vecherinka` supplies compile-time and runtime layers.
- Exactly one `.entry.` flow is required; marker follows the codomain.
- Entry domain must be non-`void`.
- `A ~> B` means `FlowSpec[A, B]`; every codomain must be non-`void`.
- Model syntax is `profile[A, B]("prompt")`; endpoints match exactly.
- Generated solve is effectively `solve(input, transport = nil, logger = nil)`.

Evidence: `src/api/vecherinka.nim`, `src/api/vecherinka_comptime.nim`,
`src/examples/vecherinka_manual_test.nim`.

## 2. Composition

```nim
first >>> second       # A ~> B, B ~> C gives A ~> C
value >>> next_flow    # seed next_flow with raw A
pure(value)            # void ~> typeof(value), no model request
```

Composition is typed. No implicit conversion, mapping, tuple flattening,
field matching, bind, or automatic projection exists.

### Parallel branches: `fan`

```nim
fan(
  model[A, B]("Extract B"),
  model[A, C]("Extract C")) # A ~> (B, C)
```

Branches need the same domain. Runtime runs them with the same input and
returns outputs in source order. `fanout` is an internal lowering form; use
`fan`, not `fanout`.

Status: **Implementation-backed**. Lowering and runtime fork/join exist; a
complete active surface flow is not currently tested.

### Local logic: `so`

```nim
so(Domain, Codomain, input) do:
  if should_use_fast_path(input):
    pure(local_value)
  else:
    input_for_next_step >>> next_flow
```

Context form also exposes the current artifact directory:

```nim
so(Domain, Codomain, input, working_dir) do:
  writeFile($(working_dir / Path("result.txt")), "done")
  pure(Output(file: Location("result.txt")))
```

Callback input type must exactly equal `Domain`; callback result must be
`FlowSpec[void, Codomain]`. Use a simple identifier for callback input.
`so` does not allocate an output artifact; seed it with `pure(...)` when
needed.

Status: **Implementation-backed**.

## 3. Selecting and lifting data

### `it` projection

```nim
it(Tuple)[[0]]             # one tuple item
it(Object)[[field]]        # one field
it(Tuple)[[0, 1]]          # tuple of items
it(Nested)[[0], [field]]   # apply next group to each selected item
it(Tuple)[[0 .. 2]]        # tuple range
```

Use nested selector groups. `it(T)[0]` is invalid. Numeric and field
selectors cannot mix within one group. Ranges must be the only selector in a
group, with nondecreasing, in-bounds values checked during typed elaboration.

Status: **Implementation-backed**. Parser and typed projection behavior are
tested; a complete generated surface flow is not active-tested.

### `lift`

```nim
lift(here)[flow]                    # X ~> Y
lift(seq[here])[flow]               # seq[X] ~> seq[Y]
lift(Option[here])[flow]            # Option[X] ~> Option[Y]
lift((FixedType, here))[flow]
lift((left: here, right: FixedType))[flow]
```

`here` is the only placeholder. Plain `_` and acc-quoted ``here`` are
not placeholders. Runtime invokes inner flow once per `here`, per sequence
element, and per present option; it restores the original outer shape.

Status: **Implementation-backed**. Do not assume `lift(Box[here])` works;
wrapper patterns use the restricted grammar above.

## 4. Profiles, prompts, and contracts

Profile constructors:

```nim
"model".none       "model".low       "model".medium
"model".high       "model".xhigh     "model".max
```

`minimal` aliases `none`. Effort is sent during thread creation and the
turn.

Custom templates use `AgentPromptTemplates` and `checked_prompt`:

```nim
const templates = AgentPromptTemplates(
  developer_instructions: checked_prompt("Developer rules"),
  goal: checked_prompt("Task: $task", "task"),
  turn_prompt: checked_prompt("$task\n$input\nDir: $working_dir",
                              "task", "input", "working_dir"))

vecherinka(solve, templates):
  ...
```

Allowed placeholders: `$task`, `$input`, `$working_dir`,
`$runtime_dir`, `$model`, `$effort`. `$$` escapes a dollar. Unknown
placeholders, malformed names, nonliteral template text, and missing required
placeholders fail at compile time. `finish_work_description` is passed
through without runtime placeholder formatting.

Model output is a generated structured contract. Use named object fields for
readability. Proven output shapes include scalars, enums, plain objects,
named tuples, sequences, options, locations, supported variants, distinct
values, and constrained integers. Artifact walking supports more shapes than
model-output round-tripping.

Known output limits: variant `else` branches, nested structural variants,
some fixed-array-in-variant shapes, and positional-tuple round trips are not
proven. Do not infer Vecherinka support from Schematic support alone.

## 5. Artifacts and `Location`

```nim
type Report = object
  summary: string
  output_file: Location

Location("relative/path.txt")
```

`Location` names a relative runtime artifact path, not an arbitrary host
path or file handle.

- Input locations resolve under `runtime_dir` and are copied into the model
  call's artifact directory.
- Output locations resolve under that model call's `working_dir`.
- Output paths must be nonempty, existing, and inside `working_dir`.
- Repeated basenames receive `-1`, `-2`, ... suffixes.
- Missing, outside-root, empty, or source-containing paths fail verification.

Important: `runtime_dir` and per-call `working_dir` are different roots.
Cross-call `Location` handoff is not proven; do not assume one model's output
location automatically resolves as the next model's input location.

Rejected artifact leaves include refs, pointers, proc values, sets, `JsonNode`,
`Table`, `char`, and `cstring`. Prefer `seq`, objects, or `Location`
where appropriate.

## 6. Effective-use recipe

1. Start with one entry model flow and named input/output objects.
2. Keep every intermediate endpoint explicit and exactly matching.
3. Use `pure` for deterministic local values; `so` for deterministic routing.
4. Use `fan` only for independent same-input work.
5. Use `it` to reduce data before another flow.
6. Use `lift` for per-item work while preserving outer structure.
7. Add `Location` only when file/directory transfer is needed.
8. Test each construct alone before combining constructs.
9. Inspect typed result, payload directories, JSONL events, and SQLite graph.

Runtime needs a working Codex app-server unless a custom `LlmTransport`
produces expected completion events. Invalid model tool output, schema
failure, missing output, unexpected tool names, and runtime failures terminate
the plan.

## 7. Provenance DB: what exists after a run

Each run creates:

```text
run-*/
  vecherinka_provenance.sqlite3
  artifact-*/       # payload directories/files
```

Live SQLite may also have `vecherinka_provenance.sqlite3-wal` and `-shm`;
keep them with the database while a writer is open.

SQLite is canonical provenance storage. Structured JSONL remains diagnostic.
The database stores graph identity and relationships, not payload contents.

Tables:

- `run`: schema version, run directory, status, timestamps, last commit seq.
- `artifact`: path, monotonic `commit_seq`, commit timestamp.
- `edge`: direct predecessor edges and ordered `position`.

Paths inside `run_dir` are stored relative and resolved by the reader. Inputs
outside `run_dir` remain absolute. Children are derived from predecessor
edges. Duplicate predecessors remain distinct because edge position is
preserved. Artifact plus edges become visible atomically at commit. The runtime
coordinator is the SQLite writer; readers use separate connections.

Reader API:

```nim
let reader = openProvenance(Path(database_path))
try:
  let info = reader.runInfo()
  for item in reader.artifacts():
    echo item.path, " <- ", item.predecessors
  echo reader.roots()
  echo reader.leaves()
  echo reader.artifactsAfter(last_commit_seq)
finally:
  reader.close()
```

`artifactsAfter(n)` returns artifacts with `commit_seq > n`, ordered by
commit sequence. `runInfo().status` ends as `finished`, `failed`, or
`aborted`.

Do not claim provenance captures payload hashes, model responses, semantic
operation metadata, or complete execution history. Operation/flow/request
fields belong to diagnostic `artifact.commit` JSONL, not this SQLite schema.

## 8. Runner POC and direct inspection

Run source, not a possibly stale binary:

```bash
cd /Users/alex/areas/productive/orchestration
CODEX_HOME="/Users/alex/areas/productive/orchestration/.codex-task-state" \
CODEX_SQLITE_HOME="/Users/alex/areas/productive/orchestration/.codex-task-state" \
nim c -r --panics:on --threads:on --path:src/api \
  src/tests/vecherinka_provenance_poc_runner.nim
```

The runner creates a temporary child workspace, compiles and runs
`vecherinka_provenance_poc_test.nim`, finds exactly one child
`run-*/vecherinka_provenance.sqlite3`, reads it through the DSL, and validates
one root plus one leaf. Required app-server auth/state and outbound network
must work.

Expected important output:

```text
child-response: provenance-poc-ok
status: finished
last-commit-seq: 2
artifact-count: 2
root-count: 1
leaf-count: 1
valid: true
```

The POC validates metadata and edges, not payload contents. Its exact
two-artifact assumptions make it a smoke test, not a general graph inspector.
Capture the printed `provenance-database` path; the parent inspection run
creates a different run/database. Full output also includes `run-dir`,
`leaf-path`, and `leaf-predecessors`.

For direct inspection, replace `RUN_DIR` with that captured run directory:

```bash
ls -la RUN_DIR
sqlite3 RUN_DIR/vecherinka_provenance.sqlite3 '.tables'
sqlite3 RUN_DIR/vecherinka_provenance.sqlite3 \
  'SELECT key,value FROM run ORDER BY key;'
sqlite3 -header -column RUN_DIR/vecherinka_provenance.sqlite3 \
  'SELECT * FROM artifact ORDER BY commit_seq;
   SELECT * FROM edge ORDER BY child_path,position;'
```

Use `src/tests/vecherinka_provenance_tests.nim` for linear, duplicate-edge,
root, leaf, delta-polling, and external-input examples. Use
`src/tests/artifact_provenance_logging_tests.nim` for `artifact.commit` JSONL
reconstruction. Commit order reflects registration order, not necessarily
artifact ID or visual completion order.

Do not reopen an existing database as a continuation run: store initialization
resets run metadata, and commit sequencing is process-local. Moving a complete
run directory is supported by relative internal paths; moving only the DB is
not.

## 9. Evidence and source map

- DSL lowering and type rules: `src/api/vecherinka_comptime.nim`.
- Runtime scheduling, artifacts, model calls: `src/api/vecherinka_runtime.nim`.
- Projection grammar: `src/api/it_projection.nim` and its tests.
- Lift grammar: `src/api/lift_pattern_typed.nim` and its tests.
- Provenance store/reader: `src/api/vecherinka_provenance.nim`.
- SQLite design and planned coverage: `vecherinka_provenance_sqlite_plan.md`.
- Current POC: `src/tests/vecherinka_provenance_poc_runner.nim` and
  `src/tests/vecherinka_provenance_poc_test.nim`.

The active suite proves the basic model flow, artifact materialization,
structured output boundaries, projection/lift parsers, and provenance reader
pieces. It does not yet prove a complete surface `fan`/`so`/`it`/`lift`
graph, all SQLite plan cases, or cross-call location handoff.
