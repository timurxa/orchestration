#import "state_machine_api_styles.typ": *

#set page(paper: "us-letter", margin: (x: 18mm, y: 16mm))
#set text(size: 9.5pt)
#set par(leading: 0.58em)
#set heading(numbering: "1.")
#show heading.where(level: 1): set text(size: 15pt, weight: "bold")
#show heading.where(level: 2): set text(size: 11.5pt, weight: "semibold")

#align(center)[
  #text(size: 21pt, weight: "bold")[State-machine contract audit]
  #linebreak()
  #text(size: 12pt, fill: rgb("52616D"))[Tautologies, redundancies, and permitted behavior]
  #linebreak()
  #text(size: 9pt, fill: rgb("52616D"))[18 October 2026 · adversarial review of the current WIP]
]

#v(8pt)

#status-panel("Derived", title: "Result", number: "A1")[
  No independent proof obligation in the current machine contract is a
  tautology. The actual laws constrain independent sources: state observations
  against event history, event payloads against node computations, accepted
  transitions against valid history extensions, DAG productivity and
  terminality, and journal round trips.

  The audit found a few duplicate presentations and derived projections. The
  WIP cleanup removes those repetitions without weakening a law. No new
  likely-unintended behavior satisfying all current contracts was proven. The
  concrete behaviors found are already called out as intentional or outside
  the core guarantee.
]

= Scope and standard <sec:scope>

This report audits the current [WIP specification]("state_machine_api_wip.typ")
as mathematical pseudocode, not as compiler-checked F\*. A *tautology* is a
proposition entailed by its definitions alone. A *redundancy* is a nontrivial
condition entailed by another required law. A permitted bad behavior requires
a concrete model satisfying every relevant contract, not a hypothetical
caller that supplies a useless definition or proof.

Machine observations are produced by `lookup_occurrence`, the three action
queries, and `terminal_output`. The independent history model is computed
from the static/generated occurrence interpreters, LEG implementations, and
valid event data. `StateRepresents` equates these two sides; replaying the
machine's own `accept_event` is not its definition.

= Actual proof-bearing obligations <sec:obligations>

The current construction obligations are:

#table(
  columns: (1.15fr, 1.75fr, 2.8fr), inset: 5pt,
  stroke: 0.5pt + rgb("C7CED4"),
  [*Owner*], [*Condition*], [*What it constrains*],
  [`initial_state` field], [`StateRepresents(..., EmptyHistory)` refinement], [Initial lookup, query bags, and terminal output match the empty-history model.],
  [`StateRepresents` refinement], [Observation agreement plus `QueryDescriptorAgreement`], [Each represented state exposes exactly its history-selected occurrences, completed values, ready actions, and root output.],
  [`accept_event` field], [`AdmissibleNow ==> Some`; and every `Some` preserves every represented history under one appended valid event], [No offered, fresh event can be silently dropped; no successful update can corrupt the represented history.],
  [`ResultCertificate` argument], [For every matching queried action, event descriptor, input, and LEG result equation agree], [Caller proves the result belongs to the currently offered node work; no runtime equality test on arbitrary values is needed.],
  [Selected `DagInstance`], [`DagProductivity` and `HistoryTerminalCoherence`], [Every declared unfinished occurrence has some finite valid completion path; root output is equivalent to no ready work.],
  [`History` constructor], [`EventValidAt` for the preceding prefix], [Only declared, uncommitted, input-correct, result-correct, fresh graph completions extend a history.],
  [`StateJournaler`], [`decode(encode(s)) == Some(s)`], [A journal produced by this journaler restores exactly the runtime state.],
)

The interpreters are independent source-of-truth fields, not extra proof
claims. `DeclaredOccurrence`, readiness, `EventValidAt`, and the observation
models are definitions. `HistoryObservationFaithful` and input assembly are
derived proof work, not machine construction fields.

= Tautology audit <sec:tautologies>

== No required law is tautological

Each required law has a countermodel if that law is removed while the other
independent laws remain:

#table(
  columns: (1.2fr, 3.4fr, 1.3fr), inset: 5pt,
  stroke: 0.5pt + rgb("C7CED4"),
  [*Law/component*], [*Countermodel to show it constrains behavior*], [*Verdict*],
  [`StateRepresents`: occurrence-state map], [A static root is declared in empty history, but `lookup_occurrence` returns `None`; keep the ready action and terminal observations correct.], [Substantive],
  [`StateRepresents`: action bags], [A declared root is ready, but its corresponding query omits `(id,input)` while lookup remains correct. Repeat independently for local, external, and generator queries.], [Substantive],
  [`StateRepresents`: terminal output], [After root completion, `terminal_output` returns `None` while lookup and query bags remain correct.], [Substantive],
  [`QueryDescriptorAgreement`], [The query returns the right `(id,input)` but its ghost descriptor selects a different same-ID backing implementation; the executable action bag alone cannot detect it.], [Substantive],
  [`initial_state` refinement], [A two-state machine chooses a state with empty lookup/queries for a ready static root; it disagrees with the empty-history model.], [Substantive],
  [`accept_event` completeness], [A valid, offered, fresh event is always answered with `None`.], [Substantive],
  [`accept_event` preservation], [A valid root completion is answered with `Some` stale state still showing the old action and no root result.], [Substantive],
  [`ResultCertificate`], [A matching action exists but event has a wrong local result, generator graph, or validator-rejected external result; no certificate can be supplied.], [Substantive when offered],
  [`EventValidAt`: declaration / descriptor / uncommitted / input / result / freshness], [Respectively append an uninterpreted ID; mismatch the event ghost descriptor with the history-selected same-ID backer; duplicate a completion; use a noncanonical input; use a wrong result; or reuse a static/prior generated ID. Each violates a distinct conjunct.], [Substantive],
  [`DagProductivity`], [Add blocked node `u` depending on a never-generated ID beside a completable root `r`. Only histories `[]` and `[r]` are valid, so terminal coherence holds while `u` has no completion suffix.], [Substantive],
  [`HistoryTerminalCoherence`], [A static root and an independent ready node exist; complete the root first. Root output is present while the independent action remains ready.], [Substantive],
  [`StateJournaler` round trip], [For two states, encode both as the same bytes and decode those bytes to only one state; round trip fails for the other state.], [Substantive],
)

The `EventValidAt` constructor proof is therefore not vacuous. Its type
requires the history-specific checks even though a completed `History` is
valid by construction. Likewise, `StateRepresents` is a definition, but its
independent observation equality is substantive: omitting any component
permits the corresponding countermodel above.

The productivity and terminal-coherence laws are independent of each other.
For productivity without terminal coherence, use an independent ready node
`u` beside a valid root `r`, then complete `r` first: `u` remains ready. For
terminal coherence without productivity, use a completable root `r` and a
blocked declared node `u` depending on a prerequisite no generator can add.
The only valid histories are the empty history and completion of `r`; the
root/action biconditional holds on both, while `u` has no valid completion
suffix. Thus neither DAG law duplicates the other.

`HistoryObservationFaithful` is a nontrivial derived theorem, not a field.
It must show that the event-data bag retains enough typed values and graph
payloads to compute the same occurrence map, ready-action bags, and root
result as the ordered history. It is still open proof work O2 in the WIP.

== Derived statements are not extra tautological fields

The following are projections or consequences, not independent obligations:

- `InitialStateRepresents` is exactly the refinement on `initial_state`.
  The duplicate standalone equation has been removed.
- `CompletedResultMatchesHistory` is the completed-value projection of the
  full occurrence-state lookup agreement. The full map law also checks
  undeclared and pending occurrences.
- `NodeInputAt = Some(input)` implies `PrerequisitesDone`: source collection
  returns `None` when any occurrence-valued source is missing.
- `DagInputAssemblyLaw` follows from productivity, `EventValidAt`, and
  stability of declarations and completed values along valid extensions. It
  is a named theorem, not a second DAG proof field.
- `Some ==> AdmissibleNow` follows from successful preservation, event-sequence
  extensionality, query visibility, and the lookup/freshness bridge. It is not
  repeated in the `accept_event` return contract.
- `FreshGeneratedAgainstState` and `FreshGeneratedIds` express the same
  freshness condition at two interfaces. Under `StateRepresents` and the
  generator result equation, the state lookup test is equivalent to absence
  of a prior history declaration. Both forms are needed: one is the
  history-constructor rule, the other is the no-history-argument admission
  guard.
- `ExclusiveGraphMembership` follows by induction from freshness and
  functional interpreters; it is not a third proof field.
- Query visibility, action-input correctness, duplicate-action exclusion,
  and terminal-output agreement are projections of the observation law.
  `QueryDescriptorAgreement` remains separate because the executable action
  observation is only `(id,input)`.

Event shape is already encoded by the dependent LEG event aliases. They
enforce the constructor kind, occurrence-ID index, and payload type. The
WIP's `EventPayloadTypedFor` now states only the substantive equality between
the event's ghost descriptor and the descriptor independently selected by
history. That equality transports the dependent payload.

The `accept_event` result certificate remains necessary. Its universal
quantifier over matching actions does not impose a second result contract:
the query-bag law and unique occurrence meaning allow at most one matching
action in a represented state. It also deliberately remains vacuous when no
matching action exists, so a stale or unrelated event can be passed and
rejected; `ActionOffered` is separately required for admission completeness.

= Proven redundancy cleanup <sec:cleanup>

#status-panel("Derived", title: "WIP edits made", number: "A2")[
  The cleanup changes only repeated or type-implied presentation. It does not
  remove a behavioral obligation.
]

- Replaced the inline `lookup_occurrence` result shape in `MachineForInput`
  with the shared `OccurrenceLookupResult` alias.
- Reduced `EventPayloadTypedFor` to descriptor equality; the event aliases
  already enforce kind, ID index, and dependent payload shape.
- Removed the standalone `accept_event` signature because the record already
  gives that exact refined type.
- Removed the standalone `InitialStateRepresents` equation; it was the same
  refinement already attached to the `initial_state` field.
- Removed an unused `HistoryEquivalent` alias that duplicated event-bag
  equality and risked confusion with the future-relevant
  `HistoryStateEquivalent` relation.

The named projections and derived theorems remain in the WIP where they
explain why the single machine law suffices. No actual machine proof field
was deleted.

= Behaviors that remain permitted <sec:permitted>

The audit found no new likely-unintended behavior satisfying all current
contracts. These concrete behaviors are allowed but explicitly classified:

== Explicitly intentional or outside this core

- *An infinite generated chain need not terminate.* Let each finite graph
  add one fresh generator occurrence that produces the next graph. Every
  finite history has one valid next completion, so each declared occurrence
  has a finite completion path. There is never a root result or quiescent
  history. Productivity and terminal coherence both hold, yet an infinite
  execution is possible. The WIP intentionally excludes termination/ranking.
- *Query list order is unspecified.* The invariant compares action bags,
  not list order. Two implementations can return `[a,b]` and `[b,a]`; a
  runner that dispatches the first item may choose different work. Scheduling
  policy is outside the machine's observable contract.
- *Raw arbitrary bytes are not guaranteed to recover a represented state.*
  Round trip constrains only bytes produced by `encode_state`. A decoder may
  return `Some(bad_state)` for unrelated bytes. Recovery guarantees require
  producer provenance; arbitrary-byte validation is assigned to the adapter.
- *An ID can have different meanings in alternative histories.* Freshness
  prevents rebinding within one history, while different generated branches
  may interpret the same ID differently. This enables runtime-dependent
  topology and is an intended property.
- *A static occurrence may wait on an ID introduced by a later graph event.*
  This forward-reference graph grafting is explicitly allowed.

These are not undisclosed failures. If any becomes undesirable, its policy
must be changed explicitly rather than inferred from the existing consistency
laws.

== Plausible candidates blocked by the current laws

- A phantom or already declared graph ID cannot be introduced by a valid
  generator event: `FreshGeneratedIds` ranges over every interpreted ID and
  rejects any prior static/generated declaration.
- A second completion for the same ID cannot extend a valid history because
  `Uncommitted` is required.
- One runtime state cannot represent histories with different completed
  typed values: its functional lookup must equal both history maps, which
  would require the same entry to equal, for example, both `Some(false)` and
  `Some(true)`.
- A wrong result or noncanonical input cannot enter a valid history because
  `NodeInputAt` and `NodeResultCorrect` are required, and the caller's result
  certificate ties an offered event to its queried action.
- Root completion with ready detached work, and a deadlock with no root
  result, both violate `HistoryTerminalCoherence`. Productivity rules out
  hidden unfinished occurrences at a quiescent root state.

= Remaining proof risks <sec:risks>

The countermodels and implications are mathematical checks of the WIP
formulas, not mechanized F\* proofs. Before implementation is considered
verified, the following derivations still need explicit F\* lemmas:

- `HistoryObservationFaithful` over the bag projection and dependent result
  indices.
- Event-sequence extensionality for deriving `Some ==> AdmissibleNow` from a
  returned history whose event sequence is the requested append.
- Stability of occurrence descriptors, completed source values, and pure
  assembler results for the `DagInputAssemblyLaw` derivation.
- Dependent equality transports for descriptor equality and result payloads.
- Recovery of the erased represented-state witness under the journal
  provenance premise.

If one of these bridge lemmas fails in F\*, that is a proof gap in the current
design, not evidence that its contract was tautological. The next useful
formalization target is to prove the history-bag, append-congruence, and
sequence-extensionality lemmas, then verify `accept_event` preservation.
