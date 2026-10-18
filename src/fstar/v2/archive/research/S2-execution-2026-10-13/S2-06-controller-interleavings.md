# S2-06 — Concurrent abstract executor

**Status:** complete at specification-contract level. P15 remains a theorem
target; this report does not claim a source proof.

## Result

Section 4.2 of `implementation_spec.md` now defines one controller per run,
with a duplicate-free durable frontier and bounded volatile execution. Ready
local and graph-generator occurrences may be claimed concurrently; each claim
binds the occurrence to its exact pinned identity, reconstructed input, and
committed allocation. `ReadyInputAgreement` connects sparse committed-input
reconstruction to the full typed graph evaluator for every legal environment.
Claims and candidates are volatile and do not enable dependents.

Worker candidates retain ghost origin witnesses. Append preparation reloads
and replays the current journal prefix, rechecks all claim bindings, and
constructs a fresh event-specific `AuthorizedEvent` proof. Only one append is
active; its commit point changes the durable prefix and exposes outputs.
Stale appends are no-ops and require complete reauthorization. Completion
order may vary, but a committed local result or graph expansion leaves the
durable frontier and cannot be scheduled again.

P15 is stated over every finite controller schedule and carries the replay,
`StateWF`, `SemWF`, global DAG, claim, candidate, append, and ledger invariants.
The ghost authorization trace is exactly the successful append-linearization
history; at every recovery cut, its journal prefix contains exactly the
witnesses for commits visible at that cut.

## Crash, callback, and bootstrap rules

The crash/recovery cut is the linearization point of a load after all prior
append requests have committed or aborted. An old append cannot commit after
that load, and the restarted controller schedules no work before it. The
prefix loaded after the barrier includes any request that committed before
the barrier. This rules out the dangerous schedule “load old prefix, rerun a
node, then an old append commits behind the new controller.” P10 states the
store law; P13 must implement its drain/cancel/fence mechanism.

Each attempt uses a fresh, non-reused controller epoch plus a local nonce.
Returns from a revoked epoch are discarded. P13 must prevent callbacks from
crossing restart or identify and fence them. A pre-commit `RunStarted` retry
must use the identical `StartRequest`; changing input, entrypoint, or budget
requires a fresh run identity and journal. Global uniqueness of run identity
in an adapter-key namespace is an allocator/caller premise refined by P13,
not a property established by per-journal append.

## Audit provenance

- `S2-06-concurrency-audit.md`: ownership, sparse readiness, schedule and
  claim obligations.
- `S2-06-crash-interleavings-audit.md`: commit visibility, stale append,
  crash cuts and response races.
- `S2-06-authorization-audit.md`: non-circular append authorization and
  candidate provenance.
- `S2-06-provenance-induction-review.md`: `RunStarted` base case, `SemWF`
  induction, and proof-witness retention.
- `S2-06-store-boundary-review.md`: prior-epoch append settlement/fencing
  before recovery load.
- `S2-06-integrated-review.md`: epoch freshness and P13 boundary.
- `s206_final_audit` final review: confirmed listed S2-06 acceptance with no
  remaining gap or DAG topology change.

## Boundary

P15 assumes P10's store-cut law and the proof-bearing local/generator/adapter
contracts. P7 still owns safe external retries and multi-inflight outcome
correlation; P10/P13 own durable append/load behavior and its concrete
refinement; P8 owns aggregate ledger conservation. No F* source, tests, or
implementation were changed or run.
