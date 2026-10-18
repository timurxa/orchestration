# S2-12 — Theorem dependency and proof-order audit

**Verdict: PASS with one ordering clarification.** Current normative dependency graph is acyclic when P10 is read as the abstract journaler/store law, P15 as abstract executor safety conditional on P10, and P13 as implementation refinement of those abstract contracts. P13’s new simulation section makes this separation checkable. P0–P16 remain theorem targets: source evidence ledger says no system theorem is fully discharged ([S2-00, lines 20–22, 28–44](S2-00-evidence-ledger.md)).

## Dependency audit

`implementation_spec.md` §6 table and graph give this order ([lines 2635–2684](../../schema_era_2026-10-14/implementation_spec.md#L2635)):

1. **Foundation:** P0 pinned identity, manifest, codec, and registry laws. P1 typed graph builder depends on P0. P2 canonical graph codec/resolver depends on P0–P1. P3 replay, event/journal canonicality, `StateWF`, and terminal absorption depends on P0/P2 plus fixed `JournalCodec` laws.
2. **Replay semantics:** P4 generated graph authorization, allocation lifting, and typed global-DAG splice depends on P1–P3. P5 exact generated-graph recovery depends on P2/P4/P10. P6 local output provenance and absorbing completion depends on P0/P3. P7 keyed external intent, validation, effect-safe resume, and receipt provenance depends on P0/P3. P8 charge/fuel conservation and once-only settlement depends on P3/P4/P7.
3. **Durability and abstract execution:** P9 is optional artifact publication/backing identity, based on P0–P3 plus artifact-store contract. P10 canonical bytes and every-cut prefix depends on P0–P3 plus journaler laws. P15 all-interleaving executor safety depends on P0–P8 and P10. P11 frontier/no-stuck depends on P1–P8 and P15. P12 rank decrease depends on P3–P8.
4. **Concrete/system theorems:** P13 concrete refinement depends on P0–P8, P10–P12, and P15; add P9 only when asserting persistent resource identity. P16 semantic recovery depends on P0–P8, P10, and P15; P9 is likewise optional for physical artifact identity. P14 conditional termination is last, depending on P11–P13 and their fairness/service premises.

One ordering clarification: P5 must be completed before any result claiming “recovery uses exact committed generated topology.” It is included by the inclusive shorthand P0–P8 in P15/P16, and explicitly appears as a P16 graph edge in both diagrams; retain that explicit edge in implementation plans. No actual cycle found. P11 depends on P15, but P15 does not depend on P11; P13 then consumes both. P12 is independent of P15 and can be proved once P3–P8 are available.

## Proposed topological proof order

| Stage | Targets | Acceptance gate |
|---|---|---|
| A | P0 | Exact pinned package/manifest identity, cross-table coherence, canonical indexed codecs, root identity, and reload law. |
| B | P1, then P2 | Builder soundness/completeness for declared schema language; canonical graph round-trip/resolution to exact typed works, indices, wires, and proofs. |
| C | P3 | Deterministic guarded replay from empty state; event/journal codec laws; `StateWF` preservation; malformed-prefix rejection; terminal absorption. No provenance claim from decode alone. |
| D, parallel | P4; P6; P7; P10 | P4 proves generator output/plan exact at every legal input/allocation and global typed-DAG splice. P6 proves exact local result at reconstructed input. P7 proves exact keyed receipt/validator/effect retry contract. P10 proves exact loaded bytes equal canonical encoding of latest committed prefix at every fenced load; monotonicity; no old append after load. |
| E | P5, P8 | P5 combines P2/P4/P10 to reuse exact committed graph and plan. P8 proves charge/fuel equations and once-only settlement from replay plus P7 receipts. P9 may be discharged here as optional store-specific extension. |
| F | P15 | Define inductive `ControllerStep_R` safety for every finite schedule: unique live claims, exact claim bindings, sparse `ReadyInputAgreement`, fresh-head reauthorization, serial authorized commits, committed-only visibility, ledger invariants, crash clearing, and P10 cuts. |
| G, parallel | P11; P12; P16 | P11 proves enabled frontier for every started nonterminal state, with pending intents resumable. P12 proves each successful post-start append strictly decreases `(G,U,W)`. P16 composes P10 prefix selection with P15 authorization witnesses and P1–P8 semantics at every cut. |
| H | P13 | Prove chosen concrete runtime’s representation relation and forward simulation to P15, including actual journaler/load/fence, worker epoch fencing, adapter, extraction, and identity/codec refinement; include P9 only for backing-object claims. |
| I | P14 | Add named weak-fairness/service progress premises, finite crashes/fuel, total local/generator/validator code, and conclude typed root output. |

Stage D may be scheduled once P3 is proved; P10 does not need P4–P8. P15 consumes P4–P8/P10, so P5/P8 must finish before P15 per the normative dependency table. P16 can proceed after P15 and those semantic lemmas. P13 and P16 are separate consumers of abstract contracts: P13 establishes concrete-to-abstract simulation; P16 establishes abstract semantic recovery. Concrete end-to-end recovered correctness needs both.

## Required semantic obligations

- **Generated graph typing:** P1/P2 establish universal direct-edge compatibility over every legal port environment, not sampled execution values. P4 quantifies generator admission over every legal exact input, pinned run metric, and allocation; commits exact canonical descriptor and local plan; proves boundary-index substitution, acyclicity, global occurrence uniqueness, and children hidden until commit. `ReadyInputAgreement` must connect sparse committed-reference reconstruction to the complete typed evaluator. External outputs range over every inhabitant of declared output family, including every validator-accepted value ([implementation spec, lines 1963–1983, 2266–2299](../../schema_era_2026-10-14/implementation_spec.md#L1963); [theorem guide, lines 181–230](../../schema_era_2026-10-14/key_correctness_theorems.md#L181)).
- **Every-cut recovery:** P10 makes loaded physical bytes the source of truth; decode must yield exactly latest committed prefix and re-encode byte-identically. Commit-before-ack, atomic prefix, monotone durability, and post-exit load barrier settle/fence old requests before load. P15 carries authorized append history through arbitrary schedules/cuts; P16 takes exactly that history prefix and transports `SemWF`, typing, and provenance without rerunning work ([implementation spec, lines 2301–2376, 2122–2172, 2547–2618](../../schema_era_2026-10-14/implementation_spec.md#L2301)).

## P10 / P15 / P16 / P13 boundary

- **P10:** storage/codec theorem only. Exact byte/prefix/replay relation; says nothing about why event payloads are correct.
- **P15:** abstract controller theorem. Authorizes events under every modeled interleaving and preserves provenance as ghost history; assumes P10 store-cut law. No concrete disk claim.
- **P16:** semantic composition. Chooses P10’s prefix from P15’s authorized history; establishes recovered graph typing, exact local/external/generator provenance, pending-intent binding, and trace-indexed no-post-commit execution. Replay-state absence from frontier is separate state corollary.
- **P13:** concrete forward simulation. Current representation binds current store bytes, append history, abstract prefix, volatile state, pinned bundle, and adapter trace; recovery clause binds fenced load bytes to exact prefix and restarts with fresh empty volatile epoch ([implementation spec, lines 2686–2859](../../schema_era_2026-10-14/implementation_spec.md#L2686)). P13 neither replaces P15 nor proves P16; it transfers their guarantees to selected implementation, subject to explicit host/service premises.

No circularity: P10 is abstract service law; P15 proves abstract executor safety assuming it; P13 proves concrete journaler/runtime refines those laws and P15; P16 composes abstract P10+P15. Do not define P10 as a theorem about the chosen concrete storage and also use P13 to prove that same premise.

## Acceptance checklist

- [ ] P0–P3 contracts become checked lemmas; all identities/codecs resolve to same exact pinned packages after reload.
- [ ] P1/P2 prove universal graph typing and canonical resolution; no runtime sample repairs an invalid edge.
- [ ] P4 proves all-input/allocation generator admission, exact graph/plan provenance, child commit-before-use, typed splice, and occurrence freshness.
- [ ] P5 recovers exact committed graph bytes/plan; P6 reuses committed local outputs; P7 retries only same keyed operation and receipt law; P8 conserves and settles ledgers once.
- [ ] Optional P9 included only for persistent resource identity; prove publish-before-reference, immutable version, exact typed projection, and same-object restart resolution.
- [ ] P10 covers every crash/load cut, exact canonical bytes, atomic prefix, monotone commit durability, settled/fenced prior appends, no late commit after load, and `recover = replay(prefix)`.
- [ ] P15 is induction over explicit controller steps/all finite schedules; stale permits are rebuilt, results hidden until append, crashes clear volatile state, pending intents retain exact key/binding.
- [ ] P11 covers every started nonterminal replay state; P12 rank decreases on every successful post-start append; rejected stale attempts are not transitions.
- [ ] P16 proves `SemWF` and all graph/result provenance at every loaded prefix; trace property forbids post-commit redispatch; pending retry is cut-scoped and P7-safe.
- [ ] P13 proves each concrete transition simulates one authorized abstract step or stutters; concrete load/append/flush/fence, epoch, adapter, extraction, manifest and codec laws are evidence-backed, not asserted by interface name.
- [ ] P14 states fairness and remote/store progress as premises; no safety proof is mislabeled liveness.
- [ ] No relied-upon `assume`/`admit` discharges system theorem; proof build and theorem reports identify unresolved host assumptions. Current evidence ledger says this gate is not yet met.

## Strongest objection

The plan is dependency-coherent but not yet proof evidence. The abstract P10 law is strong and close to its conclusion; if instantiated without an independent journaler model/proof, P13 can become circular or merely restate the desired durability guarantee. Require an explicit abstract/concrete boundary and evidence for atomic commit, durability, exact loaded bytes, and old-request fencing. Also require P15’s exact transition relation to be the one P13 simulates; prose resemblance alone cannot transfer P16.

## Evidence locations

- Normative P0–P16 dependency graph/table: [implementation_spec.md, lines 2635–2684](../../schema_era_2026-10-14/implementation_spec.md#L2635).
- P13 representation relation and simulation: [implementation_spec.md, lines 2686–2859](../../schema_era_2026-10-14/implementation_spec.md#L2686).
- Abstract controller, interleaving invariant, and P10 cut law: [implementation_spec.md, lines 1985–2189](../../schema_era_2026-10-14/implementation_spec.md#L1985).
- P10 bytes/cuts: [implementation_spec.md, lines 2301–2376](../../schema_era_2026-10-14/implementation_spec.md#L2301).
- P16 composite theorem: [implementation_spec.md, lines 2547–2618](../../schema_era_2026-10-14/implementation_spec.md#L2547).
- Independent theorem spine and P0–P16 descriptions: [key_correctness_theorems.md, lines 100–177](../../schema_era_2026-10-14/key_correctness_theorems.md#L100); combined typed graph/recovery statement lines 181–250.
- Current source-proof status: [S2-00 evidence ledger, lines 20–44](S2-00-evidence-ledger.md).
