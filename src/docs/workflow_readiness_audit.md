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
runtime, checkpoint, compile-time, and provenance suites passed.

A direct SQLite recheck later that day launched two fresh runs; both failed
because a child turn ended without calling `finish_work`. Their schema-6
databases persisted the failure: checkpoint sequences 17 and 16 were marked
`failed`, with 9 and 8 artifacts respectively. Each DB also retained the
committed and failed model-attempt states; one or more parallel attempts were
still `submitted`. These terminal failed runs cannot be resumed. This confirms
durable partial progress and failure recording, but exposes live-agent
completion reliability as an unresolved limitation.

## Remaining implementation limits

- **Filesystem boundary:** agents use `approval_policy=never` and
  `sandbox=workspace-write` ([codex_runtime.nim](../api/codex_runtime.nim#L886))
  with a temporary per-call workspace as cwd. The successful workflow run did
  not test attempts to write outside that workspace; treat isolation as an
  execution boundary that still needs dedicated verification.
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
  instead of automatically prompting the same agent again. The two direct
  recheck runs both hit this path.

The research workflow itself has no search/retrieval tool. The run's SQLite WAL
and DuckDB concurrency claims were spot-checked against their documentation;
remaining report URLs were not independently re-fetched. Run examples in an
isolated disposable checkout and verify sources before relying on the report.
