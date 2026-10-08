# Workflow readiness and validation

This current audit checks whether an LLM can author and run a simple Vecherinka
research workflow. The [DSL guide](vecherinka_dsl_guide.md), [budget
contract](vecherinka_budgeting_spec.md), and repo [run
instructions](../../AGENTS.md) describe the required budget, example, state
setup, and runtime limits. `src/main.nim` is absent; compile the standalone
example named in the run instructions.

The four-topic research example previously completed on 2026-10-05 using GPT-6
Luna at low effort and the app-bundled Codex CLI 0.160.0. That run committed
six model attempts and 13 artifacts, and its checkpoint reached `finished`.
The example exercises its combined dynamic `so`/`lift` workflow, but that exact
example is not an automated end-to-end regression test. Focused codec, store,
runtime, checkpoint, and compile-time suites passed. The former path-based
provenance POC was retired when inspection moved into the run database.

A direct SQLite recheck later that day launched two fresh runs; both failed
because a child turn ended without calling `finish_work`. Their schema-6
databases persisted the failure: checkpoint sequences 17 and 16 were marked
`failed`, with 9 and 8 artifacts respectively. Each DB also retained the
committed and failed model-attempt states; one or more parallel attempts were
still `submitted`. These terminal failed runs cannot be resumed.

The default developer instructions, goal, turn prompt, and tool description
were then strengthened to say that ordinary assistant text is not a submission
and to correct/retry rejected tool arguments. Three fresh GPT-6 Luna runs with
the revised prompts all finished. Direct inspection of all three SQLite DBs
confirmed schema 6, checkpoint sequence 21/status `finished`, 13 artifacts, 16
predecessor edges with no missing parent IDs, and six `sasCommitted` attempts.
This small sample is encouraging, not a reliability guarantee. It confirms the
workflow can complete and that each successful state is present in SQLite.

An additional real-model reliability ladder on 2026-10-05 covered four shapes
with GPT-6 Luna at low effort: nested object output with enum, `Option`, and an
ordered sequence; two distinct fan branches followed by an ordered join; a
two-call root-`Blob` handoff; and a combined fan/join that creates a `BlobTree`
with nested files and an empty directory for a later model to read. All four
finished with exact-value assertions. Direct SQLite inspection confirmed
committed attempts and predecessor edges. The root-`Blob` case also compared
the consumer's text byte-for-byte against the stored Blob payload; the combined
case confirmed both stored file contents and the empty directory survived.

The ladder identified a likely model-tool contract defect: root `string` and
`Blob` outputs were emitted as primitive JSON Schemas, and two real root-`Blob`
turns ended without `finish_work`. The output contract now wraps non-object
roots under `args`, producing object-shaped tool arguments and restoring the
declared value in the materializer. After this change and an explicit prompt
instruction for the `args` path, the root-`Blob` live run passed. The live
experiment changed schema shape and wording together, so it does not isolate
which change resolved the omissions. Schema and materializer regressions cover
root `string`, `Blob`, `BlobTree`, sequence, tuple, option, and variant values.

The first wrapped-Blob trial also used an assertion that expected a space after
the canary prefix, although its prompt had not required one. The prompt was
tightened to specify the exact prefix, including that space; the subsequent
live Blob run matched it. These cases are evidence from one run per successful
shape, not a broad reliability guarantee.

## Remaining implementation limits

- **Filesystem access:** the runs recorded in this audit used the earlier
  `workspace-write` setting. The current runtime uses
  `approval_policy=never` and `sandbox=danger-full-access`, with a temporary
  per-call workspace as cwd; workers can access any files allowed to the OS
  user. See [codex_runtime.nim](../api/codex_runtime.nim) and the current
  [DSL guide](vecherinka_dsl_guide.md).
- **Research retrieval:** the research example requests current sources, but
  the workflow registers only its `finish_work` dynamic tool
  ([vecherinka_comptime.nim](../api/vecherinka_comptime.nim#L1774)). Search
  access depends on child app-server configuration and is not guaranteed.
- **Liveness:** the event loop has no deadline or cancellation
  ([vecherinka_runtime.nim](../api/vecherinka_runtime.nim#L2213)); a stalled
  request can wait indefinitely.
- **Cost:** budgeting uses fixed admission estimates, not actual provider
  usage or retry spend.
- **Recovery:** tests cover checkpoint restore and pending-model retry, but do
  not kill a live process at every transition boundary. Recovery is from the
  last committed scheduler checkpoint; an indeterminate model call can run
  again.
- **Completion tool:** the goal and prompts ask the agent to call
  `finish_work`, and the runtime detects an omitted call, but it fails that run
  instead of automatically prompting the same agent again. Stronger prompts
  and the non-object root wrapper address observed causes, but other omissions
  can still terminate a run.

The research workflow itself has no search/retrieval tool. The run's SQLite WAL
and DuckDB concurrency claims were spot-checked against their documentation;
remaining report URLs were not independently re-fetched. Run examples in an
isolated disposable checkout and verify sources before relying on the report.
