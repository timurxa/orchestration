# Historical research index — F* v2

Everything under this directory records earlier design and source audits. It
is evidence of how the former schema-centered plan was selected and where its
proof gaps were found; none of its recommendations is an active requirement.

## Current authorities

- [Design and theorem statements](../../theory/system_spec.md)
- [Work and status](../../state/work_dag.md)

## Historical evidence groups

- V2-01 through V2-03: earlier identity, graph, codec, resolver, and generator
  design explorations.
- S2 execution: the abstract-system theorem spine, journal authorization,
  controller interleavings, durability, and concrete-refinement analyses.
- A00 through A05: source inventories, proof-gap audits, and work on the
  former schema implementation. In particular,
  [A05 research](A05-2026-10-14/approach_registry.md) documents the route now
  retired by the active redesign draft.
- Multimodule build notes and earlier overview/review folders: historical
  verifier and architecture evidence.

Historical conclusions may conflict with the current specification or code.
Use them to recover prior reasoning, not to determine current behavior,
theorem scope, or task status. The chronology is in
[node_summaries.md](../history/node_summaries.md) and
[run_log.md](../history/run_log.md).
