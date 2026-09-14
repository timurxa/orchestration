# Vecherinka stepping-stone test plan

Purpose: find shortest default prompts that make models handle Vecherinka input,
output, artifacts, and control-flow composition correctly.

This is a test outline, not a proposed DSL. [vecherinka_dsl_guide.md](/Users/alex/areas/productive/orchestration/src/vecherinka_dsl_guide.md) is authority for syntax and support boundaries.

## Rules

- Add stages in order. Do not start advanced tests while an earlier stage fails.
- Run each test once per meaningful revision. No variance campaign. Rerun only
  after fixing prompt, DSL, runtime, or fixture issue.
- Begin each prompt with only task-specific text. Add instruction only when a
  failure proves it necessary. Record final shortest prompt beside each test.
- Every test must inspect all three outputs:
  - direct typed result;
  - structured runtime log, including model calls, flow nodes, failures, and
    artifact paths;
  - generated artifact graph, checking nodes, edges, fan/join shape, lift
    cardinality, and absence of useless files.
- A model may create files only when output type explicitly contains a
  `Location`. Any unrequested file is failure.
- Verify exact values, tuple order, sequence order, option presence, variant
  branch, and location existence. Do not accept plausible prose as proof.
- Stop immediately on a new issue. Classify it before continuing:
  compile-time DSL issue, runtime/lowering issue, prompt issue, model-output
  issue, artifact-materialization issue, or graph/logging issue. Fix and rerun
  only affected tests.

## Shared harness

Create `src/vecherinka_stepping_stone_tests.nim`. Keep fixtures small and
deterministic. Use one generated `solve` entry per scenario, or separate
scenario procedures if that gives clearer logs and artifact graphs.

Each scenario should provide:

1. fixed input values and, where needed, files under the runtime directory;
2. expected typed result;
3. prompt text under test;
4. a log sink and run identifier;
5. artifact-graph capture or a reproducible way to inspect the generated graph;
6. assertions for result, logs, graph, and filesystem.

Keep model profiles cheap. Do not use `void` codomains. Prefer named fields for
human-readable result assertions; use positional tuples only when testing tuple
semantics.

## Stage 0: harness and baseline

Goal: prove test machinery, not model reasoning.

- Compile a minimal entry flow using the documented `profile[Input, Output]`
  form.
- Confirm generated solve signature, one model node, one output artifact, and
  no unrelated files.
- Confirm logs expose run start, model call, finish, and terminal result.
- Inspect generated graph manually and save the inspection procedure.

Gate: direct result, logs, graph, and filesystem all match. If graph capture is
not reliable, stop here.

## Stage 1: one model call, scalar/object output

DSL: one entry model call.

Test model behavior with the smallest useful object:

- input has one or two scalar fields;
- output has one required scalar field;
- prompt states task only, without generic DSL explanation.

Check model fills declared fields, does not invent fields, does not create
files, and returns no explanatory wrapper. Remove prompt words until first
failure, then retain only necessary wording.

Gate: exact typed output; exactly one model call; no useless artifact.

## Stage 2: `pure` and `>>>`

DSL: raw-value seed plus sequential composition.

Scenarios:

- `pure(value) >>> next_flow` proves raw input enters a model flow;
- `first_flow >>> second_flow` proves exact intermediate type matching;
- second model must use only first output and preserve required fields.

Use distinct marker values so accidental use of original input is visible.
Inspect graph for linear order and exactly two model nodes. Test one intentional
type mismatch as a compile-time negative case if harness supports it.

Gate: no implicit conversion or field guessing; intermediate artifact count
matches graph; prompt remains minimal.

## Stage 3: `fan`

DSL: `fan(flow_a, flow_b)` with same domain and ordered tuple output.

- Two branches receive identical input.
- Branches produce visibly different named outputs.
- A follow-up flow consumes the resulting tuple.

Check both branches run once, branch results retain source order, join occurs
once, and follow-up sees tuple rather than a flattened value. Inspect graph for
fork, two branches, join, and no duplicate input artifacts.

Prompt test: each branch gets only its own task; do not tell model about graph
internals unless failure proves that necessary.

Gate: `fan` is nonempty, domains exact, tuple shape exact, graph shape exact.

## Stage 4: `so` callback routing

DSL: `so(Domain, Codomain, input) do: ...`.

- Feed a fixed typed value to a callback.
- One path returns `pure(value)`.
- Another path seeds a next flow with `value >>> next_flow`.

Use a deterministic discriminator. Assert only selected path executes, skipped
path has no model call or artifact, and callback output type is exact.

Inspect graph and logs for callback branch choice, not merely final result.
Keep callback-local logic ordinary Nim; prompt only the model flow.

Gate: no accidental eager execution, no nil-flow surprise, exact path in graph.

## Stage 5: `it` projection

DSL: `it(Domain)` and nested selector groups using documented `[[...]]` syntax.

Scenarios, in order:

- project tuple item `[[0]]` after `fan`;
- select multiple tuple items `[[0, 1]]` and verify retained tuple nesting;
- project a named object field `[[field]]`;
- apply a second group to a nested tuple/object;
- use one tuple range only after scalar selectors pass.

Compose each projection into a model flow with the projected type as domain.
Check no model receives unprojected sibling data through the artifact graph.
Do not use `it(T)[0]`; that is unsupported.

Gate: selected values/types exact; field/index/range errors fail at the right
phase; graph contains projection without an extra model call.

## Stage 6: artifact materialization and `Location`

DSL: ordinary model flows with artifact-bearing input/output.

Start with one `Location` file, then one directory, then nested locations in a
named object and sequence.

- Fixture files live under runtime directory.
- Prompt tells model where requested input artifacts are and what output fields
  mean, but does not prescribe filenames unless output type requires one.
- Output first contains no `Location`; then explicitly contains one requested
  `Location`.

Check input copies resolve from runtime directory, output locations resolve from
model working directory, paths stay relative, and repeated basenames are
renamed as documented. Inspect graph for only declared locations.

Important known boundary: current source uses different roots for input copying
and output verification. Treat cross-call Location handoff as a separate probe,
not an assumption.

Gate: model does not create files for scalar-only output; declared files exist;
missing/outside paths fail clearly; artifact graph has no junk files.

## Stage 7: sequences and `lift(seq[here])`

DSL: inner flow plus `lift(seq[here])[inner_flow]`.

- Use two or three items with unique markers.
- Inner flow transforms one item.
- Assert one inner model call per element, source order preserved, no dropped or
  duplicated items, and output sequence length exact.

Prompt inner model to process one item only. Do not ask it to process the whole
sequence; graph and call inputs must prove that it did not.

Repeat with a sequence containing nested scalar fields, then with nested
`Location` fields. Inspect graph cardinality and per-item artifact paths.

Gate: cardinality, ordering, item isolation, and graph all agree.

## Stage 8: `Option`, tuples, and object lift shapes

DSL: progressively combine structural patterns, one wrapper at a time:

1. `lift(Option[here])[inner_flow]` with present option;
2. same with absent option;
3. `lift((FixedType, here))[inner_flow]`;
4. named tuple pattern;
5. object pattern containing `seq[here]` or `Option[here]`.

Use markers in untouched fields. Assert absent options create zero inner calls,
unchanged fields survive, tuple labels survive, and reconstructed outer shape is
exact. Inspect graph for zero/one/many lift work items.

Use plain `here` only. Do not test `_`, acc-quoted `` `here` ``, or
`Box[here]` as supported placeholders.

Gate: structural reconstruction exact; no work for absent options; no mutation
of non-`here` values.

## Stage 9: variants, fixed arrays, aliases, and named tuples

Use only shapes proven by artifact and Schematic tests.

- Start with variant input, selecting active branch correctly.
- Test simple supported top-level variant output with no unsupported `else` or
  nested structural variant contract.
- Test fixed-array input/output where current schema rules prove support.
- Test aliases, distinct values, constrained values, and named tuple output.

Each case must identify its wire shape and conversion expectation before coding.
Do not infer model-output support from artifact-tree walking alone. In
particular, reject nested structural variants and variant `else` output as
unsupported probes.

Gate: active branch only is traversed; array cardinality exact; aliases and
distinct values round-trip; unsupported shapes fail before model execution.

## Stage 10: composed advanced scenarios

These are final tests. Build them only after every prior gate passes.

### 10A: fan, `it`, `so`, sequential follow-up

Entry model produces a small named/tuple-bearing analysis. `fan` runs two
independent analyses. `it` selects the decision data. `so` routes deterministically
to either `pure` or a follow-up model. Final flow uses `>>>` to assemble the
declared output.

Verify fork/join, projection, routing, and linear follow-up in one graph.

### 10B: lifted sequence of artifact-bearing records

Input contains a sequence of records with scalar fields and `Location` values.
Use `lift(seq[here])` to process each record, preserve untouched metadata, and
return a sequence of results with explicitly declared output locations.

Verify per-record calls, file usage, output path validation, order, and absence
of scratch files.

### 10C: nested structural lift plus optional work

Input combines named tuple/object context, a sequence, and an optional nested
value. Lift only the intended `here` positions. Include a present and absent
fixture in separate runs/scenarios.

Verify exact work cardinality, outer reconstruction, option semantics, and
graph correspondence.

### 10D: full supported orchestration

Use all proven features in one bounded workflow: entry model call, sequential
`>>>`, `fan`, `it`, deterministic `so`, `pure`, lifted sequence, optional
subtree, named tuple/object fields, variant branch, and declared `Location`
artifacts. Keep output schema within proven Schematic limits.

Final prompt must be shortest prompt surviving all prior failures. Final graph
review must show every node is useful and every artifact is consumed, declared,
or returned.

## Prompt-minimization record

For every scenario, record:

- initial task-only prompt;
- observed failure, if any;
- one smallest added instruction;
- result/log/graph evidence that justified it;
- final prompt and why each sentence remains necessary.

Never add broad instructions such as “be careful,” “use the DSL correctly,” or
“do not make useless files” without a concrete observed failure and a test that
proves the addition fixed it.

## Completion criteria

Plan complete when:

- all stages through 10D pass once after final fixes;
- each test has exact direct-output assertions;
- each run has reviewed logs and generated artifact graph;
- no unrequested files appear;
- unsupported shapes are documented as rejected, not silently skipped;
- final prompts are minimal, recorded, and explain only proven model needs.
