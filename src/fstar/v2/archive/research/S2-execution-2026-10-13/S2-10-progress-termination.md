# S2-10 — Progress, fairness, no-loop, and termination

## Scope and decision

S2-10 covers P11 `frontier_total_and_no_stuck`, P12
`no_infinite_progress_cycle`, and P14 `conditional_termination`. The work is
specification-level only. P11 proves a logical enabled action exists in every
started reachable nonterminal state; it does not prove a scheduler or service
will perform it. P12 rules out an infinite sequence of successful legal
journal appends. P14 composes frontier existence, strict rank decrease,
concrete refinement, and explicit fairness/service premises to establish
eventual output for a started run.

## P11: the logical frontier is nonempty

The enabled frontier is constructor-defined: a ready unexpanded local node
has `RunLocal`; a ready unexpanded generator has `GenerateGraph`; a ready
external node without intent has `BeginExternal`; an external node with a
committed intent but no outcome has same-key `ResumeCall`. Readiness requires
only the committed values referenced by that node's input wire. An occurrence
with committed completion or graph expansion is absent from the frontier.

For a finite DAG, every nonempty unfinished dependency-closed portion has a
ready vertex by strict topological rank. A pending external intent itself
supplies a resume action. Once the root graph and root input have committed,
either the derived root result is terminal or one of those cases gives a
legal action with an abstract continuation. The pre-`RunStarted` empty journal
is bootstrap and outside P11. Adapter capacity is a physical dispatch bound,
not a filter on logical frontier membership; response/capacity service is a
P14 premise.

## P12: strict rank for every successful append

For replay state `S`, define:

- `G(S)`: sum of committed expansion fuel allocated to all unexpanded
  generators;
- `U(S)`: number of unexpanded generator occurrences;
- `W(S)`: sum of phase weights for incomplete local/external occurrences:
  local pending `1`; external pending `2`; external intent committed `1`.

Order `(G,U,W)` lexicographically over `nat^3`. Every initial started graph is
finite and its ledger values are finite naturals, so the initial rank is
finite.

For `GraphCommitted` with parent fuel `b > 0`, the parent allocation `b` is
replaced by nested-generator allocations with sum `F < b`. Thus `G` strictly
decreases regardless of how many finite ordinary nodes the generated graph
contains. If `b = 0`, every nested generator must nevertheless receive
positive fuel by P4's allocation law, so there can be no nested generators;
`G` is unchanged and `U` decreases by one. Root generators may have zero
fuel, but the nested-generator rule still applies to their output graph.
`NodeCompleted`, `CallIntent`, and `CallOutcome` preserve `G,U` and lower `W`
by one. Therefore every successful post-start event strictly lowers the
well-founded rank. Stale/rejected appends are not state transitions. The
journal serializes commits, so arbitrary concurrent completion order applies
one of these decreases per accepted event; no global ordering of worker
completion is needed.

## P14: explicit conditional termination

P14 applies after a valid `RunStarted` has committed. It assumes:

1. weak fairness for every continuously enabled ready claim;
2. total local, generator, and validator computations, plus executor progress
   that makes each claimed local/generator computation return its result to
   the controller and offers completed results to the serial append path;
3. every authorized append or stale-head retry eventually commits or is
   definitively rejected and fully reauthorized;
4. every completed adapter response is eventually consumed, releasing any
   occupied capacity; P7 supplies fair retry/query service and eventual
   terminal outcome or definitive reconciliation for each admitted key;
5. required artifact resolutions eventually complete, when the selected
   workflow action needs them;
6. only finitely many process exits.

P11 supplies a legal action when nonterminal; P12 prevents infinite successful
append progress without terminal completion; P13 supplies the concrete
runtime refinement and fairness behavior. The claim is conditional: failure
of an explicit service or fairness premise does not imply a safety failure,
but may prevent progress. No journaler concurrency premise is required.

## Contradiction reconciled

The theorem guide previously said no positive-fuel rule was needed for child
generators. That conflicted with the normative P4 allocation contract and
made the zero-fuel rank case invalid. The guide now agrees with the existing
spec: root generators may have zero fuel; every nested generator receives
positive fuel. No DAG topology, acceptance rule, or theorem dependency was
changed.

## Review evidence

- P11 frontier/capacity audit: no state-shape counterexample. It confirmed
  disconnected vertices remain actionable, empty/constant-output graphs are
  terminal when their derived result is available, and capacity is liveness,
  not frontier safety. It flagged wording that conflated action existence and
  eventual service; §5 now separates P11 from P14.
- P12 rank audit: passed after reconciling zero-fuel child wording. The
  `(G,U,W)` decrease holds for arbitrary finite child graph size and all
  serializations of concurrent completions.
- P14 interleaving/fairness audit: serial journal append is sufficient;
  bounded multi-inflight external calls are compatible with P14 if response
  consumption frees capacity fairly. It flagged ambiguous pre-start scope and
  vague fairness wording; §5 and the theorem table now scope liveness after
  committed `RunStarted` and state the service clauses explicitly.

## Limits

These are theorem contracts and proof targets, not discharged F* proofs.
S2-11 must define concrete refinement obligations for how a runtime proves
these service, fairness, crash, and fencing premises. The current S2 work does
not edit F* source or run the verifier or tests.
