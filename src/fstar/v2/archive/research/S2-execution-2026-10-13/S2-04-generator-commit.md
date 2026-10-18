# S2-04 — Generator admission, occurrence lift, and graph commit

**Status:** complete at specification-contract level. The normative text and
the theorem guide have been reviewed by two independent graph/recovery and
rank auditors; root checked the claims against the event grammar and allocation
rules. This is specification and proof architecture only. No generic F* proof,
source edit, verifier run, or test is part of this node.

## S2-04 decision

Each pinned generator is a total pure function of its exact typed input and
ledger-derived `(expansion_fuel, charge_allocation)`. Its admission law is
universal over every input and allocation: returned descriptor is
`SchemaSupported` at that input, and returned graph-local allocation plan
aligns with graph node order and fits the parent allocation. Runtime
authorization commits exactly the returned graph bytes and local plan.

Events store local `NodeKey`s and allocation values, not derived
`NodeOccurrence` IDs. Root graph identity is `RootGraph(run_identity)`; a graph
introduced by committing generator occurrence `p` is
`ChildGraph(p.graph,p.key)`. Replaying the event deterministically lifts each
local plan key `k` to `NodeOccurrence(child_occurrence(p),k)`. Graph-local keys
are unique; one absorbing `GraphCommitted` transition is allowed per generator
occurrence. This gives injective occurrence paths without adding a second
event field or making the event sequence part of plan construction.

P4's graph splice replaces the generator vertex with the admitted child DAG,
wires the generator input into the child's root port, and substitutes the
child output wire for every use of the generator output. The child's exact
boundary indices match the removed vertex: input is the committed generator
input; output type is `o x`. Hence all existing edge equalities remain valid.
Child internal edges are acyclic; their incoming dependencies come only from
ancestors of the generator and outgoing dependencies lead only to its
descendants. The splice preserves `global_dag_wf`, the root output type, and
occurrence uniqueness. Replay exposes no child action before the graph commit.

P5 combines canonical graph decode/resolution, deterministic plan lifting,
`SemWF` append provenance, and every-cut recovery. Recovered state reuses exact
committed bytes and plan. Generator is never rerun after `GraphCommitted`, and
the event transition rejects a second commit for that generator occurrence.

## Allocation and progress-rank reconciliation

Root plans fit the initial run budget; a root generator may receive zero fuel.
In a generated graph, every nested generator receives positive fuel. Their
fuel sum is strictly below the parent fuel when any are present; it is zero
when none are present. A zero-fuel generator therefore may emit any finite
graph of local/external nodes, but cannot create another generator. External
maximum charges plus child-generator charge pools fit the parent charge
allocation. These are per-plan bounds in P4; global charge/fuel ledger
conservation and settlement remain P8.

The former P12 rank `(G,W)` was false. Counterexample: a zero-fuel generator
with no nested generators may commit a graph with multiple pending local
nodes. `G` remains zero, while `W` grows. Tightening all generators to require
positive fuel would avoid this case but unnecessarily reject flat generated
graphs at zero expansion budget. An ordinal rank `omega^(fuel+1)` per pending
generator also handles arbitrary finite graph sizes, but adds ordinal
machinery. Selected repair is natural lexicographic rank `(G,U,W)`:

- `G`: sum of fuel allocations on unexpanded generators;
- `U`: number of unexpanded generators;
- `W`: local/external phase rank, local pending `1`; external pending `2`,
  intent committed `1`, completed `0`.

A positive-fuel graph commit strictly lowers `G` because nested fuel sum is
strictly smaller than parent fuel. A zero-fuel graph commit has no nested
generators, so `G` stays equal and `U` decreases by one despite any finite
increase in ordinary nodes. `NodeCompleted`, `CallIntent`, and `CallOutcome`
preserve `G,U` and lower `W`. Thus every successful post-start append lowers
`(G,U,W)` in `nat^3`. S2-10 remains owner of the full no-loop and conditional
termination proof; S2-04 records the allocation facts it needs. DAG structure
and acceptance conditions are unchanged.

## Proof spline and boundaries

1. P1/P2 provide one supported graph language, indexed codec, and exact
   resolver for roots and generated graphs.
2. Generator admission proves graph support and allocation-plan validity for
   all inputs/allocations.
3. `lift_root_plan` and `lift_graph_plan` prove deterministic order-preserving
   mapping to unique occurrence paths.
4. Append authorization binds current replay head, reconstructed typed input,
   ledger allocation, exact pinned generator, exact canonical graph bytes,
   and exact returned local plan.
5. Graph splice preserves type boundaries, global DAG structure, root output,
   occurrence uniqueness, and child-visibility-after-commit.
6. P5 plus P10 preserves the committed descriptor and derived allocation at
   every recovered prefix; `SemWF` transports origin facts without rerunning
   generation.
7. P8 separately proves global ledger conservation. P15/P16 compose these
   facts with concurrent execution and crash recovery.

The generic theorems are contract targets, not discharged proofs. The verified
chain generator in legacy V2 history is one example only; it does not prove
generic admission, graph splice, or P5.

## Independent audits

- The architecture audit found the zero-fuel `(G,W)` counterexample. It was
  confirmed by an independent counteraudit. Both identified the same
  `(G,U,W)` repair; root checked the transition cases against the event
  grammar and allocation rules.
- The DAG audit found a representation seam: the generator returns a local
  key plan while `GraphCommitted` had described a lifted occurrence plan as
  returned data. This spec stores only the local plan and derives occurrence
  keys during replay, removing duplicate durable facts. The audit found no
  dependency or topology change necessary.
- The architecture reviewer independently checked all `(G,U,W)` event cases,
  including zero-fuel root generators, and found strict decrease under the
  stated allocation/transition laws. Its report is
  `/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-04-rank-repair-review.md`.
- The graph/recovery reviewer checked the S2-04 acceptance row against the
  integrated P4/P5 text and found exact result binding, graph-local plan
  lifting, typed splice, commit-before-use, and no-regeneration recovery
  covered. Its report is
  `/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-04-graph-repair-review.md`.
- The earlier independent counteraudit supplies the zero-fuel `(G,W)`
  counterexample and independently derives `(G,U,W)`; it also checked the
  event-plan representation seam. Its report is
  `/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-04-rank-counteraudit.md`.
- Root cross-checked each review against the current event grammar and
  allocation clauses. The remaining obligation is to prove the schematic
  `allocation_plan_wf` and `root_allocation_plan_wf` predicates enforce the
  stated equations in a later implementation; this is within S2-04's
  contract-target scope, not evidence that a generic F* theorem is already
  proved. No DAG dependency or acceptance change was needed.

## Carry-forward work

- S2-05 defines replay and proves event application/lift deterministic and
  canonical; it must use this derived occurrence path as the sole mapping.
- S2-06 binds concurrent claims and reconstructed generator inputs to this
  committed state.
- S2-08/P8 prove per-occurrence accounting conservation from local plans.
- S2-09/P5+P10 proves exact durable-prefix recovery and `SemWF` preservation.
- S2-10 formally discharges the `(G,U,W)` decrease and fairness-dependent
  termination theorem.
- S2-12 chooses small F* module boundaries for graph syntax, schema resolver,
  generator contracts, journal/replay, and cross-module proof composition;
  no monolithic implementation module is prescribed.
