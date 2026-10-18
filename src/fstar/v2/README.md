# F* workflow v2 documents

Use this index to find the current design, work status, and retained history.

## Start here

1. Read the current [event-driven state-machine API WIP](theory/state_machine_api_wip.typ).
   It is the working design discussion, not an implementation specification.
2. Check [current state](state/README.md) and the
   [theorem work DAG](state/work_dag.md) for progress and next steps.
3. Consult the [previous system specification](theory/system_spec.md) and
   [archive](archive/README.md) for earlier theorem proposals, design
   arguments, source audits, and research.

## Layout

- [`theory/`](theory/state_machine_api_wip.typ) contains the current working
  API WIP and previous theorem proposals.
- [`state/`](state/README.md) contains active status and theorem work tracking.
- [`archive/`](archive/README.md) contains superseded plans, guides, and
  research notes. Archived work is evidence and context, not current direction.
- [`archive/current_implementation/`](archive/current_implementation/README.md)
  preserves the pre-redesign F* source and its verification Makefile. It is
  useful for studying the existing implementation, but is not the active
  implementation of the top-down specification.
