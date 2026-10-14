# S2-05 — canonical journal and replay machine

**Status:** complete at specification-contract level. **Scope:** P3 and the
S2-05 acceptance row. This document records design decisions and audit
resolution; it is not a proof report. No `.fst`/`.fsti` file, implementation,
F* invocation, or test was run.

## Result

The normative specification now defines the journal as the only durable
workflow-control state and `replay_C(J)` as its deterministic state function
under one immutable pinned resolver and `JournalCodec`. The empty journal
replays to the unique unstarted state. The event sequence itself supplies
zero-based sequence numbers; `RunStarted` records the run identity once, and
later `EventNodeRef`s use paths relative to that run. This avoids copying
derivable run/sequence/version fields into every event. The journal format
identity is fixed across restart.

Five event constructors are specified: `RunStarted`, `GraphCommitted`,
`NodeCompleted`, `CallIntent`, and `CallOutcome`. The spec gives a guard,
exact state delta, and append-authorization fact for each. Replay validates
structure, typed payload resolution, local graph validity, and ledger updates;
it does not execute local code, generators, or adapter effects.

## Central separation

`StateWF` is replay-checkable. It covers legal event order, unique graph/node
occurrences, exact indexed decoding at reconstructed inputs, local graph
well-formedness, one-time statuses, and ledgers. `GlobalGraphWF` is separate:
P4 proves graph commitment preserves typed global DAG structure through
boundary substitution. `SemWF` is ghost provenance from the linearized
authorized append trace. It records that the root event came from the pinned
entrypoint, a graph commit came from the exact generator result, a local
completion equals pinned `CodeRef.run`, and external outcomes came from the
same intent under the pinned validator/adapter contract. These properties do
not follow from canonical bytes, types, replay, or `StateWF`.

The sole abstract write operation is `append_authorized`, indexed by the
exact prefix, replayed state, and an `AppendPermit` containing `StateWF`, the
structural event guard, and `AuthorizedEvent`. Its transition relation says:
matching prefix commits exactly `prefix ++ [event]`; stale prefix leaves the
stored journal unchanged. The raw storage write path is private to this
operation. A stale-head request must reload, replay, reconstruct inputs, and
reauthorize. The concrete coordinator/write-path refinement remains P13;
atomicity, byte persistence, and crash-cut behavior remain P10.

`Terminal` is a derived exact condition: every generator is expanded, every
local and external occurrence has its one completion, and the root output wire
evaluates from committed values. It includes valid empty or constant-output
graphs. Terminal state has no enabled work and rejects all appended events;
no `RunTerminal` event is needed.

## Canonical encoding boundary

The fixed `JournalCodec` supplies separate event and full-journal round-trip
and exact re-encoding laws. Event constructor tags and field framing are
unambiguous; journal framing preserves order and rejects trailing or
noncanonical encodings. Nested graph and typed output payloads use exact
pinned codecs and reconstructed indices. Syntax/encoding validity is not
authorization. P10 connects stored bytes to the exact loaded event list and
proves prefix durability across cuts. P0/P2 provide manifest and graph/value
codec coherence; they do not replace the journal codec.

## Audit synthesis

Three independent read-only audits were integrated:

- **Transition model:** required a non-circular event machine, exact guards
  and state deltas, explicit pre-start state, derived ledgers, and terminal
  equivalence. The spec now has an exhaustive five-row guard/update/origin
  table, explicit `initial_state`, and a separately stated invariant.
- **Encoding:** distinguished indexed payload, event, and journal
  canonicality; required one immutable format identity and physical bytes to
  exact-prefix refinement. The spec adds `JournalCodecIdentity`, separate
  event/journal laws, a fixed replay context, and leaves physical refinement
  to P10.
- **Provenance:** exhibited canonical, replay-valid wrong root/local/external/
  generated results. The spec requires event-specific `AuthorizedEvent` at
  the exact current replay head and an authorized-trace induction. P3 claims
  only structural replay facts; P15/P10/P16 compose authorization and recovery.

The audit suggestion to store run identity, sequence, and version in each
event was considered and not retained: sequence is the journal list position,
run identity is fixed by the first event, and format identity is fixed in the
replay context. This keeps one source for each fact while preserving stable
`(run, sequence)` event identity. Adapter resume bytes remain an opaque,
canonically framed event payload at this layer; P7 must define their pinned
interpretation and safe resumption semantics.

## Remaining theorem work

No P3 proof has been discharged in F*. The next design nodes must formalize
all-interleaving execution (P15), multi-inflight effect-safe adapter calls
(P7), resource/accounting contracts (P8/P9), and exact physical journal
recovery (P10). P16 still composes these into recovered semantic graph
correctness. All correctness statements remain conditional on the explicit
codec, resolver, executor, adapter, resource-store, and journaler contracts.

## Evidence

- [Transition model audit](S2-05-transition-model-audit.md)
- [Encoding audit](S2-05-encoding-audit.md)
- [Provenance audit](S2-05-provenance-audit.md)
- Normative [implementation specification](../../../implementation_spec.md),
  §4.1 and §5, and [key correctness theorem guide](../../../key_correctness_theorems.md)
