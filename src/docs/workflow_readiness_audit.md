# Workflow readiness status

Static review of whether an LLM can author and run a simple Vecherinka
research workflow. The [DSL guide](vecherinka_dsl_guide.md),
[budget contract](vecherinka_budgeting_spec.md), and repo [run instructions](../../AGENTS.md)
now agree on the required budget argument, runnable example, launch directory,
state setup, and runtime limits. `src/main.nim` is absent; compile the
standalone example named in the run instructions.

## Remaining implementation limits

- **Filesystem safety:** agents use `approval_policy=never` and
  `sandbox=danger-full-access` ([codex_runtime.nim](../api/codex_runtime.nim#L886)).
  Working-directory restrictions are prompt text, not enforced isolation.
- **Research retrieval:** the research example requests current sources, but
  the workflow registers only its `finish_work` dynamic tool
  ([vecherinka_comptime.nim](../api/vecherinka_comptime.nim#L1774)). Search
  access depends on child app-server configuration and is not guaranteed.
- **Liveness:** the event loop has no deadline or cancellation
  ([vecherinka_runtime.nim](../api/vecherinka_runtime.nim#L2213)); a stalled
  request can wait indefinitely.
- **Coverage:** the research example's combined `so`/`lift` graph is not
  covered by an end-to-end test; the guide documents the coverage boundary.
- **Cost:** budgeting uses fixed admission estimates, not actual provider
  usage or retry spend.

Use an isolated disposable checkout for execution and verify source URLs.
This audit was not validated by compiling or running the workflow.
