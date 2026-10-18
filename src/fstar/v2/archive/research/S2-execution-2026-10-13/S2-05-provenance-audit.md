# S2-05 adversarial audit: replay WF versus semantic provenance

Audit scope: `implementation_spec.md` §4.1 and §4.4; `key_correctness_theorems.md`; S2 DAG acceptance. Read-only audit otherwise; no F* run. This is a target audit, not a proof report.

## Verdict

**S2-05 acceptance is not yet met by the written contract alone.** The spec correctly separates replay-checkable `WF(J,S)` from ghost `AuthorizedTrace(T)` / `SemWF(T,J,S)`, and names the right provenance origins. But §4.1 leaves an interface seam: `append_store` takes only `(expected_head,event)` and its transition law requires a legal `apply` event; later prose says only the coordinator can append a semantically authorized event. Those are different predicates. If the former is the actual append guard, replay-valid unauthorized events pass. If the latter is an extra journaler law, it must be made an explicit proof-carrying contract/interface, with P15 proving authorization construction and P13 proving concrete refinement. Calling events authorized in a contract does not itself derive their provenance.

No circularity is forced if provenance is defined event-by-event against the prior replay state and the executor proves each authorization before append. It becomes circular/incomplete if `SemWF` is assumed by P15 for every successor, or if “legal event” is defined as “event from authorized history” and P3 then claims to establish that property from replay alone. P3 should establish replay `WF` and terminal facts; P15 establishes authorized extension; P10 transports the authorized append trace across cuts; P16 composes them.

## Replay-valid, unauthorized journals

These are counterexamples to `WF => SemWF`, not counterexamples to the full contract if the verified append boundary is enforced:

1. **Wrong local result.** Start with authorized root graph containing `f : A -> B`; record `NodeCompleted(k, encode_B(y_bad))` where `y_bad : B` is canonical, well typed, but `y_bad != f(x)`. Replay can reconstruct `x`, decode bytes, and accept event shape/order. Local provenance fails.
2. **Wrong external result.** For an existing `CallIntent(k, request)`, record a canonical output at the right indexed type, with evidence/key fields matching the intent, but where the pinned validator returns `None` or a different `y`. Correlation and typing do not imply validator acceptance.
3. **Wrong generated topology.** Record a canonical, schema-supported child graph and valid local plan at the right generator occurrence/input, but different from `generate_graph(x,a)`. Resolver, codec, occurrence lift, allocation fit, and DAG splice can all succeed; generator provenance fails.
4. **Wrong root graph.** `RunStarted` contains a canonical supported graph/plan but not the result of the pinned root entrypoint on its recorded input and budget. Replay can validate the graph without establishing constructor provenance.

Thus event bytes, canonicality, type correctness, legal order, and even graph/allocation validity cannot establish semantic origin. An attacker with a raw journal write path can manufacture all four histories. §4.4 explicitly excludes external mutation and requires protocol integrity; such a history violates that store contract. But replay alone must reject none of them on semantic grounds.

## Provenance induction invariant

Use one append trace `T = [e0,...,en]` with ghost per-append witnesses; for each prefix `J = take(n,T)`, define `S = replay(J)`. Induct on authorized append count:

```text
AuthorizedTrace(T) :=
  T starts with RunStarted authorized by pinned root entrypoint, exact input,
    budget, canonical graph bytes, and exact plan;
  for every later event e at index i:
    S_i = replay(take(i,T)) is Ok;
    exists auth_i : AuthorizedEvent(S_i,e);
    e is exactly the payload committed at current head i under auth_i.

SemWF(T,J,S) :=
  J is a prefix of T
  /\\ S = replay(J) = Ok
  /\\ WF(J,S)
  /\\ every event in J retains its corresponding AuthorizedEvent witness.
```

`AuthorizedEvent(S,e)` must be disjointly defined by event constructor:

- `RunStarted`: exact pinned root constructor result for decoded root input and budget.
- `GraphCommitted`: exact canonical `GeneratorRef.generate_graph(x,a)` descriptor and graph-local plan, where `x` and `a` are reconstructed from `S`.
- `NodeCompleted`: exact canonical encoding of `CodeRef.run(x)` for reconstructed exact input `x`.
- `CallIntent`: ready adapter occurrence, stable exact occurrence key, canonical request derived from reconstructed input; at most one intent.
- `CallOutcome`: existing exact intent/key/request; pinned validator accepts this keyed reply at reconstructed exact input and produces the encoded output; settlement/artifact clauses match the corresponding contracts.

Induction step: `SemWF(T,J,S)`, current-head authorization witness for `e`, and successful append of exactly `e` imply replay/apply success, `WF(J++[e],S')`, and `SemWF(T++[e],J++[e],S')`. Rejection leaves both journal and invariant unchanged. A stale head invalidates/requires reconstruction and reauthorization; witness cannot be retargeted by changing sequence number.

Origin witnesses are ghost proof values, not journal bytes. Their producers are the trusted abstract workflow kernel and proof-bearing pinned contracts: local/generator results are recomputed values of total pure pinned functions before commit; external result is produced by pinned validator after exact intent correlation; root is pinned constructor. They are not supplied as unchecked adapter claims. For a concrete runtime, P13 must show these exact checks and append fencing refine the abstract kernel.

## Contracts and trust boundary

Minimum missing precision for S2-05:

1. State `apply`/`replay` as checking only replay `WF`; define `AuthorizedEvent` separately. Do not silently let the meaning of “legal transition” alternate between the two.
2. Give coordinator append a proof-bearing input, conceptually `append_authorized(head,e,auth : AuthorizedEvent(replay(head),e))`. Journaler law binds committed bytes to that exact `(head,e,auth)` and forbids raw append or external mutation. If proof erasure requires runtime checks, identify which checks enforce each constructor case.
3. Make the `RunStarted` authorization explicit. A trusted initial event without root-entrypoint equality breaks the induction base.
4. State authorized-trace induction and `RecoveryPreserves`: cut loads prefix of the same linearized append trace; ghost witnesses restrict to that prefix; `recover = replay(prefix)`. P10's atomicity/prefix properties alone do not manufacture witnesses.
5. State the assurance boundary plainly: P15 is an abstract theorem from pinned executable definitions and proof-bearing contracts; P13 and the store refinement prove actual controller/journaler/adapter implement that boundary. If `append_store` itself is only an assumed oracle that enforces semantic provenance, this is a trusted theorem parameter, not a proved journaler implementation.

This is not inherently a circular proof: define constructors and authorization predicates first, prove authorization soundness and transition preservation, then prove trace induction. Circularity appears only if a premise already asserts the P15 conclusion (e.g. “all appended events authorized”) without a lower-level coordinator proof, or if P3 is asked to infer semantic provenance from replay bytes.

## Terminal state and event minimality

Terminal derivation is sound in shape: derive it from committed graph state, all generator occurrences expanded, all ordinary occurrences complete, and evaluation of the root output wire from committed outputs. No `RunTerminal` event is needed; a separate terminal event duplicates a pure journal projection and creates disagreement risk. Require the terminal predicate to be exact in both directions: `terminal_output(S)=Some t` iff this complete condition holds and wire evaluation yields `t`. Absorption then follows from no enabled actions plus `apply` rejection from terminal state.

Counterexample if terminal predicate is weaker: graph has completed ordinary nodes but an unexpanded generator whose output is not yet available; or root wire references a missing output. “All nodes complete” can be ambiguous because unexpanded generators are nodes, but exact predicate resolves it. Also ensure zero-node/constant-output graphs can be terminal immediately after valid `RunStarted`; otherwise a run can get stuck with no actions and no terminal. Empty output port is permitted only if graph language allows it and typed wire evaluation is total.

Event minimality looks sound provided omitted data is uniquely derivable: identities/input/codec from pinned graph + replay state; occurrence paths from parent generator; reservation from ledger; terminal result from wire. `CallOutcome` needs enough correlated reply/evidence to verify validator provenance, and artifact references need their own P9 law if backing durability claimed. No extra terminal event or duplicated generator identity needed.

## Strongest objection and acceptance consequence

Strongest objection: a serial journaler whose checked rule is merely “expected head and `apply` accepts” can durably commit the bad local `NodeCompleted` above. Thereafter every byte-level, canonical replay, and crash-prefix guarantee succeeds, while recovered state falsely claims the pinned computation ran. The separate §4.1 prose requirement “only ... current-head-authorized append” repairs this only if represented as an explicit contract with constructor-specific witness and a proof path; no raw journal mutation can bypass it. P13 being future work means this abstract boundary is not yet implemented or proved in source.

Against S2-05 DAG row: **conditional / revise artifact before acceptance**. Row asks for transition contracts specifying authorization and result-validation predicates, not implementations. Audit found predicates stated narratively across §4.1, §4.2, §4.3, but append interface and induction contract remain underspecified. Add the five items above; do not claim a discharged theorem. Strong target remains P3 replay WF + deterministic replay/terminal absorption; P15 authorized interleavings; P10 prefix durability; P16 semantic recovery. Evidence ledger says all are absent from source today. This report does not establish any theorem.
