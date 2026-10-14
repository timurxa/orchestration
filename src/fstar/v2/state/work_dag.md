# V2 abstract-system proof DAG

**Status: planned, not executed.** This replaces the prior S2 specification-
planning DAG as the active plan. Every node below is `not_started`; this task
only creates the plan. No F* source was changed and no verifier or tests were
run.

## Objective and authority

Build the **fully proved abstract F* workflow system** specified in
[`implementation_spec.md`](../implementation_spec.md), with
[`key_correctness_theorems.md`](../key_correctness_theorems.md) as the guide
to the semantic graph and recovery burdens. Prove all abstract-system theorem
targets and the generic P13 refinement-transfer theorem. A host-specific P13
instance remains later work. The
[`implementation_packet.md`](../implementation_packet.md) proposes module
ownership and proof ordering but is subordinate to the specification.

The result is an abstract system parameterized by constructed,
proof-bearing contracts for pinned work/codecs, the serial journaler, the
possibly concurrent local/generator executor, and the multi-inflight adapter.
It proves the abstract system's safety, durability, graph typing, recovery,
and conditional liveness theorems. It does not implement SQLite/filesystem,
process/network adapters, an extracted runner, or a concrete scheduler.
Instead it defines the refinement interface and proves the generic transfer
theorem that a future implementation can instantiate with its own simulation
proofs. A later concrete implementation task must prove those instances.

The three executable work forms are total pure local `Work`, fallible and
possibly nondeterministic external `Work`, and pure runtime graph generation.
Root and generated graphs share the same supported graph language, resolver,
typed-edge theorem, journal events, and recovery. Independent ready local and
generator work may execute concurrently; distinct adapter calls may be
in-flight together; journal append remains serial under one run coordinator.
Committed local results and graph descriptions are reused after recovery.

**Proof rule:** every applicable P0–P16 result must be a checked F* theorem
from definitions and explicit contract records whose laws are themselves
proof fields. No theorem path may use `assume`, `admit`, a sampled execution,
or a test as a proof. Conditional host/remote laws remain explicit premises.
Examples are proof-bearing constructions and do not replace the generic
theorems.

**Schema AST clarification:** this is the workflow's own restricted,
manifest-pinned schema-expression AST, with an F* datatype encoding,
denotation, and proved equality/checking calculus. It is not the F* compiler
AST, quotation, arbitrary `Type0` reflection, or an unchecked SMT callback.
P1/P2 completeness is exactly for `SchemaSupported`. A direct edge is
accepted only when its producer/consumer types agree in every legal graph
environment from static declarations. Thus unconstrained `vector n` cannot
feed `vector 3` merely because one run produced length 3.

## DAG operating rules

1. This table is the sole execution authority. An edge `A -> B` means B
   cannot start until A is complete. Mermaid is a high-level view; every edge
   in the detailed table binds even when omitted from that diagram.
2. The first future node is a read-only inventory of existing v2 source and
   the precise refactor map. Existing declarations/examples are not credited
   as P0–P16 proofs without checking their theorem path.
3. A theorem node completes only when its F* declaration/proof is in the
   source, its full transitive proof path has no forbidden escape hatch, the
   project full-check command passes, and evidence is recorded in
   `node_summaries.md`. Proof-interface stubs do not count as completion.
4. Contract nodes define explicit records and law fields. The abstract
   theorems must be proved generically from those fields; a contract is not a
   hidden axiom. Concrete instances of journaler, adapter, executor, compiler,
   extraction, or artifact store are outside this DAG.
5. Safety never assumes fairness. P10 (journaler prefix law) is distinct from
   P15 (abstract authorization across schedules); `StateWF` is distinct from
   semantic-origin `SemWF`; P16 explicitly consumes P5 exact graph recovery.
6. Human review nodes stop the graph until explicit user review/resume. Record
   the review outcome and any approved DAG change before starting dependents.
   If review finds the specified theorem unprovable for the selected model,
   stop at that gate with the counterexample and alternatives; do not weaken
   the theorem locally.
7. The final verifier run checks the complete module set. Do not add a test
   suite as a substitute for proof; the examples are F* proof witnesses.

## High-level proof spine

~~~mermaid
flowchart TD
  A00["A00 Source audit"] --> A01["A01 Module/API boundary"]
  A01 --> A02["A02 Kernel signatures"]
  A02 --> A03["A03 Manifest core"]
  A03 --> A04["A04 Bundle coherence: P0"]
  A04 --> H0["H0 Human review: identity/contracts"]
  H0 --> A05["A05 Schema AST/denotation"]
  A05 --> A06["A06 Equality calculus"]
  A06 --> A07["A07 Resolver/edge theorem"]
  A07 --> A15["A15 Allocation model"]
  A15 --> A16["A16 Generator admission"]
  A16 --> A08["A08 Builder completeness: P1"]
  A07 --> A08
  A02 --> A09["A09 Graph syntax codec"]
  A08 --> A10["A10 Typed decode: P2"]
  A09 --> A10
  A10 --> H1["H1 Human review: typed graphs"]
  H1 --> A11["A11 Journal transition model"]
  A11 --> A12["A12 Event/journal codecs"]
  A12 --> A13["A13 Replay/WF: P3"]
  A13 --> H2["H2 Human review: journal/replay"]
  H2 --> A14["A14 Semantic witnesses"]
  H2 --> A20["A20 Adapter keyed contract"]
  H2 --> A23["A23 Optional resource identity: P9"]
  H2 --> A24["A24 Serial journaler contract"]
  A16 --> A17["A17 Typed splice"]
  A17 --> A18["A18 Authorized graph commit: P4"]
  A14 --> A18
  A13 --> A19["A19 Local provenance: P6"]
  A14 --> A19
  A20 --> A21["A21 Adapter theorem: P7"]
  A18 --> A22["A22 Ledgers: P8"]
  A21 --> A22
  A24 --> A25["A25 Every-cut durability: P10"]
  A18 --> A26["A26 Exact generated recovery: P5"]
  A25 --> A26
  A18 --> H3["H3 Human review: graph commits/cuts"]
  A19 --> H3
  A21 --> H3
  A22 --> H3
  A23 --> H3
  A25 --> H3
  A26 --> H3
  H3 --> A27["A27 Abstract services/controller"]
  A19 --> A27
  A21 --> A27
  A22 --> A27
  A27 --> A28["A28 Ready input/claim lemmas"]
  A28 --> A29["A29 All-schedule safety: P15"]
  A29 --> H4["H4 Human review: concurrency"]
  H4 --> A30["A30 Frontier: P11"]
  A22 --> A31["A31 Rank: P12"]
  A19 --> A31
  A26 --> A30
  A26 --> A31
  H4 --> A32["A32 Recovered semantics: P16"]
  A26 --> A32
  A19 --> A32
  A21 --> A32
  A22 --> A32
  A23 -. "only if persistent resource identity claimed" .-> A29
  A23 -. "only if persistent resource identity claimed" .-> A32
  A30 --> A33["A33 Generic refinement interface: P13 schema"]
  A31 --> A33
  A29 --> A33
  A33 --> A34["A34 Conditional termination: P14"]
  A32 --> A35["A35 Proof-bearing workflows"]
  A34 --> A35
  A35 --> A36["A36 Integrated proof/trust audit"]
  A36 --> H5["H5 Human review: abstract system complete"]
~~~

The detailed table is authoritative for all inputs, including shared P0/P1/P2
prerequisites omitted from the compact diagram. Dashed P9 edges are conditional
extensions, not prerequisites for the opaque-reference base theorem.

## Detailed nodes

All rows have status `not_started`. `P` labels identify theorem targets from
the normative spec; a node may prepare definitions before its theorem is
proved.

| ID | Depends on | Planned source result and acceptance condition | Status |
|---|---|---|---|
| **A00** | — | **Read-only source/build inventory.** Map every current `WorkflowV2.*.fst`, the Makefile, existing assumptions/admissions, current verified lemmas, and missing P0–P16 obligations. Decide which declarations are reusable, split, or replaced; record module-cycle risks and exact locations. Check the configured F* tool/build instructions when execution begins. Current known starting points: seven F* modules; `Graph.fst` has admitted builder laws; `GraphCodec.fst` proves syntax roundtrip only; `Journal.fst` declares events but defers replay; chain files are examples, not generic P1/P4. | not_started |
| **A01** | A00 | **Proof/module boundary.** Define the acyclic module import graph, public `.fsti` contracts, implementation/proof module split, build order, and trust-audit convention. Preserve independent contracts close to their API. No theorem is discharged here. | not_started |
| **A02** | A01 | **Kernel signatures.** Define typed identities, plain/indexed codecs, `CodeRef`, nondeterministic `OpRef`/validator, generator signature, the three `Work` forms, first-order `Wire`/`GraphDesc`, the custom schema-expression syntax and identities, artifact-reference syntax, and run charge metric. Keep dependent/refinement guarantees at the callee in `CodeRef`'s output family where expressible (e.g. `Work nat (fun n -> Prime n)`); do not add a separate lemma field for a property already stated by that type. Remove competing signature sources; include the metric consistently in run budget and generator/operation contracts. Prove codec roundtrip/canonical laws required at this level. | not_started |
| **A03** | A02 | **ManifestCore.** Define disjoint tagged identity domains, canonical first-order manifest/schema entries and encoding, duplicate rejection, exact cross-reference closure, and the manifest projection relation from package tables. Prove encoder/identity injectivity and uniqueness lemmas needed by P0. No closures or proof terms enter bytes. | not_started |
| **A04 (P0)** | A03 | **Pinned Bundle.** Compose executable code/operation/generator/codec/schema/resolver/graph-codec/root tables with the manifest. Prove full identity uniqueness and exact package coherence, codec/schema/type agreement, root-entry constructor linkage, run metric coherence, exact projection in both directions, and same-manifest abstract reload. P0 cannot be discharged by comparing only durable refs. | not_started |
| **H0** | A04 | **Human review: identity and API contracts.** Review the public typed signatures, no-capture decision, manifest projection, codec laws, Work/Op/generator inputs, and P0 theorem/trust boundary before schema or graph proofs depend on them. Stop for explicit review. | not_started |
| **A05** | H0 | **Restricted schema syntax and semantics.** Encode the manifest-pinned schema AST as ordinary F* datatypes. Define binders/indices, substitutions, `LegalEnv`, denotation into F* types/predicates, schema membership, and static graph-context constraints. Precisely distinguish this custom AST from F* compiler AST. | not_started |
| **A06** | A05 | **Equality calculus.** Define total normalization or derivation checking for exactly the manifest-declared schema equations. Prove termination, denotational soundness, and completeness for the declared `SchemaSupported` equality relation. Unknown or undecidable equalities reject; no unchecked solver-success constructor, runtime observation, or extra edge-proof payload. | not_started |
| **A07** | A06, A04 | **Graph resolver / universal edge judgment.** Define typed wire judgments and the dependent port telescope over legal environments. Prove root, constants, prior outputs, pairs, and projections denote their declared families. Prove every direct edge's producer-output/consumer-input equality for all legal environments, with external values quantified over the entire declared output family. Explicitly reject unconstrained `Sigma n. vector n -> vector 3`. | not_started |
| **A15** | A07, A04 | **Allocation and occurrence model.** Define graph-local plans, exact node alignment, valid fuel/charge allocation, deterministic path-derived occurrence lifting, run-wide charge metric and ledger projections. Prove plan lookup, uniqueness, and lift-preservation lemmas. This is data and local proof support, not yet aggregate P8. It uses first-order graph/resolver judgments, not the public builder, so it can precede generator admission without a module cycle. | not_started |
| **A16** | A15, A07, A04 | **Universal generator admission.** Define `GeneratorMember`/package membership bound to the exact pinned callback. Prove for every legal input, metric, and parent allocation that the generator returns a `SchemaSupported` graph and a valid aligned graph-local plan. The proof is supplied by the pinned generator package, not an unchecked claim or a sample generator run. It depends on schema resolution and allocation definitions, never GraphBuilder; GraphBuilder consumes this witness. | not_started |
| **A09** | A02 | **Graph syntax codec.** Define canonical first-order descriptor encoding/decoding, complete-input parsing, malformed/trailing-byte rejection, and prove graph syntax encode/decode roundtrip plus accepted-byte canonicality. Keep this result explicitly syntactic. | not_started |
| **A08 (P1)** | A07, A16 | **Builder soundness and completeness.** Implement public `start_graph`, `add_node`, and `finish_graph` over one canonical finite-DAG syntax. Prove successful construction is a finite, unique-key, acyclic `SchemaSupported` graph with exact port types; prove failure/success behavior and completeness for every supported finite topology (including independent nodes, fan-out, joins, constants, and projections), up to typed graph isomorphism. Replace current `admit()` builder spine. No topology-size restriction is introduced. GraphBuilder consumes pinned `GeneratorMember` evidence from A16; A16 uses schema resolution/allocation definitions, not GraphBuilder, so the module graph stays acyclic. | not_started |
| **A10 (P2)** | A08, A09, A04 | **Typed graph interpretation/roundtrip.** Resolve decoded root and generated descriptors through the same pinned resolver. Prove exact reconstruction/preservation of input/output indices, work package, constants, port telescope, wires, topology and derived typing witness. Prove typed isomorphism transports dependent contexts and signatures under key renaming; raw label/wire equality is insufficient. No graph closure or typing proof is serialized. | not_started |
| **H1** | A10 | **Human review: schema and graph contract.** Review the custom schema language, universal edge theorem, completeness boundary, root/generated resolver identity, builder expressivity and typed decode theorem. Require the `vector n` counterexample to be rejected statically. | not_started |
| **A11** | H1 | **Canonical journal data and transition definitions.** Define the minimal five events (`RunStarted`, `GraphCommitted`, `NodeCompleted`, `CallIntent`, `CallOutcome`), canonical state as `replay(J)`, derived projections, guarded `apply`, terminal states, and event-specific expected-head conditions. Keep semantic origin separate from replay-checkable `StateWF`; do not add a durable failure state. | not_started |
| **A12** | A11, A02, A10 | **Journal codecs.** Define event/journal codecs and prove roundtrip, unique accepted encoding, framing, and rejection of malformed/torn/trailing representations. Use canonical indexed value/graph bytes and exact run codec identities. | not_started |
| **A13 (P3)** | A12, A04 | **Replay and structural WF.** Prove empty-journal base case; deterministic guarded replay; every legal transition preserves replay-checkable `StateWF`; malformed prefixes reject; terminal state is absorbing; canonical durable logical state is exactly `replay(J)`. Explicitly prove replay alone does not imply computation provenance. | not_started |
| **H2** | A13 | **Human review: journal/replay model.** Review the five-event state machine, event codec, terminal absorption, distinction between `StateWF` and `SemWF`, and serial append contract boundary before provenance and cut proofs depend on it. | not_started |
| **A14** | H2, A04, A10 | **Semantic authority model.** Define `AuthorizedEvent`, event-origin witnesses, append-history `SemWF`, and prefix restriction/extension operations. Keep ghost witnesses out of journal bytes. State exactly how a witness is tied to the selected Work, input, output bytes, generator graph/plan, adapter receipt, and current replay head. | not_started |
| **A17** | A16, A15, A08 | **Typed dynamic splice.** Prove child-boundary substitution at the exact generator input; preserve all internal edge equalities, root result family, global DAG acyclicity, occurrence uniqueness, and exact path-lifted allocations. Prove zero-fuel cannot emit nested generators and nested generator fuel rules. Root and generated topology use the same graph judgment. | not_started |
| **A18 (P4)** | A17, A14, A13, A10 | **Authorized graph commit and visibility.** Prove only the exact admitted generator result and plan can authorize `GraphCommitted`; journal bytes are canonical exact result; successful serial append is the visibility point; no child is actionable before commit. Compose typed splice with transition and append token without depending on P10's crash theorem, P8, or P15. | not_started |
| **A19 (P6)** | A14, A13, A04, A10 | **Local result provenance and absorption.** For exact reconstructed input, prove committed canonical output bytes decode at the exact index and equal the pinned total pure `CodeRef.run`; after commit the occurrence is absent from the future frontier. A calculation interrupted before commit may be recomputed. | not_started |
| **A20** | H2, A02, A04, A11 | **External adapter contract.** Define one-intent-per-submission interface with multiple distinct outstanding keys; stable call key and exact canonical request/resume binding; receipt/evidence/charge/artifact fields; pinned validator and `persist_x`; same-key overlap/retry/restart safe-effect law; changed bindings rejected. Distinct keys may be nondeterministic and finish out of order. State per-key progress separately as a conditional law. | not_started |
| **A21 (P7)** | A20, A14, A13, A04, A10 | **Adapter provenance theorem.** Prove each authorized outcome belongs to its exact intent/key/input, validated typed output, immutable terminal receipt, evidence, charge and resources. Prove same-key retries/overlaps/restarts denote one logical effect and byte-identical terminal tuple from the contract laws; do not assume deterministic replies across distinct keys. Keep liveness conditional. | not_started |
| **A22 (P8)** | A15, A18, A21, A13 | **Charge/fuel ledgers.** Prove replay transition equations and aggregate conservation for free, allocated, reserved, and spent charge plus free/allocated/consumed fuel. Prove graph commit/intents/outcomes preserve exact occurrence projections and reserve/settle once. All charges use the one pinned run metric; do not reallocate unused root remainder dynamically. | not_started |
| **A23 (P9, conditional extension)** | H2, A02, A04, A13 | **Typed artifact identity.** Define exact typed reference/inventory projection and proof-bearing artifact-store laws; prove P9 generically from those laws: publish-before-event-commit, immutable logical version, same-object resolution after supported restart, no overwrite/delete of reachable versions, and replay performs no I/O. The API may omit a store instance and treat references as opaque; only runs supplied with this contract claim backing-object identity, and only their P15/P16 results include the P9 extension. | not_started |
| **A24** | H2, A12, A13 | **Abstract serial journaler contract.** Define compare-and-append, exact head, atomic committed-prefix visibility, monotone persistence, canonical bytes on load, arbitrary crash cuts, no external mutation, and settle/fence of old append requests before recovery load. These are proof-bearing contract fields; no concrete disk/database is implemented here. | not_started |
| **A25 (P10)** | A24, A13, A04, A10 | **Every-cut canonicity/durability.** Prove every recovery load yields exactly the latest complete committed prefix; its bytes are the unique canonical encoding; committed events persist monotonically; old appends cannot cross the recovery barrier; `replay` returns exactly that prefix's state. Keep physical implementation/refinement claims outside this abstract theorem. | not_started |
| **A26 (P5)** | A18, A25, A10, A16, A15 | **Exact generated-graph recovery.** For every recovered prefix with `GraphCommitted`, prove decode/resolution returns the exact committed graph and path-derived lifted plan. Recovery reuses these bytes and allocations and never reruns the generator to select or replace committed topology. | not_started |
| **H3** | A18, A19, A21, A22, A23, A25, A26 | **Human review: independent commit/provenance/cut results.** Review P4/P5/P6/P7/P8/P9-conditional/P10 separately and as compositions. Check graph is visible only after append; bytes alone are not provenance; pending calls retry exact binding; journal cuts cannot admit stale writes. | not_started |
| **A27** | A19, A21, A22, A25, A26, H3 | **Abstract Services and ControllerModel.** Define proof-bearing local/generator executor and scheduler contracts (bounded concurrent claims, only ready inputs, result return, fresh epochs); multi-inflight adapter service; one commit coordinator; serial journal append slot; controller volatile state and atomic steps. No concrete worker pool or runtime. | not_started |
| **A28** | A27, A08, A10, A14 | **Ready-input and claim lemmas.** Prove sparse reconstruction from committed referenced outputs agrees with the full typed graph evaluator in every compatible environment. Prove unique live claim, exact input/allocation binding, fresh epoch, current-head reauthorization, stale permit/result rejection, and commit-gated visibility lemmas. | not_started |
| **A29 (P15)** | A27, A28, A18, A19, A21, A22, A25, A26 | **All-schedule abstract safety.** Induct over every permitted bounded launch, completion, adapter retry/outcome, append, crash, and recovery ordering. Prove typed graph WF, `SemWF`, exact inputs, ledger invariants, unique claims, serial reauthorization, commit-before-visible, recovery barrier safety, and no dispatch after committed completion/outcome. Safety is for arbitrary completion order and uses no fairness. If P9 is included, prove its concurrent artifact extension here as a conditional theorem. | not_started |
| **H4** | A29 | **Human review: concurrency and authorization.** Review the transition relation and all-schedule induction, especially reversed completions, same-key retries, duplicate claims, append/ack crash cuts, stale epochs, and no-postcommit dispatch. Require proof that the serial journaler is sufficient only because one coordinator is modeled. | not_started |
| **A30 (P11)** | H4, A08, A18, A19, A21, A22, A26 | **Enabled frontier/no-stuck.** Prove every started reachable nonterminal replay state has an enabled legal action or same-key resumable intent. Exclude pre-`RunStarted` bootstrap. State this as frontier existence only, not service completion. | not_started |
| **A31 (P12)** | A13, A18, A19, A21, A22, A26 | **Well-founded progress rank.** Define and prove strict decrease of `(G,U,W)` (or an equally explicit well-founded measure) on every successful post-start append under any serialization order. Show stale/rejected appends are not transitions and handle zero-fuel generators. No P15 premise is used. | not_started |
| **A32 (P16)** | H4, A26, A19, A21, A22, A25, A29, A13, A14 | **Recovered semantic graph correctness.** For every authorized abstract trace and crash cut, compose P10 prefix selection, deterministic replay, `SemWF` prefix witnesses, P2/P5 graph typing/recovery, P4 exact generator provenance, P6/P7 result provenance, P8 ledger state, and P15 trace safety. Prove committed work is not rerun/replaced; pending intents resume only on exact binding. Add P9-backed object identity only under its proved contract. | not_started |
| **A33 (P13 schema)** | A29, A30, A31, A25 | **Generic concrete-refinement interface/theorem.** Define `ConcreteRep`, concrete steps, load/barrier mapping, and proof-bearing component simulation obligations. Prove generically that any future runtime supplied with these refinement witnesses simulates the abstract system and inherits established safety/durability results. Specify progress-preserving/finite-stuttering conditions needed to transfer P14. This proves the transfer theorem, not an instance; no OCaml/filesystem/network implementation is in this DAG. | not_started |
| **A34 (P14)** | A30, A31, A33 | **Conditional termination.** Prove the abstract run reaches its typed root output from committed `RunStarted` when explicit weak fairness, total local/generator/validator behavior, executor return, append retries, adapter terminal/reconciliation progress, resource progress if P9 is claimed, finite initial fuel, finitely many crashes, and any P13 progress-preservation obligations hold. Keep all liveness premises out of P15. A concrete runtime inherits this result only after a later P13 instance supplies the refinement proof. | not_started |
| **A35** | A32, A34, A04, A10 | **Proof-bearing API examples.** Construct and verify (1) dependent `Work nat (fun n -> Prime n)` with the callee returning its prime proof in the result; (2) local output reused after recovery; (3) static analysis over typed file/tree refs with adapter materialization, CLI result parsing in F*, and P9 if backing identity is promised; (4) input-dependent graphs with differing finite sizes, joins and fan-out; (5) inline and reusable/library API adapters with identical `OpRef`/P7 semantics; (6) deterministic event-queue adapter with concurrent keyed out-of-order completion. Examples are actual F* proofs and exercise the public API; they do not replace generic theorem proofs. | not_started |
| **A36** | A35, A23 | **Integrated theorem/trust audit and full check.** Verify all abstract P0–P12/P14–P16 targets, the generic P13 transfer theorem, and contract law owners against implementation spec; identify that no concrete P13 instance is claimed. Inspect transitive dependencies for `assume`, `admit`, unreviewed axioms, duplicate sources of truth, unproved solver boundary, or host claim hidden in an abstract theorem. Run the complete project F* check and record tool versions/command/results. No unresolved theorem may be called verified. | not_started |
| **H5** | A36 | **Human review: abstract system complete.** Present source modules, theorem map, contract assumptions, successful full-check evidence, and explicitly deferred concrete instances. Stop here. A concrete runner/SQLite/filesystem/network P13-instantiation DAG requires a separate plan and review. | not_started |

## Theorem dependency checklist

The table above refines this normative proof order; later nodes must preserve
these dependencies and theorem meanings:

| Theorem | Required proved inputs |
|---|---|
| P0 pinned identities/codecs | Proof-bearing package, codec, manifest, root-entry, and reload laws; exact package projection. |
| P1 typed graph builder/resolver | P0; schema denotation/equality calculus; universal edge compatibility and builder completeness for exactly `SchemaSupported`. |
| P2 graph codec and typed resolution | P0/P1; canonical syntax roundtrip and exact typed witness reconstruction for both root/generated graphs. |
| P3 canonical replay | P0/P2 plus fixed journal codec laws; guarded deterministic replay, `StateWF`, terminal absorption. |
| P4 graph commit | P1–P3; universal generator admission, exact plan, typed splice/global DAG, exact authorized append before child visibility. |
| P5 graph recovery | P2/P4/P10; exact committed graph and lifted plan reused. |
| P6 local provenance | P0/P3; exact reconstructed input, result equal to pinned function, committed occurrence absorbing. |
| P7 external provenance/effect safety | P0/P3; exact key/binding, effect-safe retry, immutable receipt and output correlation; progress conditional. |
| P8 charge/fuel | P3/P4/P7; one-time settlement, exact plan projections and conservation. |
| P9 resources | P0–P3 and artifact-store contract; conditional extension to P15/P16 only when resource identity is claimed. |
| P10 every-cut durability | P0–P3 and serial journaler contract; exact latest prefix bytes, canonicality, monotonicity, stale append fencing. |
| P11 frontier | P1–P8/P15; enabled action or exact resumable intent in started nonterminal states. |
| P12 progress rank | P3–P8; strict well-founded decrease for every successful append, independent of P15. |
| P13 refinement | P0–P8/P10–P12/P15, with P9 only for promised backing identity; this DAG proves a generic transfer theorem, not a host instance. |
| P14 conditional termination | P11–P13 plus explicit fairness/service/fuel/crash assumptions. |
| P15 all-schedule safety | P0–P8/P10, plus P9 extension only if claimed; arbitrary interleavings, no fairness. |
| P16 recovered semantics | P0–P8/P10/P15, with P5 named explicitly and P9 only for backing identity; every-cut typed graph, provenance, and no-rerun theorem. |

## State and provenance protocol

- [`state.md`](state.md) names this DAG as authoritative and states the
  objective and no-execution status.
- [`node_summaries.md`](node_summaries.md) records historical S2 planning
  separately from this DAG; for A00–H5 it records no execution until nodes
  actually start.
- [`run_log.md`](run_log.md) is chronological and records this planning
  revision without claiming a DAG node ran.
- [`research/registry.md`](research/registry.md) tracks source, theorem-order,
  and adversarial reviews for this DAG.
- [`legacy_v2_work_dag.md`](legacy_v2_work_dag.md) is historical only. It is
  not an alternate execution authority.

Before any future node starts, update the run log. On completion, first record
the artifact, verification evidence, and remaining obligations in
`node_summaries.md`; then update status in this DAG and `state.md`. Keep the
diagram, table, state hub, summaries, and log consistent. Do not mark a node
complete because earlier source resembles its planned result.
