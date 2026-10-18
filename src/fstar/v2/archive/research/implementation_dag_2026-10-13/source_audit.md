# Source audit for implementation DAG

## Verdict and scope

Current source is useful substrate and examples, not implementation of abstract system. Controller, concurrency, replay, durable store, and recovery model are absent. Several graph claims are visibly admitted. Packet is a suitable target map; new DAG should create contracts and proofs in its dependency order, not treat current `verify` target as P0–P16 evidence. This audit inspected source only; no F* build or test was run.

“Partial” below means source has relevant definitions or example proof, not that normative theorem is established. Direct observations are cited; P mapping is audit inference against spec theorem table at `implementation_spec.md:2666-2684` and packet acceptance list at `implementation_packet.md:371-430`.

## Existing module and build map

| Current source | Directly observed content | Normative gap |
|---|---|---|
| [`WorkflowV2.Kernel.fst`](../../current_implementation/src/WorkflowV2.Kernel.fst) | Durable identities/refs, first-order wire and graph syntax, codecs and laws, code/op/generator refs, allocations, Work variants (`:7-186`). | No manifest/schema calculus, controller, or run-wide charge metric. `run_budget` has only fuel and charge (`:162-165`); generator takes input and allocation, not metric (`:172-174`). Spec requires metric (`implementation_spec.md:544-548,642-660`). |
| [`WorkflowV2.Identity.fst`](../../current_implementation/src/WorkflowV2.Identity.fst) | Identity equality, typed-to-durable refs, packed work/codec registries, uniqueness and exact resolution (`:6-282`). Bundle has registry identity plus work/codec tables (`:284-292`). | No canonical manifest projection, schema/type links, root-entry linkage, op/generator/graph-codec tables, or stable reload proof. Bundle comment itself leaves identity/content coherence open (`:284-292`). |
| [`WorkflowV2.Graph.fst`](../../current_implementation/src/WorkflowV2.Graph.fst) | Finite DAG interpretation, port telescope, dependent wires, typed node sequence/witness, graph WF and graph-local allocation checks (`:150-904`). | No finite schema AST universal resolver. Builder theorem spine includes `admit()` at start/add/finish/completeness (`:908-956`). Generator admission takes no metric (`:881-904`). |
| [`WorkflowV2.GraphCodec.fst`](../../current_implementation/src/WorkflowV2.GraphCodec.fst) | First-order graph syntax encode/decode and syntax roundtrip/canonicality proofs (`:11-486,635-...`). | Syntax laws do not reconstruct the typed graph witness through one pinned resolver; no event/journal codec. |
| [`WorkflowV2.Journal.fst`](../../current_implementation/src/WorkflowV2.Journal.fst) | Run/occurrence/allocation/artifact payload data and five event constructors (`:7-93`); a small action enum and journal wrapper (`:95-113`). | Comments explicitly defer replay and grant no transition authority (`:101-108`). No apply/replay, StateWF, provenance, authorization, codec, serial append, or crash model. |
| [`WorkflowV2.GenerationExample.fst`](../../current_implementation/src/WorkflowV2.GenerationExample.fst) | Nat codecs, increment local work, chain descriptor/plan generator, registries, and chain membership (`:12-205`). | One fixed chain example only. Generator call omits charge metric (`:146-155`); does not establish universal P4. |
| [`WorkflowV2.ChainProof.fst`](../../current_implementation/src/WorkflowV2.ChainProof.fst) | Builds typed witnesses and proves properties for generated chain (`:13-115,117+`). | Example-specific; cannot replace arbitrary graph builder/resolver or generator-commit proofs. |

`Makefile:1-13` lists only those seven `.fst` files under one `verify` target. No `.fsti`, planned module layering, milestone targets, or P0–P16 theorem target. No build was run, so this report makes no claim about current verification success.

### AST meaning

“AST” means the restricted, first-order **schema language AST** in `implementation_spec.md:815-842`, with pinned denotations and a declared equality calculus (`:899-919`). It is not F* compiler AST, quotation/reflection, arbitrary `Type0` equality, or an unchecked SMT query. Resolver must reject unknown equalities. Graph descriptor AST is separate first-order runtime syntax (`:527-539`); it stores durable refs, not closures.

## P0–P16 source coverage

| Target | Status | Existing evidence and decisive missing work |
|---|---|---|
| P0 identity/package | Partial | `Identity.fst:6-292` has identity comparisons, unique registry entries, exact lookup. Missing canonical manifest as exact package projection, cross-table/schema/coherence/root links, metric and reload theorem (`implementation_spec.md:2668`). |
| P1 graph typing | Partial | `Graph.fst:150-797` has typed telescopes, graph witness, DAG/WF definitions. Restricted schema resolver and universal legal-environment checker absent; builder proof spine admitted (`:908-956`). |
| P2 graph decode/resolve | Partial | `GraphCodec.fst` gives syntax codec laws; `Graph.fst` interprets syntax. Missing composition to exact dependent witness with same pinned resolver for root and generated descriptors (`implementation_spec.md:2670`). |
| P3 replay | Absent | `Journal.fst:82-113` declares events and journal only; explicitly defers replay. |
| P4 generator commit | Partial | Allocation predicates and generator admission in `Graph.fst:799-904`; example generator in `GenerationExample.fst:146-155`. Missing metric argument, committed authorization, append gating, typed splice/global DAG preservation. |
| P5 graph recovery | Absent | No exact committed graph/plan decode, path lifting, or recovery reuse. |
| P6 local provenance | Partial substrate | `Kernel.fst:110-115` has total `CodeRef.run` and indexed codecs. No authorized completion origin, exact reconstructed-input provenance, or no-rerun-after-commit theorem. |
| P7 adapter safety | Partial substrate | `Kernel.fst:117-124` has validator and maximum charge only. No keyed idempotent effect/receipt contract, intent binding, retry/restart law, or multi-inflight adapter proof. |
| P8 ledgers | Partial | `Graph.fst:799-875` checks graph-local allocations, fuel and charge pools. No replay-derived global ledgers, reservations, settlement, run metric, or interleaving conservation. |
| P9 artifacts | Partial syntax | `Journal.fst:39-45,63-67,74-79` carries artifact refs. No typed inventory, publish-before-commit, immutable backing or restart identity laws. Conditional theorem absent. |
| P10 durable store | Absent | No append/load/cut/barrier or exact-prefix/fencing model. |
| P11 enabled frontier | Absent | `Journal.action` is vocabulary only; no controller state or frontier theorem. |
| P12 progress rank | Absent | No rank or append-decrease proof. |
| P13 concrete refinement | Absent | No concrete representation, runtime-step projection, host/remote premises, or restart simulation. |
| P14 termination | Absent | No fairness/progress assumptions or conditional completion theorem. |
| P15 abstract safety | Absent | No controller step relation, attempt/epoch state, worker pool, keyed in-flight calls, serial append slot, or all-schedule induction. |
| P16 recovered semantics | Absent | No crash-cut recovery theorem composing graph typing, provenance, reuse and pending-call recovery. |

## Largest deltas

1. **No operational semantics.** Current journal has event syntax, not state transitions. Packet requires pure replay, `StateWF`, append provenance, controller transitions, and crash handling (`implementation_packet.md:248-265,308-340`). P15 requires unique claims, ready-input binding, reauthorization at current head, serial append, arbitrary completion order, commit-only visibility, and no redispatch after commit (`implementation_spec.md:2683`). None appear in current modules.
2. **No resolver connecting durable bytes to dependent types.** Graph code has a typed builder/witness, but no finite schema AST and manifest-linked proof-producing resolver. This is strongest foundational blocker; P1/P2 cannot be inferred from syntax roundtrip or example construction (`implementation_spec.md:899-919,2669-2670`; packet `:242-247`).
3. **Graph proof spine contains `admit()`.** Direct proof gap, not merely missing implementation plan (`Graph.fst:908-956`). New DAG must replace it before claiming P1.
4. **Generator API mismatch.** Source lacks `ChargeMetricIdentity` in `run_budget` and `generate_graph`; spec and packet require metric to parameterize charging (`implementation_spec.md:544-548,642-660`; packet `:82,125`). Resolve at Kernel contract milestone, before generator or ledger proofs.
5. **Build organization is not milestone-ready.** Makefile submits all existing source files in one invocation but has no module/interface boundary or milestone decomposition. Packet says current source is starting evidence and permits split/replacement (`implementation_packet.md:289-304`).

## Proposed dependency-ordered DAG milestones

Each milestone should produce named contracts and checked theorems, then unlock successors. Split independent branches only after shared foundations are frozen. This follows packet proof order (`implementation_packet.md:342-369`) and module DAG (`:236-287`).

1. **M0 — Baseline/source inventory.** Record compiler/version and current verifier behavior in a separate implementation task; decide `.fsti` policy and Makefile per-module dependency checks. Do not count this as a theorem. No execution was done in this audit.
2. **M1 — Kernel contracts and identity primitives (P0 foundation).** Preserve useful identities/codecs/Work types; add exact charge metric to budget and generator signature; isolate first-order graph and journal value types. Define signature invariants without cycles.
3. **M2 — ManifestCore + restricted Schema AST.** Define canonical manifest entries, supported type/value grammar, binder/index representation, normal forms/equality derivations, denotation links. Prove termination, soundness, completeness for declared fragment; unknown rejects. This is app schema AST, never F* compiler AST.
4. **M3 — Bundle, GraphResolve, GeneratorAdmission (P0, P1).** Prove identity selects exactly one complete package, manifest projection/coherence and reload stability. Build proof-producing graph resolver; prove builder soundness/completeness for all supported legal port environments. Keep GeneratorAdmission below GraphBuilder as packet requires.
5. **M4 — GraphCodec + GraphInterpretation (P2).** Preserve syntax encoding laws; compose decode with the same pinned resolver for root/generated graphs. Prove canonical syntax roundtrip plus exact dependent witness recovery.
6. **M5 — Journal and JournalCodec (P3).** Define five event transitions, guarded `apply`, deterministic replay, `StateWF`, canonical event/journal bytes, malformed-prefix rejection, terminal absorption. Keep semantic append-history provenance separate from replay WF.
7. **M6 — Independent post-replay branches (P4, P6, P7, P10).** P4: exact generator result/plan, allocation lifting, typed splice, event authorization and child visibility only after append. P6: exact local input/output origin and absorbed committed occurrence. P7: immutable keyed binding/receipt under overlap/retry/restart, distinct keys out of order. P10: serial compare-and-append, atomic cuts, exact latest-prefix load and old-request fencing. P4 must not import P10 theorem; consume successful append token only.
8. **M7 — Recovery/resources/ledgers (P5, P8, optional P9).** P5 reuses exact committed graph bytes and lifted plan. P8 proves allocation/reservation/spend/fuel equations per transition using one run metric. P9 separately proves durable publish and same logical object/version across supported restart; omit only if system makes no persistent backing identity claim.
9. **M8 — ControllerModel + ControllerSafety (P15).** Define single-coordinator transition system with volatile claims/attempt epochs, bounded independent workers, keyed adapter in-flight state, serial append slot, stale-head reauthorization, commit-gated visibility, crash/restart fencing. Induct over all permitted schedules and interleavings, including arbitrary completion order and no-rerun-after-commit.
10. **M9 — Progress/recovery compositions (P11, P12, P16).** Prove nonterminal frontier/same-key resume, strict well-founded rank decrease on each successful post-start append, then every-cut semantic recovery and provenance composition. Keep P5 separate from P16 as packet specifies.
11. **M10 — Concrete refinement then termination (P13, P14).** Choose implementation and name host/remote premises. Map every concrete step and recovery load to abstract transitions; show one active coordinator, exact bytes/prefix, epoch and append fencing, stable identities. Only then prove conditional termination from explicit fairness/service-progress/finite-crash/fuel premises.
12. **M11 — Proof-bearing examples.** Retain chain as regression-shaped theorem example; add arbitrary joins/fanout, generated nested graph, dependent family, concurrent independent local/generator nodes, multi-key out-of-order adapter scenario. Examples validate expressibility, never replace generic P0–P16.

## Assumptions and unresolved obligations

- Treat packet as module/order plan and spec as normative semantics; packet itself says it proves no P0–P16 theorem (`implementation_packet.md:3-6`).
- Existing source proofs are historical source evidence only. This audit did not run F*, so no claim about current buildability or actual proof checking.
- Exact AST calculus, schemas, canonical manifest encoding, and representation are open implementation choices, but their soundness/completeness and identity links are obligations (`implementation_spec.md:899-919`; packet `:268-287`).
- P10 and P13 require concrete physical journaler/host facts, including serial atomic append, exact cut load, and old-request settlement/fencing. Those are named premises/contracts, not consequences of pure replay (`implementation_spec.md:2678,2681`; packet `:335-340`).
- P7 requires adapter’s effect-safety/receipt law; pure controller logic cannot establish external exactly-once effects by itself (`implementation_spec.md:371-456,2675`).
- P9 remains conditional on persistent resource identity claims (`implementation_spec.md:2677`).

## Strongest objection

P1/P2 lack their central sound, complete durable-to-dependent-type resolver, while `Graph.fst` still admits builder theorems. Building controller and recovery proofs atop current graph layer would risk proving safety over an incomplete or unsound graph interpretation. Implement M2–M4 first; packet order already does this.

## Next investigation

Before implementation DAG execution, inspect installed F* version and current module-check behavior in a separately authorized build task; use it to set interface/module compilation policy and estimate whether schema AST proofs need smaller modules. No such execution belongs to this read-only audit.
