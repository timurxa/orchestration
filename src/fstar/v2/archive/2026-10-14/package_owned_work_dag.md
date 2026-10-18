# F* v2 redesign work DAG

**Status: archived design draft.** The former A00–C6/A05 schema-typing plan is retired as an execution plan. This file is retained for its complete dependency and acceptance history; it is not the active work plan.

## Authority

- [package-owned implementation draft](package_owned_implementation_spec.md) was the design authority at the time. Its detailed obligations and D1-D7 register are preserved as history.
- At that checkpoint, this file was the sole active execution/status plan. It recorded tasks, dependencies, acceptance, and status.
- [node_summaries.md](../history/node_summaries.md) and [run_log.md](../history/run_log.md) preserve evidence and chronology from the retired schema plan. Treat their A00-A36/A05 statuses as historical, not current.
- Files under [research](../research/registry.md) are historical design evidence. Their earlier selection of a universal schema resolver is superseded by later design work.

## Current checkpoint

The earlier plan paused during A05c schema work. That checkpoint is preserved in Git history, but A05a-A07 and the dependent schema-resolution stages are no longer active tasks. The new plan is not ready for theorem implementation until the open decisions below are discussed and the package boundaries are fixed.

No implementation node below is complete. The existing checked fragments are evidence for possible reuse only. The nearest source shapes and admitted/absent obligations are linked from the P0-P16 table in the spec.

## New proof spine

~~~mermaid
flowchart TD
  R0["R0 close package and graph decisions"] --> R1["R1 exact package identities P0"]
  R0 --> R2["R2 typed graph constructors P1"]
  R1 --> R2
  R1 --> R3["R3 package-owned graph codec P2"]
  R2 --> R3
  R3 --> R4["R4 journal codec and proof-directed replay P3"]
  R1 --> R5["R5 node and operation provenance P6/P7"]
  R2 --> R6["R6 generator commit and global splice P4"]
  R4 --> R6
  R5 --> R7["R7 global budget ledger P8"]
  R6 --> R7
  R4 --> R8["R8 authorized prefix and crash recovery P10"]
  R3 --> R8
  R8 --> R8b["R8b exact generated graph recovery P5"]
  R3 --> R8b
  R6 --> R8b
  R5 --> R9["R9 controller interleavings P15"]
  R6 --> R9
  R7 --> R9
  R8 --> R9
  R8b --> R9
  R9 --> R10["R10 enabled frontier P11"]
  R4 --> R10b["R10b progress rank P12"]
  R5 --> R10b
  R6 --> R10b
  R7 --> R10b
  R8 --> R11["R11 recovered semantics P16"]
  R9 --> R11
  R8b --> R11
  R12["R12 concrete refinement P13"]
  R8 --> R12
  R9 --> R12
  R10 --> R12
  R10b --> R12
  R10 --> R13["R13 conditional liveness P14"]
  R10b --> R13
  R12 --> R13
  R11 --> R14["R14 integrated trust audit and proof-bearing examples"]
  R13 --> R14
~~~

## Tasks

| ID | Depends on | Acceptance | Status |
|---|---|---|---|
| R0 | — | Resolve D1-D7 in the spec or explicitly defer each with a rule that keeps theorem statements sound. Confirm whether all finite typed topologies are a product requirement. Do not begin schema replacement code while the typed graph decoder and trust boundary are unsettled. | in_progress (discussion draft) |
| R1 | R0 | Define an exact package table and canonical durable identities. Prove each reference selects the same codec, callback, and law-bearing package on reload. Remove schema-denotation rows and parallel declarations. This is P0 in the spec. | not_started |
| R2 | R0, R1 | Define the public typed graph value and builder. Prove exact descriptor projection, unique node keys, prior-port scope, and dependent input/output typing for every port environment. Keep builder completeness only to the topology set explicitly chosen in D3. This is P1. | not_started |
| R3 | R1, R2 | Define graph-package encode/decode over durable graph bytes. On success return a typed graph for the exact pinned package refs; prove syntax preservation, round-trip coverage for every graph the package emits, and canonical accepted bytes. No general schema AST, type serializer, or proof bytes. This is P2. | not_started |
| R4 | R1, R3 | Define event and journal codecs plus total state projection. Prove canonical byte boundaries and prove that a prefix carrying the append-history witness folds to the expected structural state without rerunning semantic guards. This is P3. | not_started |
| R5 | R1, R4 | Define package-indexed local-result and external-operation witnesses. Prove exact input/output bytes, local result equality, external request/key/receipt binding, same-key retry safety, and committed-occurrence absorption. This is P6/P7. | not_started |
| R6 | R2, R3, R4 | Use the exact generator package's universal graph/plan law. Prove current-head authorization, exact graph/plan commit before child visibility, global DAG composition, occurrence uniqueness, and allocation-path lifting. This is P4. | not_started |
| R7 | R5, R6, R4 | Prove aggregate charge/fuel equations, exact occurrence projections, and once-only reservation/settlement across the combined journal. Keep global accounting in the machine. This is P8. | not_started |
| R8 | R4 | Define trusted genesis and the authorized append boundary. Prove append-history PrefixWF, exact immutable latest-prefix cuts, canonical loaded bytes, and old-writer fencing. This is P10. | not_started |
| R8b | R3, R6, R8 | For a committed GraphCommitted event, reopen the same exact graph bytes and plan through the pinned package. Prove recovery never regenerates topology or allocations. This is P5. | not_started |
| R9 | R5-R8b | Define the controller transition system. Prove all-schedule claim uniqueness, ready-input agreement, exact-head reauthorization, serial append, commit-before-visibility, no post-commit dispatch, and PrefixWF preservation. This is P15. | not_started |
| R10 | R9 | Prove every started nonterminal state has an enabled legal action or exact same-key resumable intent. This is P11; keep service fairness out of safety. | not_started |
| R10b | R4-R7 | Prove a well-founded rank decreases on every successful post-start append under any serialization order. This is P12 and does not depend on P15. | not_started |
| R11 | R3-R9 | Compose graph decoding, append-history witnesses, operation/result provenance, global ledgers, and every-cut recovery to establish no committed work is replaced or rerun. This is P16. Add P9 only for persistent object identity. | not_started |
| R12 | R1-R10b | State the concrete representation relation and prove a selected runtime refines the abstract contracts. This is P13; it requires the contract proofs and controller safety, not P16. | not_started |
| R13 | R10, R10b, R12 | Prove termination only under explicit fairness, service/adapter/journal progress, finite-fuel, and finite-crash premises. This is P14. Keep all liveness premises out of P15. | not_started |
| R14 | R1-R13 | Audit every theorem dependency and callback proof path for admissions, hidden axioms, duplicate authorities, or an unstated host premise. Verify proof-bearing examples against the public API. Record exactly which guarantees are proved and which depend on external contracts. | not_started |

## Decision register

The detailed questions and proposals at that checkpoint are in [the archived package-owned draft, Section 9](package_owned_implementation_spec.md#9-open-design-decisions). The decisions that gated R1-R3 were:

- D1: `option` decoding for arbitrary bytes versus total decoding behind a validity proof.
- D2: which pinned graph package reconstructs typed graphs after restart.
- D3: whether builder completeness for all finite typed topologies is required.
- D4: which static index/refinement facts suffice for dependent edges.
- D5: how P10 carries ghost `PrefixWF` through physical storage and restart.
- D6: exact operation-package receipt and retry contract.
- D7: whether budgets, artifact identity, liveness, and concrete runtime refinement stay in scope.

## Retired plan components

Do not resume A05's schema AST, package denotation, weakening/substitution, `LegalEnv`, custom equality calculus, or `SchemaSupported` completeness tasks. They were obligations of the former universal-schema proposal. Their historical scratch notes remain under `research/A05-2026-10-14/` as evidence, but they are not dependencies or acceptance criteria here.

Do not move global obligations into package contracts by assumption. P4 graph splice, P8 combined ledger conservation, P10 prefix-history transfer, P15 controller safety, and P16 recovery composition stay in the machine because each relates multiple nodes/events or the whole run.
