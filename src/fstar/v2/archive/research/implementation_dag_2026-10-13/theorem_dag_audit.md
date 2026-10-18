# V2 theorem DAG audit — independent derivation

**Verdict: PASS, with explicit conditional boundaries.** Normative target dependencies form acyclic graph. A proof order exists. P10 is abstract journaler law; P15 abstract executor; P16 abstract semantic recovery; P13 later concrete refinement. P9 enters only when persistent resource identity is promised. No P0–P16 theorem is claimed discharged by current source/spec ([implementation spec, lines 1–6](../../schema_era_2026-10-14/implementation_spec.md#L1)).

## Normative dependency map and owners

Dependencies below come from `implementation_spec.md` §6 and theorem guide §“The theorem spine”; owners are proof-module proposals, not current proved source owners ([spec, lines 2635–2684](../../schema_era_2026-10-14/implementation_spec.md#L2635); [guide, lines 100–177](../../schema_era_2026-10-14/key_correctness_theorems.md#L100)).

| Target | Prerequisites | Proposed proof owner | Acceptance artifact |
|---|---|---|---|
| **P0** `pinned_identity_and_codec_resolution` | Proof-bearing registry/codec contracts | `ManifestCore` + `Bundle` (+ `Kernel`) | Theorem: canonical manifest is exact projection of coherent complete packages; identities resolve uniquely; root, schema, codec, work, operation, generator, metric, and reload correspondence hold. |
| **P1** `typed_graph_builder_sound_complete` | P0 | `Schema` + `GraphResolve` + `GraphBuilder` | Soundness and completeness exactly for `SchemaSupported`; derivations establish every node carrier and universal direct-edge equality over every legal environment. |
| **P2** `graph_codec_and_resolution_roundtrip` | P0, P1 | `GraphCodec` + `GraphInterpretation` | Canonical graph syntax round-trip plus proof-producing resolution preserves exact signatures, indices, constants, ports, topology, and derived typing for root and generated graphs. |
| **P3** `replay_wf_canonical_terminal_absorbing` | P0, P2, fixed `JournalCodec` laws | `Journal` | Deterministic guarded `apply`/`replay`; empty base; `StateWF` preservation; canonical event/journal bytes; malformed-prefix rejection; terminal absorption. No origin proof inferred from replay. |
| **P4** `graph_commit_before_use_and_global_dag_preservation` | P1–P3 | `GraphCommitProof` + `Generation` | For every exact input, metric, and allocation: generator result is schema-supported; event bytes/plan equal exact result; child plan lifts exactly; splice preserves boundary type, global DAG and occurrence uniqueness; children hidden until commit. |
| **P5** `graph_recovery_exact` | P2, P4, P10 | `GraphRecovery` | Every prefix containing `GraphCommitted` resolves same committed descriptor/path/plan; no generator rerun or replacement topology. |
| **P6** `local_completion_sound_and_absorbing` | P0, P3 (P2 explicit in guide; follows through P3) | `LocalProvenanceProof` | At exact reconstructed input, completion decodes canonically and equals pinned `CodeRef.run`; committed occurrence leaves frontier; precommit pure work may repeat. |
| **P7** `adapter_intent_effect_safety_and_progress` | P0, P3 (P2 explicit in guide; follows through P3) | `AdapterProvenanceProof` + adapter service contract | Intent fixes exact key/request/resume binding; retries/overlaps/restarts reconcile one immutable receipt/effect; validator/result/evidence/charge/artifacts bind exact input; liveness remains conditional. |
| **P8** `charge_and_fuel_ledgers_safe` | P3, P4, P7 | `BudgetProof` | Every replay/event/schedule preserves aggregate charge/fuel equations, plan projections, and one-time reservation/settlement. |
| **P9** `artifact_publication_safe` | P0–P3 + artifact-store contract | Optional `Artifacts` branch | If claimed: typed reference projection, durable publication before event commit, immutable logical version, same-object post-restart resolution; replay performs no store I/O. Otherwise refs remain typed opaque values. |
| **P10** `canonicity_and_every_cut_durability` | P0–P3 + journaler contract | `Durability` | At every post-exit load barrier, exact physical bytes decode to latest committed prefix and re-encode identically; prefixes monotone; old appends settled/fenced and cannot commit after load; recovery equals replay. |
| **P11** `frontier_total_and_no_stuck` | P1–P8, P15 | `Progress` | Every started reachable nonterminal replay state has enabled legal action or same-key resumable intent; empty pre-start state is bootstrap. No liveness without separate premises. |
| **P12** `no_infinite_progress_cycle` | P3–P8 | `Progress` | Every successful post-start append lowers well-founded `(G,U,W)`; stale/no-op attempts do not count. P12 does not depend on P15. |
| **P13** `concrete_runtime_refines_abstract_system` | P0–P8, P10–P12, P15; P9 only if backing identity claimed | `Refinement` | Chosen concrete runtime forward-simulates P15/P10; concrete storage/load/fence, controller, workers, adapter, extraction, identities/codecs have evidence-backed refinements. Host/remote laws stay explicit premises if not provable. |
| **P14** `conditional_termination` | P11–P13 + named fairness/service premises | `Termination` | From committed valid `RunStarted`, assumptions on weak fairness, total callbacks, adapter/store progress, finite fuel/crashes imply typed root output. |
| **P15** `executor_interleaving_preserves` | P0–P8, P10; P9 only for resource extension | `ControllerSafety` | Induction over explicit abstract controller steps/all finite schedules and cuts: unique live claims, exact inputs/allocations, stale reauthorization, authorized serial commits, commit-only visibility, `SemWF`, ledgers, no postcommit redispatch. |
| **P16** `recovered_semantic_graph_correctness` | P0–P8, P10, P15 (P5 explicit in guide and included in P0–P8); P9 only for backing identity | `Recovery` | For every authorized trace/cut: exact prefix/replay and `SemWF`; globally typed root/generated DAG; exact local/external/generator provenance; committed work reused; pending intent retries exact-bound; trace no-postcommit execution. |

`P6`/`P7` guide adds P2 edge; normative table lists P0/P3. Since P3 depends on P0/P2, transitive closure matches. P16 explicitly depends on P5 in guide/diagram; normative table’s P0–P8 range includes P5. Keep P5 named in implementation checklist so this shorthand cannot hide exact-topology recovery.

## Independently derived staged DAG

1. **Package boundary:** P0. Review gate: exact registry/manifest/codec linkage and restart stability accepted before proof uses durable identity.
2. **Restricted graph language:** P1, then P2. Review gate: all graph equations proved in declared schema calculus; canonical syntax resolves through one pinned resolver.
3. **Journal semantics:** P3. Review gate: event syntax/canonical codecs and pure transition/replay laws; reject malformed prefixes; do not conflate `StateWF` with semantic origin.
4. **Independent semantic and storage lemmas (parallel after P3):** P4, P6, P7, P10; optional P9. Review gates: generator admission/splice; local result; adapter receipt/effect; physical-byte/cut law; optional artifact publication and identity.
5. **Compositions:** P5 and P8. P5 composes P2/P4/P10. P8 composes replay allocations, P4 plans, and P7 receipt truth. P9 stays separate/conditional.
6. **Abstract schedule theorem:** P15 after P0–P8 and P10. Review gate: all-step induction over finite schedules/cuts, including stale heads, reversed completions, commit/ack cut, pending intent, and restart fencing.
7. **Abstract recovery and progress:** P11 after P15; P12 after P3–P8 (may precede P15); P16 after P0–P8/P10/P15. Review gate: exact-prefix semantic transfer and universal graph/provenance properties.
8. **Concrete transfer:** P13 after P0–P8/P10–P12/P15, then P14 after P11–P13 and liveness premises. Review gate: selected host implementation simulates abstract services; concrete termination only with named fairness/progress assumptions.

Topological witness: `P0; P1; P2; P3; (P4,P6,P7,P10,[P9]); (P5,P8); P15; (P11,P12,P16); P13; P14`. Parentheses mean parallelizable after listed inputs; P12 may move before P15. No cycle: P10 feeds abstract P15, P15 feeds P11/P13/P16, P11/P12 feed P13, P13 feeds P14. P13 is not a premise of P15 or P16.

## Journal, replay, generated graph, and cut obligations

- **One durable authority:** journal `J` is sole durable workflow state; logical state is `replay_C(J)`. Any cache must equal that projection ([spec, lines 1487–1497](../../schema_era_2026-10-14/implementation_spec.md#L1487)).
- **Canonical replay:** codec proves event and journal round-trip plus accepted-byte uniqueness; framing has no ambiguity/trailing data. Replay is deterministic guarded fold; structural `StateWF` says nothing about value provenance ([spec, lines 1541–1556, 1721–1740](../../schema_era_2026-10-14/implementation_spec.md#L1541)).
- **Schema AST scope:** AST is manifest-pinned, first-order schema syntax with finite derivations and denotation model, not F* compiler AST. It supports only declared `SchemaSupported` equations, no arbitrary `Type0` equality, casts, unchecked SMT success, or sampled-result repair ([spec, lines 242–252, 805–842, 899–919](../../schema_era_2026-10-14/implementation_spec.md#L242)).
- **Universal edge rule:** every direct producer/consumer edge is equal at exact dependent indices for every legal `LegalEnv`; environment includes every value of full external output family, hence all validator-accepted results. P4 proves generated graph valid for every legal generator input/allocation, then proves typed substitution/global DAG preservation. No child action before `GraphCommitted` ([spec, lines 854–890, 921–930, 1742–1746](../../schema_era_2026-10-14/implementation_spec.md#L854); [guide, lines 181–230](../../schema_era_2026-10-14/key_correctness_theorems.md#L181)).
- **P10 cut semantics:** append commit point determines visibility; load gets exact complete prefix bytes; acknowledged append committed; after exit old requests settle/fence before recovery load and cannot append after. P10’s store contract is abstract law; concrete flush/atomicity/fencing proof belongs to P13. P10 alone never establishes event authorization ([spec, lines 2301–2376](../../schema_era_2026-10-14/implementation_spec.md#L2301)).
- **P15/P16 split:** P15 proves event authorization at current replay head across every interleaving and carries append witnesses in `SemWF`. P16 selects P10’s prefix from same history and derives graph/result/no-repeat claims. Replay does not rerun local/generator work or establish adapter effect origin ([spec, lines 1985–2189, 2547–2618](../../schema_era_2026-10-14/implementation_spec.md#L1985); [guide, lines 232–250](../../schema_era_2026-10-14/key_correctness_theorems.md#L232)).

## Packet reconciliation

Only after deriving above order, compared `implementation_packet.md` §3/§5. Its phases A–I match normative topological witness; no dependency correction needed ([packet, lines 237–265, 342–366](../../schema_era_2026-10-14/implementation_packet.md#L237)). Packet refines owner boundaries usefully: separates schema/graph resolution, GraphCommitProof, LocalProvenanceProof, AdapterProvenanceProof, GraphRecovery, ControllerSafety, and Refinement. P5 remains independent of P15; P16 consumes P15. Packet explicitly says P12 does not depend on P15. These are source-module decompositions, not new theorem edges.

AST treatment aligns: spec’s first-order manifest schema AST and mathematical denotation are the proof boundary; packet places schema derivations in `WorkflowV2.Schema`, not F* compiler AST. No contrary normative claim found. Packet’s `P4,P6,P7,P10` parallel phase is valid because each has P0–P3 prerequisites; P5/P8 are downstream compositions. Packet’s P9 conditionality, P11/P12/P13/P14/P15/P16 prerequisites, and no-cycle statement agree with §6 and theorem guide ([packet, lines 349–406](../../schema_era_2026-10-14/implementation_packet.md#L349); [spec, lines 2666–2684](../../schema_era_2026-10-14/implementation_spec.md#L2666); [guide, lines 100–177](../../schema_era_2026-10-14/key_correctness_theorems.md#L100)).

## Review gates and acceptance rules

- **Contract gate:** every registry, codec, executor, adapter, journaler, and optional artifact-store law is carried by a constructed proof-bearing record; no `assume`/`admit` discharges system goal.
- **Graph gate:** P1/P2 soundness/completeness proven for exactly restricted AST language; P4 generator theorem quantified over arbitrary admitted inputs/allocations; all root/generated graphs use same resolver.
- **Journal gate:** P3 and P10 separately reviewed. P3 is codec/replay/WF; P10 is storage prefix/byte/barrier. Require malformed/torn/trailing bytes, commit-before-ack, stale CAS, in-flight exit, old append after load, monotonic cuts.
- **Authorization gate:** P6/P7/P15 hold exact input/index/key and current-head authorization; reordered independent results cannot commit stale proof; only commit exposes value/graph/outcome.
- **Recovery gate:** P5 exact descriptor/plan; P16 all-cut `SemWF`/typed graph/value provenance and trace no-postcommit property. Include P9 claims only with P9 proof.
- **Host gate:** P13 forward simulation uses actual selected append/load/flush/fence, callback epoch, identity-loader, extracted-code, adapter, codec and (if claimed) resource implementations. Unavailable laws remain explicit conditional premises, never silently promoted to proved facts.
- **Liveness gate:** P14 separate from safety; record fairness, storage service, executor return, adapter reconciliation, totality, finite fuel and finite crashes.

## Assumptions, strongest objection, unresolved issues

**Assumptions:** one active commit coordinator per run (multiple coordinators require extended shared fencing/claim theorem); local/generator functions total and pure; adapter effect safety is per key/binding with explicit remote dedup/status/idempotence law; crash model preserves same available store and excludes disk loss/corruption/rollback/external mutation; P9 is omitted unless persistent backing identity is claimed ([spec, lines 18–42, 2303–2313, 1985–1991](../../schema_era_2026-10-14/implementation_spec.md#L18)).

**Strongest objection:** P10 contract is intentionally strong: an abstract theorem over a value whose laws already specify exact prefix bytes, monotonicity, and fencing does not prove a filesystem/database implements those laws. P13 must show chosen concrete storage refines those independently reviewable contracts; otherwise “P10 proved” is circular or merely contract restatement. Also, AST calculus completeness is only for declared `SchemaSupported`, not arbitrary F* types; widening that claim without a new soundness/completeness proof invalidates graph guarantees.

**Unresolved:** current turn plans proof targets; it does not establish source theorem bodies, host durability, service progress, or remote effect laws. Proof owners remain proposed modules. One next investigation: map current `.fst/.fsti` declarations/admissions to each planned owner and test whether import graph can support this exact DAG without cycles; do not start implementation until that gap map is reviewed.

## Evidence anchors

- Normative DAG and exact P0–P16 prerequisites: [implementation_spec.md, lines 2635–2684](../../schema_era_2026-10-14/implementation_spec.md#L2635).
- Abstract schema AST and universal edge calculus: [implementation_spec.md, lines 805–930](../../schema_era_2026-10-14/implementation_spec.md#L805).
- Replay/event/journal definitions: [implementation_spec.md, lines 1487–1556, 1721–1740](../../schema_era_2026-10-14/implementation_spec.md#L1487).
- Controller/P15 and cut invariant: [implementation_spec.md, lines 1985–2189](../../schema_era_2026-10-14/implementation_spec.md#L1985).
- P10 durability law: [implementation_spec.md, lines 2301–2376](../../schema_era_2026-10-14/implementation_spec.md#L2301).
- P16 composition: [implementation_spec.md, lines 2547–2618](../../schema_era_2026-10-14/implementation_spec.md#L2547).
- Independent theorem guide: [key_correctness_theorems.md, lines 100–250](../../schema_era_2026-10-14/key_correctness_theorems.md#L100).
- Packet comparison only after independent derivation: [implementation_packet.md, lines 237–265, 342–406](../../schema_era_2026-10-14/implementation_packet.md#L237).
