# Vecherinka DSL guide

Vecherinka is a typed Nim DSL that lowers workflow declarations into a
`solve` procedure. Read this with the [budgeting contract](vecherinka_budgeting_spec.md)
and [run instructions](../../AGENTS.md). Source is authoritative; composite
surface workflows are not all covered by end-to-end tests.

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

const model = "gpt-5.6-luna".medium

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
  transport = nil, logger = nil)
```

`initial_budget` is required. The defaults apply to all arguments after it.
`solve` raises `ValueError` if execution fails or returns no output.

## Composition and data

`first >>> second` composes `A ~> B` with `B ~> C`; `value >>> flow` seeds a
flow with a raw `A`. Use `pure(value)` for a zero-cost local value. There are no
implicit conversions, field matching, tuple flattening, or automatic
projection.

- `fan(flow1, flow2, ...)` runs same-domain branches on the same input and
  returns a tuple in source order. Use `fan`, not internal `fanout`.
- `so(A, B, input) do: ...` runs local routing and returns
  `FlowSpec[void, B]`; return `pure(value)` for a direct result. Path forms
  expose `runtime_dir` and `working_dir`; budget forms expose a snapshot.
- `it(Tuple)[[0, 1]]` projects selected tuple items;
  `it(Object)[[field]]` projects fields. Use nested selector groups for nested
  projections. Index and field selectors cannot mix in one group; a range
  must be the only selector and stay in bounds.
- `lift(here)[flow]`, `lift(seq[here])[flow]`, and
  `lift(Option[here])[flow]` apply a flow while preserving the outer shape.
  Supported wrapper forms are deliberately restricted; do not assume
  `lift(Box[here])` works. `here` is a placeholder; `_` is not.

These composite surface forms have implementation support, but a combined
`fan`/`so`/`it`/`lift` workflow is not yet covered end-to-end. The research
example demonstrates `so` plus `lift`; treat it as illustrative until that
exact path is exercised.

## Profiles, prompts, and output contracts

Use `"model".none`, `.low`, `.medium`, `.high`, `.xhigh`, or `.max` to choose
reasoning effort (`minimal` aliases `none`). Supported profiles and budget
estimates are in the budgeting contract.

`AgentPromptTemplates` customizes developer instructions, goal, turn prompt,
and finish description. `checked_prompt(text, "name", ...)` validates literal
templates. Supported substitutions are `$task`, `$input`, `$working_dir`,
`$runtime_dir`, `$model`, and `$effort`; `$$` escapes `$`. The finish
description is passed through without substitution.

Model output is parsed against the declared output type via `finish_work`.
Prefer named object fields. Supported round-trip shapes include scalars,
enums, plain objects, named tuples, sequences, options, locations, supported
variants, distinct values, and constrained integers. Some variant/array cases
and positional-tuple round trips are not established; Schematic support alone
does not prove Vecherinka support.

## Files and `Location`

`Location("relative/path")` is a runtime-relative artifact path. Typed input
is also written to `vecherinka_model_input_materialization.txt` in the call's
artifact directory; read it for exact values. Prompt text and JSON schema are
control data, not workflow input or output.

Input locations resolve under `runtime_dir` and are copied into the consumer
artifact directory. Output locations must name an existing file or directory
inside the producer's `working_dir`; Vecherinka validates and canonicalizes
them relative to `runtime_dir` for downstream use. Empty, missing, or outside
paths fail. Repeated basenames get `-1`, `-2`, etc. Input and output roots are
different; a raw output filename is not itself a cross-call path.

Use `string` for inline content and `Location` for file transfer. For example,
an output field `patch_text: string` must contain patch text; a
`report_file: Location` must name a file created in the current working
directory. Do not put file contents in a `Location` or return a filename in a
string field when file transfer is intended. Artifact leaves reject refs,
pointers, procedures, sets, `JsonNode`, `Table`, `char`, and `cstring`.

## Running the research example

From the repo root, after following the state setup in [AGENTS.md](../../AGENTS.md):

```bash
CODEX_HOME="$PWD/.codex-task-state" \
CODEX_SQLITE_HOME="$PWD/.codex-task-state" \
nim c -r --panics:on --threads:on --path:src/api \
  src/examples/vecherinka_parallel_research.nim
```

It prints a recommendation, rationale, sources, and caveats. The current
directory receives `parallel-research.jsonl` and a `run-*` directory
containing the provenance database and artifact directories. Run from an
isolated disposable checkout: the child agent currently has full filesystem
access despite prompt instructions restricting writes to its working
directory. Source lookup is not configured by this workflow; current-source
research requires search-capable tools in the child app-server environment.

The public solve API has no timeout or cancellation. A stalled request can
wait indefinitely. Invalid `finish_work` data is rejected and returned to the
agent as a tool error, so it may correct the result in the same turn. If the
turn ends without a valid `finish_work`, the plan fails.

## Provenance and inspection

Every run stores `vecherinka_provenance.sqlite3` and `artifact-*` directories
under `run-*`. SQLite stores artifact paths and predecessor edges, not
payloads, hashes, model responses, or full operation history; JSONL logs are
diagnostic. Keep SQLite WAL/SHM files with the database while it is open.
Run status ends `finished`, `failed`, or `aborted`. Do not reopen a prior DB as
a continuation run; initialization resets its metadata.

For the provenance smoke test (separate from the research example):

```bash
CODEX_HOME="$PWD/.codex-task-state" \
CODEX_SQLITE_HOME="$PWD/.codex-task-state" \
nim c -r --panics:on --threads:on --path:src/api \
  src/tests/vecherinka_provenance_poc_runner.nim
```

The test checks a fixed two-artifact graph, not general workflow correctness.
Implementation map: lowering in `src/api/vecherinka_comptime.nim`, runtime in
`src/api/vecherinka_runtime.nim`, projection/lift grammars in
`src/api/it_projection.nim` and `src/api/lift_pattern_typed.nim`, and
provenance in `src/api/vecherinka_provenance.nim`.
