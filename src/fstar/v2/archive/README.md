# F* v2 archive

This directory keeps superseded material available for context. It is not an
active design or implementation plan. Start with the
[top-down system specification](../theory/system_spec.md) and
[current state](../state/README.md).

## Contents

- [`current_implementation/`](current_implementation/README.md): the complete
  pre-redesign F* source tree and its Makefile. Its types, schema checker, and
  admitted proof boundaries explain the current implementation history; the
  top-down specification is the active design.
- [`2026-10-14/`](2026-10-14/README.md): the previous package-owned design
  draft and its implementation DAG. It records codec boundaries, typed graph
  proposals, journal invariants, source theorem gaps, and open design
  decisions.
- [`schema_era_2026-10-14/`](schema_era_2026-10-14/state/work_dag.md): full
  pre-pivot specifications, theorem guides, work DAG, state summary, and
  research registry. Old research links that cited those documents can be
  followed here.
- [`research/`](research/registry.md): source audits, adversarial reviews,
  package-contract studies, and former schema work. These reports can explain
  existing declarations and historical choices; their recommendations and
  task statuses are not automatically current.
- [`history/`](history/node_summaries.md): milestone summaries and the run
  log, retained as a chronology rather than an active plan.
- [`retired_guides/`](retired_guides/implementation_packet.md): short former
  redirect notes from the prior documentation checkpoint. Full earlier
  versions of those guides are in `schema_era_2026-10-14/`.

The archive is intentionally useful as evidence. When an archived claim
conflicts with the active specification or current source, follow the active
specification and verify the source.
