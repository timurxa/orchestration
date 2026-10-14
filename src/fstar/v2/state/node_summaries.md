# F* v2 node execution summaries

This file preserves historical V2 implementation evidence and S2
specification-planning summaries. The active proof DAG is the new A00–H5 plan
in [work_dag.md](work_dag.md); no node in that plan has started, so it has no
execution summaries yet. See [state.md](state.md) for the objective and
current status.

Keep one durable summary per stable node ID. The chronological sequence of
starts, finishes, and checks belongs in [run_log.md](run_log.md).

## S2-00 — Source and theorem evidence ledger (complete)

- Started and completed: 2026-10-13. Read-only source/evidence audit covered
  all seven current F* modules, P0-P16, normative spec, theorem guide, and
  historical V2 records. Two independent source audits plus root integration.
- Result: [S2-00-evidence-ledger.md](research/S2-execution-2026-10-13/S2-00-evidence-ledger.md)
  classifies every P0-P16 target with source references and distinguishes
  proof bodies, declarations, assumptions/admissions, contract targets, and
  host refinement. No P0-P16 system theorem is fully discharged by current
  source. Historical full-build claims are explicitly qualified.
- Consistency repair: P15/P16 base dependencies now exclude optional P9;
  P10 is included in P16 composition. P9 extends claims to persistent backing
  object identity. Stale theorem-guide references were corrected. No DAG
  dependencies or node scopes changed.
- Validation: independent reviewer checked corrected source references and
  ReadyInputAgreement gap. No F* source changes, implementation, verifier run,
  or tests.
- Next: S2-01 is ready; it must settle a constructive graph resolver and its
  exact completeness boundary before dependent graph/replay work starts.

## S2-01 — Dependent graph representation decision (complete)

- Start: 2026-10-13 after S2-00 acceptance. Scope: compare typed constructor
  AST, type-schema checker, proof reflection, and registry-pinned GraphResolver.
- Required invariant: edge acceptance remains universal across all legal
  environments; no resolver reads produced outputs/external replies; no
  per-edge proof bytes; public builder and recovery resolver accept same
  declared graph language.
- Result: [S2-01-graph-resolution.md](research/S2-execution-2026-10-13/S2-01-graph-resolution.md)
  selects a canonical manifest schema language and one proof-producing
  registry-pinned GraphResolver shared by public construction and recovery.
  P1/P2 completeness is exactly for `SchemaSupported`; topology is unbounded,
  but arbitrary erased F* `Type0` equality is not claimed. Typed AST is a
  builder frontend only, proof reflection is authoring/verifier support only,
  and per-Work rules are permitted only as pinned proved schema extensions.
- Clarified generated graph boundary: its exact generator input may derive
  from committed external output; P4 proves admission for every input and
  allocation. Internal ports remain universally quantified and sampled
  outputs cannot repair static edges. At S2-01 the report allowed a pinned
  validator postcondition to narrow external values; S2-03 explicitly
  supersedes that clause with the stricter full-declared-family rule.
- Compared three independent research reports and an adversarial reviewer.
  Reviewer found no blocker; exact AST, equality calculus, and validator
  predicate encoding were assigned to S2-03. The policy amendment is recorded
  in the S2-01 decision's dated S2-03 section, preserving the original node's
  history.
- Updated §2.2.1 and the expressibility/P1 statements in
  `implementation_spec.md`, plus the theorem guide. No DAG structure or
  dependency changed. No F* source, implementation, verifier, or tests.
- S2-02 and S2-03 are now ready and started in parallel.

## S2-02 — Identity, manifest, codec contracts (complete)

- Start/completion: 2026-10-13, after S2-01. Scope: P0 exact manifest
  projection and identity binding, package uniqueness/coherence, plain and
  indexed codec laws, root entrypoint, restart stability, and the P13 host
  identity boundary.
- Result: [S2-02-pinned-manifest.md](research/S2-execution-2026-10-13/S2-02-pinned-manifest.md).
  The manifest is a canonical projection of the actual package tables with
  exact membership in both directions. It rejects duplicates before sorting;
  each executable identity resolves one full package. Bidirectional
  `manifest_named_by`/bundle identity equations bind the journal key to that
  same projection. Root start binds input/graph codecs, result family, exact
  graph bytes and allocation plan. Codec acceptance is round-trip canonical.
- Abstract restart returns the same manifest; concrete host binary/extraction
  matching remains P13. Resolver/module dependencies are acyclic and use one
  shared manifest core. Independent P0 review passed at contract level.
- No `.fst`/`.fsti` edits, F* run, implementation, or tests. P0 source proofs
  are later implementation work, not discharged by this specification.

## S2-03 — Typed graph language, builder, resolver (complete)

- Start/completion: 2026-10-13, parallel with S2-02 after S2-01. Scope: P1/P2
  finite DAG/wire rules, exact legal environments, fixed Work input and
  dependent output family, builder, graph codec/resolver, and typed
  completeness/isomorphism.
- Result: [S2-03-typed-graph-contract.md](research/S2-execution-2026-10-13/S2-03-typed-graph-contract.md).
  The spec defines the schema AST and semantic judgments, a dependent
  `PrefixSupported` invariant, universal wire/input equality, exact builder
  `None`/success laws, syntax round-trip/canonicality, resolver soundness and
  completeness, and typed graph isomorphism. Root and generated descriptors
  share this resolver. P4's all-input/allocation admission is stated as a
  contract; S2-04 owns its proof and global substitution.
- Policy resolution: S2-01 had allowed a pinned validator postcondition to
  narrow the external legal set. S2-03 selects the stricter rule from the
  latest project direction: graph typing quantifies over the full declared
  output family, includes every accepted reply, and uses no validator-side
  assumption. Subset restrictions required for wiring belong in the declared
  result type. This can reject some validator-safe edges by design.
- Independent re-review confirmed the formal judgments/prefix/builder shape
  and flagged only that policy choice; the dated S2-01 amendment records its
  resolution. S2-02/03 contract boundary is now consistent.
- No `.fst`/`.fsti` edits, F* run, implementation, or tests. Source-level
  schema, resolver, builder, and codec proofs remain for a later implementation
  DAG.

## S2-04 — Generator and allocation contracts (complete)

- Start: 2026-10-13 after S2-02 and S2-03 completion. Scope is P4/P5:
  all-input/allocation generator admission, aligned allocation plans,
  deterministic occurrence lifting, graph commit, global typed-DAG
  substitution, and exact recovery of committed topology.
- Updated the normative spec with exact all-input/allocation admission,
  graph-local allocation-plan alignment, root/nested allocation bounds,
  deterministic occurrence lifting, append authorization, typed graph splice,
  and P5 recovery that reuses committed bytes/plan without generator replay.
  Evidence: [S2-04 report](research/S2-execution-2026-10-13/S2-04-generator-commit.md).
- Audits found and repaired a real P12 counterexample: `(G,W)` can increase
  when a zero-fuel generator expands into finite ordinary nodes. The revised
  `(G,U,W)` natural lexicographic rank covers both zero- and positive-fuel
  commits. Independent review checked each accepted event class and graph
  transition. The plan predicates are still schematic proof obligations;
  this node claims contract completeness, not generic F* proof discharge.
- `key_correctness_theorems.md` now includes the rank definition and
  S2-04-to-P4/P5 plan-lifting boundary. Registry provenance includes both
  independent reviews and the earlier counteraudit.
- Acceptance met without changing DAG structure. No `.fst`/`.fsti` edits,
  implementation, F* run, or tests.

## S2-05 — Canonical journal and replay machine (complete)

- Outcome: complete at specification-contract level after S2-02, S2-03, and
  S2-04. Evidence and decisions are in
  [S2-05-canonical-replay.md](research/S2-execution-2026-10-13/S2-05-canonical-replay.md).
- The normative spec now gives five event constructors with explicit
  structural guards and state deltas, an empty pre-run state, deterministic
  replay, exact-head proof-bearing append, absorbing terminal derivation,
  separate event/journal codec laws, and P3's non-circular `StateWF` proof
  target. It distinguishes replay-checkable `StateWF`, graph-level
  `GlobalGraphWF`, and append-history `SemWF`.
- Integrated three independent audits: transition completeness, canonical
  encoding layers, and replay-valid but semantically unauthorized event
  counterexamples. Run/sequence duplication was rejected because list index
  and the single `RunStarted.run_identity` already determine `(run,sequence)`;
  adapter resume bytes remain opaque here and are interpreted under P7.
- No P3 theorem was proved in source. P10 still must connect physical bytes to
  exact durable prefixes; P13 must refine the private authorized write path.
  No `.fst`/`.fsti` edits, implementation, F* run, or tests.

## S2-06 — Concurrent abstract executor (complete)

- Start: 2026-10-13 after S2-05 completion. Scope is P15: define the
  abstract frontier/controller, volatile occurrence claims, exact
  `ReadyInputAgreement`, bounded local/generator concurrency, serial
  reauthorization and append, arbitrary legal completion order, and crash
  behavior.
- Result: [S2-06-controller-interleavings.md](research/S2-execution-2026-10-13/S2-06-controller-interleavings.md).
  The spec defines the controller steps, exact sparse/full input agreement,
  proof-bearing candidate provenance, latest-head reauthorization, serial
  commit visibility, and P15 over every allowed finite schedule. `SemWF`
  tracks exactly the successful append history and its authorization
  witnesses.
- Integrated independent audits for claims/scheduling, crash cuts, append
  authorization, and recovery fencing. Added identical `StartRequest` retry
  binding, non-reused attempt epochs, rejection of stale callbacks, and a P10
  recovery barrier that settles/fences old appends before load. A final
  adversarial review found no remaining acceptance gap. Concrete mechanisms
  remain P13 obligations; P10/P15 are not proved in source.
- No DAG structure or acceptance condition changed. S2-06 is complete;
  S2-07 has started independently because both depend only on S2-05.
- No `.fst`/`.fsti` edits, implementation, F* run, or tests.

## S2-07 — Multi-inflight external adapter (complete)

- Start: 2026-10-13 after S2-05 completion; S2-06 is an independent parallel
  branch. Scope is P7: formalize keyed adapter submits/retries and outcomes,
  same-key effect safety under recovery and overlapping retries, distinct-key
  concurrency, validation/evidence/charge correlation, and conditional
  progress.
- Result: [S2-07 adapter contract](research/S2-execution-2026-10-13/S2-07-adapter-contract.md).
  P7 now defines the adapter key `K`, exact request/resume binding `Q`,
  immutable terminal receipt `T`, mismatch rejection, cross-restart
  `EffectSafe`, and an exact-input `P7ReceiptWitness`. `persist_x(T)` maps
  validated raw reply bytes to canonical indexed output bytes and correlates
  those bytes with the same evidence, charge, and artifact references stored
  in `CallOutcome`. Replay decodes the canonical bytes and never repeats the
  operation or validator.
- The contract admits distinct-key nondeterminism and out-of-order
  completion, with finite multi-inflight capacity. P7 liveness requires
  fair retry/query/response service and eventual completion or definitive
  reconciliation; a full capacity of permanently stuck calls blocks further
  dispatch progress. P15 owns workflow dispatch/late callback handling; P8
  owns one-time charge settlement; P9 owns persistent artifact identity;
  P10/P16 preserve committed outcomes through recovery.
- Independent retry and interleaving reviews passed after the receipt
  projection was made explicit. No P7 acceptance gap remains. Evidence and
  review provenance are recorded in the adapter contract report and
  [research registry](research/registry.md).
- S2-07 complete; S2-08 started after its dependencies S2-04, S2-05, and
  S2-07 were complete. No DAG topology or acceptance condition changed.
- No `.fst`/`.fsti` edits, implementation, F* run, or tests.

## S2-08 — Budget and artifact contracts (complete)

- Start/completion: 2026-10-13, after S2-04, S2-05, and S2-07. Scope was P8/P9:
  occurrence-keyed charge/fuel conservation and settlement, plus generic typed
  durable references to files, trees, and other external resources.
- Result: [S2-08-budget-artifact-contracts.md](research/S2-execution-2026-10-13/S2-08-budget-artifact-contracts.md).
  P8 pins one charge metric at the run, derives ledger projections from
  canonical plans/events, checks bounds before subtraction, and proves
  conservation/once-only settlement. P9 defines typed existential references,
  exact `refs_of` inventories, publish-before-commit, immutable versioned
  identity, and post-restart resolution to the same logical resource.
- Three read-only audits covered P8 arithmetic, P9 resource typing/lifecycle,
  and P8/P9 composition into replay, concurrency, recovery, and liveness. The
  final integrated audit passed; its one wording correction was applied to the
  P8 audit record. No contradiction or DAG change was needed.
- Alternatives recorded: one scalar pinned metric over vector ledgers;
  generator metric derived from `RunBudget` rather than copied into each
  allocation; typed existential refs over untyped labels; logical identity
  across restart over same process-local handle; pure replay over store I/O.
- No `.fst`/`.fsti` edits, implementation, F* run, or tests.

## S2-09 — Serial store, every-cut recovery, semantic theorem (complete)

- Start/completion: 2026-10-13 after S2-05, S2-06, S2-07, and S2-08.
  Completed at specification-contract level; P10/P16 remain theorem targets.
- Result: [S2-09-serial-recovery-contract.md](research/S2-execution-2026-10-13/S2-09-serial-recovery-contract.md).
  P10 now relates exact loaded physical bytes to the latest committed prefix,
  derives byte equality from canonical journal encoding, formalizes serialized
  compare-and-append and recovery fencing, and states monotone every-cut
  recovery. P16 composes this with `SemWF`, universal root/generated graph
  typing, exact provenance, and safe pending-call retry.
- Two precision fixes were integrated after independent review: storage bytes
  are the sole durable source while `load_store` is their decoded projection;
  no-repeat-after-commit is a controller-trace property, separate from the
  recovered frontier property. Pending-intent retry at a cut quantifies only
  over intents present and pending in that cut's prefix.
- Three independent audits passed after those fixes. They attacked physical
  byte refinement, state-versus-history theorem scope, late appends/callbacks,
  root-start races, commit/ack cuts, external retry windows, and concurrent
  independent completions. The cut is the post-exit load barrier: an in-flight
  append may commit before it and must then be recovered, or abort and never
  commit afterward.
- No DAG topology or acceptance condition changed. No `.fst`/`.fsti` edits,
  implementation, F* run, or tests.

## S2-10 — Progress, fairness, no-loop, termination (complete)

- Started: 2026-10-13 after S2-06, S2-08, and S2-09 completion. Completed at
  specification-contract level after three independent reviews. Scope was
  P11 enabled frontier/no-stuck, P12 strict progress rank, and P14 conditional
  termination under explicit fairness/service assumptions.
- Results and review evidence:
  [S2-10-progress-termination.md](research/S2-execution-2026-10-13/S2-10-progress-termination.md),
  [frontier audit](research/S2-execution-2026-10-13/S2-10-frontier-audit.md),
  [rank audit](research/S2-execution-2026-10-13/S2-10-rank-audit.md), and
  [termination audit](research/S2-execution-2026-10-13/S2-10-termination-audit.md).
- Reconciled the theorem guide with P4: root generators may have zero fuel;
  nested generators must receive positive fuel. Thus positive-fuel graph
  commits lower `G`; zero-fuel commits have no generator children and lower
  `U`; ordinary completions and external phase changes lower `W`.
- P11 now proves logical frontier existence only. P14 applies after committed
  `RunStarted` and states fairness for ready claims, result return, serial
  appends/retries, adapter response consumption/capacity release, P7 key
  progress, needed artifact resolution, and finite process exits. This keeps
  service liveness separate from frontier safety and does not require parallel
  journaling.
- Independent reviews found no remaining state/frontier counterexample, rank
  counterexample, or concurrency/liveness contradiction. No DAG topology or
  acceptance criterion changed. No `.fst`/`.fsti` edits, implementation, F*
  run, or tests.

## S2-11 — Concrete refinement boundary (complete)

- Started: 2026-10-13 after S2-09 and S2-10 completion. Scope is P13: specify
  the obligations a concrete controller, worker pool, serial journaler,
  adapter, codec/manifest reload path, host extraction layer, and optional
  resource store must prove to refine the abstract contracts.
- Result: [S2-11-concrete-refinement.md](research/S2-execution-2026-10-13/S2-11-concrete-refinement.md)
  adds P13's concrete representation relation, forward simulation/stuttering
  contract, crash-load mapping, and component proof burdens. It binds current
  journal bytes and append history to the replay-derived P15 controller,
  requires append fencing before recovery load, empty volatile state and a
  fresh epoch after load, and exact pinned adapter validation/projection.
- Three independent audits passed: controller/worker, journaler/storage, and
  adapter/identity/resource. The P13 dependency list keeps P9 conditional on
  persistent resource identity. P10/P14/P15/P16 boundaries remain consistent.
- No `.fst`/`.fsti` edits, implementation, F* run, or tests.

## S2-12 — Implementation-ready packet and adversarial audit (complete)

- Started: 2026-10-13 after S2-11 completion. Scope: translate the normative
  P0-P16 system and P13 refinement boundary into a later-agent-ready module,
  interface, representation-constraint, theorem-order, alternatives, and
  acceptance packet.
- Result: [implementation packet](../implementation_packet.md) now maps the
  P0-P16 contracts to a proposed acyclic source-module graph, API and journal
  signatures, proof order, theorem acceptance checklist, alternatives, six
  proof-bearing expressibility examples, and representation owners/decision
  rules. It separates typed graph interpretation (P2), generator contract
  evidence from graph construction, P4 commit visibility from generator
  splice, and P5 graph recovery from P16 semantic recovery. `GeneratorMember`
  is explicitly a package-author proof input bound by P0 and consumed by
  P2/P4. P4 precedes P8 without a module back-edge; P6/P7 proofs are separate
  from witness definitions.
- Independent architecture, proof-order, integrated, counterexample,
  GeneratorMember-contract, and P4 append-boundary reviews passed after fixes.
  Initially failing P2/P4 ownership and P4/P8
  dependency findings remain in the research reports as provenance and are
  resolved in the packet; final passes are linked from the
  [research registry](research/registry.md).
- `implementation_spec.md` §8 now states that representation choices remain
  for the later implementation; packet module names and ownership are
  proposals while normative dependency order stays fixed.
- No `.fst`/`.fsti` edits, implementation, F* run, or tests. S2-HUMAN is now
  awaiting user review; no implementation DAG was started.

## Historical state — V2-03 in progress at the time of the last implementation pass

V2-01 and V2-02 were reopened on 2026-10-12 and revised to remove per-work
capture channels, typed work-reference wrappers, duplicate journal fields,
and graph-size bounds. Their current outcomes appear in the final two sections
below. The earlier V2-01 and V2-02 summaries are retained as historical
evidence and are superseded where they describe the old API. The normative
contracts are in `../implementation_spec.md`.

- `Work` has only `LocalWork`, `ExternalWork`, and `GenerateWork`; each
  `durable_work_ref` is derived from its `Work`.
- A pinned registry bundle remains necessary to resolve heterogeneous durable
  references after decoding. Typed node and constant witnesses now carry exact
  membership in that bundle, with exact work/codec-key lemmas. The bundle
  identity is not yet proved to bind its contents, and decoding still cannot
  reconstruct the dependent witness; P0/P1/P2 remain open.
- No work kind has a separate capture value. Inputs carry per-run settings;
  code/operation/generator identities pin fixed definitions/configuration.
- `GenerateWork` stays indexed by the workflow result family, while its
  generator returns a `GraphDesc`; the committed child graph supplies the
  eventual indexed output.
- Graph expressibility is over arbitrary finite DAGs. The only execution
  controls are one occurrence-keyed fuel/charge allocation plan. There are no
  node/depth/encoded-size graph bounds.
- `CallKey` is the adapter `NodeOccurrence`. `CallIntent` stores the key and
  adapter resume data; operation, request, and maximum charge are derived.
  `GraphCommitted` derives its parent from the generator occurrence. Root
  input bytes carry an explicit input-codec identity.

The latest full F* command passes all seven modules. It proves the syntax codec
and chain/allocation example results recorded below, but does not close exact
heterogeneous graph resolution, typed builder, P0/P1/P2, adapter, or host-store
holes.

## V2-00 — Spec inventory and typed kernel

- Outcome: complete
- Changes: proof-obligation inventory below and the checked typed-kernel
  module at `src/WorkflowV2/Kernel.fst`; added the V2 `verify` target.
- Theorems: P0–P14 mapped to their definitions and prerequisite results.
- F* check: `opam exec -- make -C src/fstar/v2 verify` passed with F* 2026.03.24
  and Z3 4.15.4. The first attempt failed; its issues and correction are
  recorded in `run_log.md`.
- Assumptions/admissions: the normative spec's boundary premises remain
  conditional; this module adds no `assume` or `admit`. P0 and graph
  well-formedness remain future proof obligations.
- Follow-up: the user reviewed and approved V2-00. V2-01/V2-02 and their review
  gate were later completed; V2-03 is now the active DAG node.

### Retry history

The initial inventory-only acceptance conditions were completed and the
human gate was reached. On the user's “Try again”, the scope was explicitly
revised to include the typed-kernel declarations requested for review. The
revised scope is now complete; the inventory below remains part of the result.

### Typed-kernel declarations

`WorkflowV2.Kernel` exposes `work input output`, with `output : input ->
Type0`, and exactly three core constructors: `LocalWork`, `ExternalWork`, and
`GenerateWork`. `code_ref.run` returns the result indexed by the exact input;
external work validates reply bytes into that family without claiming the
external effect is pure or deterministic. `generator_ref.generate_graph` is
total and input-indexed and returns a `graph_desc`. A durable work reference
is derived from `Work`. Plain and indexed codec records state round-trip and
canonical-encoding laws as obligations of each codec.

At this layer `graph_desc` carries its payload bytes with its input/output
indices. V2-02 must replace this boundary payload with the finite, first-order
typed DAG representation and prove graph well-formedness, soundness, and
completeness. This module does not claim those properties or P0.

### Specification map

| Specification area | Main content | Obligations |
|---|---|---|
| §1–2 | Goal, indexed `Work`, local code, external operations, dynamic graph descriptor/builder, pinned references, and occurrence allocations. | P0–P2 establish identity/codecs, builder soundness and completeness, and descriptor-byte round-trip plus typed resolution. |
| §3 | Generic typed artifacts backed by files, trees, network resources, or other host objects. | P9 proves publication-before-reference and stable recovery under the resource-store contract. |
| §4.1–4.2 | Canonical journal state, event grammar, replay, generation commit, local completion, adapter intent/outcome, and terminal state. | P3–P7 establish replay/WF/absorption, graph commit/global-DAG preservation/exact recovery, local no-rerun, and adapter intent safety/progress. |
| §4.3 | Append-only store model, crash cuts, canonical encodings, and monotone committed prefixes. | P10 proves every-cut durability and canonical recovery, conditional on the concrete store premises. |
| §5 | State invariants, charge/fuel accounting, enabled frontier, strict progress rank, and termination conditions. | P8 and P11–P14 cover ledgers, no-stuck, no infinite successful append sequence, runner refinement, and conditional termination. |
| §6–8 | Required proof list, permitted premises, expressibility targets, and open representation choices. | Normative checklist for all proof nodes; examples constrain expressibility but are not tests or proof substitutes. |

### Proof dependency map

| Result | Depends on | What it enables |
|---|---|---|
| P0 | Pinned registry and codec laws. | Typed work/graph references can be resolved to exact semantics and canonical bytes. |
| P1 | P0; explicit finite graph and wire typing definitions. | Every built descriptor is a typed DAG, and every admissible finite typed DAG can be built. |
| P2 | P0, P1; graph codec laws. | Persisted graphs decode to the exact typed graph and pinned work, without serializing closures. |
| P3 | P0, P2; event transition definitions. | A journal prefix has one deterministic well-formed state and absorbing terminal behavior. |
| P4–P5 | P1–P3; pure pinned generator and graph commitment rules. | Dynamic expansion preserves global DAG invariants; recovery reuses committed graph bytes. |
| P6 | P0, P3; runner authorization for local work. | A completion is the pinned computation's result and cannot authorize re-execution. |
| P7 | P0, P3; adapter safety, correlation, and liveness premises. | Every operation starts from a durable intent and resumes under that same logical call. |
| P8 | P3–P7; occurrence-keyed allocation transitions. | Charge/fuel conservation and single reservation/settlement support progress arguments. |
| P9 | P0, P3; resource-store durability and identity premise. | A journaled artifact reference resolves to the same durable typed artifact after restart. |
| P10 | P0, P2–P3; atomic-prefix, monotone-durability, protocol-integrity, and canonical-store premises. | Every crash cut recovers exactly the latest committed journal prefix. |
| P11 | P1, P3–P9; total local/generator actions, resumable adapter, and store/adapter liveness. | Every reachable nonterminal state has a valid continuation and cannot remain pending forever under the liveness premises. |
| P12 | P3–P5, P8; finite initial fuel and strict lexicographic rank decrease. | Infinite successful journal-append sequences are impossible after `RunStarted`. |
| P13 | P0–P10; concrete runner/extraction refinement. | Executed actions and appended results correspond to authorized abstract transitions. |
| P14 | P11–P13 plus fair scheduling, store progress, total local work, adapter outcome, and finitely many process exits. | The workflow conditionally reaches its typed root output. |

### Boundary premises and points to resolve

- Concrete journal storage must establish atomic append, latest-prefix load,
  monotone durability, canonical encoding, and no external mutation. The crash
  theorem excludes media loss, external corruption, and rollback.
- Registry identity, pure-code totality, codecs, graph codec/completeness, and
  typed graph substitution are concrete proof obligations; they are not
  top-level axioms. Adapter effect safety and eventual outcome are
  operation-specific premises until proved by the adapter implementation.
- Resource adapters own physical materialization and must prove the generic
  publish-before-reference and same-object-after-restart contract. The kernel
  does not make files, sockets, or database handles primitive values.
- §8 leaves dependent port contexts, graph representation, node keys, and
  concrete store/adapter refinements open. P1/P2 still require actual
  soundness/completeness proofs; an unconstrained `dag_wf` cannot satisfy them.
- P6 and P7 both mention reuse after recovery. The typed kernel should state
  precisely that a completed occurrence cannot be re-executed, while a
  pending `CallIntent` may be resumed only as the same logical call.
- Resolved in the simplification revision: the normative file is headed
  “F* workflow v2”; its signatures are schematic where representation remains
  open, and `state.md` names it as the implementation source of truth.
- P11, P12, and P14 are distinct: no stuck state, no infinite successful
  journal transitions, and conditional end-to-end termination. P12 does not
  rule out an adapter looping internally, runner stuttering, or infinitely
  many process exits; P14 adds the required liveness/fairness conditions.

## Summary template

```markdown
## <node ID> — <short title>

- Outcome: in_progress | complete | blocked
- Changes: files and declarations added or revised
- Theorems: statements proved or still open
- F* check: command/result, or not run with reason
- Assumptions/admissions: each item, owner, and discharge condition
- Follow-up: remaining work and dependent-node implications
```

## V2-01 — Pinned identity and event vocabulary (pre-simplification history)

- Outcome: complete for the declaration phase; host-level P0 remains open.
- Changes: added `WorkflowV2.Identity.fst` and `WorkflowV2.Journal.fst` to the
  checked module set. `work_package` derives its durable reference from the
  exact executable `Work`; structural identity comparators have soundness
  lemmas; heterogeneous work/codec registries expose exact lookup lemmas and
  require uniqueness; `pinned_registry_bundle` ties both registry identities
  to the identity named by `RunStarted`. Codec decode/canonicality lemmas are
  derived from the exact codec carried by each `Work`. Journal event/action
  vocabulary is first-order and introduces no transition authority.
- Theorems: comparator soundness, exact successful resolver result, and
  canonical decoded input/output encodings typecheck as ordinary lemmas. This
  is not a complete `identity_codec_canonical` theorem over graph decoding or
  across process restarts.
- F* check: included in `opam exec -- make -C src/fstar/v2 verify`; all four
  modules pass under F* 2026.03.24 with `--cache_off` and warning 285 fatal.
- Assumptions/admissions and owners:
  - `global_registry_unique` and `global_codec_unique` are obligations on
    registry values, not proven constructors. V2-03/P0 must provide a closed
    constructor or inductive registry and prove uniqueness/presence behavior.
  - `pinned_registry_bundle` proves same identity inside one F* value only.
    V2-11 owns proving or explicitly refining the host's reload of that exact
    bundle after process restart; recovery must fail closed if unavailable.
  - The F* registry selects exact values, but build IDs are not proven to
    identify separately compiled host code. V2-11 owns extraction/runtime
    refinement.
- Follow-up: V2-02 uses the identity and journal vocabulary. P0 remains an
  explicit downstream proof target; do not claim it has been discharged.

## V2-02 — Typed finite DAG and builder theorem spine (pre-simplification history)

- Outcome: complete as a declaration/interface review milestone; P1 remains
  unproved. V2-HUMAN-02 is now `awaiting_human`.
- Changes: `WorkflowV2.Graph.fst` defines finite DAG maps and a topological
  permutation, structural edge-order checks, raw key-renaming isomorphism,
  dependent wire syntax, explicit syntax-directed `wire_typing_witness`,
  typed `wiring`, root/constant/indexed-constant/output/pair/projection
  constructors, a minimal start/add/finish surface, `builder_reachable`, a
  typed node-sequence judgment, and an exact projection witness into the
  first-order DAG. Numeric node-key order is no longer required to equal the
  supplied topological order.
- Theorems: `graph_sound` follows directly from the definition of `graph_wf`;
  `builder_finish_nodes_preserved` is proved. The theorem interfaces for
  start/add laws, `finish_graph_sound`, `graph_complete`, and bounded
  completeness are present, but their bodies use `admit()`. The current
  `graph_isomorphic` is structural and does not transport dependent port
  typing; it is weaker than the full P1 equivalence required by the spec.
- F* check: `opam exec -- make -C src/fstar/v2 verify` passed for Kernel,
  Identity, Graph, and Journal. This establishes well-typed declarations and
  discharges non-admitted VCs only; F* accepts the deliberate `assume` and
  `admit` holes, so it is not evidence that P1 is proved. No separate tests
  were run.
- Assumptions/admissions and owners:
  - `port_context`, `port_env`, `port_ref`, `graph_builder`, `root_port`,
    `extend`, `prior_env`, `port_ref_key`, and `eval_port_ref` are abstract
    representation boundaries. V2-02 proof work must establish laws tying
    each key/evaluator to the exact prior typed node and context.
  - `start_graph` and `add_node` are assumed operations. `start_graph_law`
    and `add_node_appends_exact` are admitted. V2-02 must implement or refine
    builder state and prove those laws, freshness, preservation, and ordering.
  - `finish_graph_sound`, `graph_complete`, and `graph_complete_bounded` are
    admitted. P1 requires soundness plus completeness for every admitted finite
    typed DAG, preserving occurrences, constants, wires, and output typing.
  - `graph_fits_bounds` is assumed and owned by V2-03; this is outside the
    unbounded P1 core but blocks bounded completeness claims.
  - Current revision indexes `typed_graph_witness` and `dag_wf` by the pinned
    registry bundle, but does not prove unique registry resolution. The
    witness can still contain a typed Work/codec unrelated to the bundle.
    V2-02/P0 must connect every graph label and constant codec to one pinned
    snapshot.
  - Raw `graph_isomorphic` compares erased serialized labels and renamed wire
    syntax only. V2-02 must define typed isomorphism and prove transport of
    dependent port environments, resolved work signatures, codec evidence,
    and occurrence multiplicity.
- Follow-up: this summary is the requested review artifact. Stop at
  V2-HUMAN-02; V2-03, V2-04, and all other descendants remain unstarted.

## V2-01 — Pinned identity and minimal journal vocabulary (current)

- Outcome: complete for the revised declaration/interface milestone; P0 and
  runtime identity refinement remain open. V2-HUMAN-02 is again
  `awaiting_human` after the dependent V2-02 revision.
- Changes: removed the redundant typed `work_ref`/`work_package` pairing and
  constructor wrappers `local`, `external`, and `generate`. `durable_ref_of_work`
  derives the only durable work label from the exact `Work`. The heterogeneous
  `global_work_registry` remains as the single resolver needed after decoding;
  `pinned_registry_bundle` contains the work and codec resolvers under one
  identity. `RunStarted` records the root input codec identity. `CallKey` is
  exactly a `NodeOccurrence`; `CallIntent` stores only that key and resume data.
  Charge reservation and work/input identity are derived from pinned state.
  `GraphCommitted` no longer repeats the parent graph, which is determined by
  its generator occurrence. Event identity is the run/sequence pair; the
  redundant `event_identity` field was removed.
- Proofs/typechecked declarations: structural identity comparisons, exact
  successful resolver results, canonical work-input decoding, and journal
  event shapes remain in the module set. No `assume` or `admit` was added in
  this revision.
- F* check: `opam exec -- make -C src/fstar/v2 verify` passed for Kernel,
  Identity, Graph, and Journal with cache disabled and warning 285 fatal.
- Open proof boundary: registry uniqueness still appears as a record field;
  `bundle_identity` is not tied to the work/codec/graph-codec manifest in the
  current declaration; build identity and host reload are not refined;
  root-entrypoint and input-codec resolution must connect to the same pinned
  bundle. P0 is not proved.
- Follow-up: V2-03 must establish exact registry resolution for every decoded
  work and codec reference. No later DAG node has started.

## V2-02 — Capture-free typed graph declaration (current)

- Outcome: complete for the revised declaration/interface milestone; P1 is not
  proved. V2-HUMAN-02 is `awaiting_human`.
- Changes: `dag_wf`, `graph_wf`, `finish_graph_sound`, and `graph_complete` now
  carry the actual pinned registry bundle. Removed the tautological
  `is_typed_dag` alias, trivial `graph_sound` wrapper, and one-use optionality
  helpers. Renamed the code's erased label/wire relation to
  `wire_label_isomorphic`; the spec's required typed `graph_isomorphic` remains
  a distinct, unsatisfied P1 obligation. Plain and root-indexed constant
  wiring are both specified. The generator's output remains `GraphDesc`,
  while `GenerateWork` keeps its workflow output family.
- Simplifications: removed graph node/depth/encoded-size bounds and the
  assumed `graph_fits_bounds`/`graph_complete_bounded` path. The builder's next
  key is derived from its node count. The only runtime limits are occurrence
  allocations for expansion fuel and charge.
- F* check: the same full four-module verification passed after these edits.
- Open proof boundary: the witness carries the pinned bundle but does not
  prove each Work/codec is a member or the unique resolver result. The current
  builder type is not indexed by that bundle and has no erased membership
  argument; the spec now requires both as a proof interface. The current
  wire-label isomorphism does not transport dependent types. Builder start/add
  and completeness remain admitted; `port_context`, `port_env`, `port_ref`,
  and builder laws remain abstract. These are explicit P0/P1/P2 obligations.
- Follow-up: after human review, V2-03 must implement typed resolution and
  descriptor roundtrip; V2-05 must prove committed child-graph substitution.

## V2-03 — Graph codec, resolution, and generation (in progress)

- Outcome: in progress; acceptance is not met. No downstream node has started.
- Scope: graph byte codec, exact pinned resolution, and allocation-aware
  dynamic generation for root and generated descriptors.
- Proven: `WorkflowV2.GraphCodec.fst` round-trips every descriptor and proves
  every accepted byte string canonical, including complete-input rejection.
  `WorkflowV2.ChainProof.fst` constructs a typed chain of input-dependent
  length, proves graph well-formedness for every input, and proves exact
  generator admission for every parent allocation. See the progress records
  below.
- Proven supporting structure: registry lookup returns exact package
  membership; port telescopes are concrete; typed sequence witnesses prove
  prior-edge order; `PairWire` is structural and its type follows from the
  child wires; graph allocation plans align with node order.
- Not proven: executable reconstruction of a typed witness from raw decoded
  syntax. The codec encodes keys, labels, and wires, while the typed witness
  contains erased evidence and arbitrary F* type indices. Exact identity
  lookup does not construct the universal equality between each prior output
  family and the next Work's fixed input type.
- Resolver research: arbitrary `Type0` families have no generic reification
  or equality decision procedure. A Work-pinned handler is sound for graphs
  it accepts, but generic completeness then means handler-resolvable graphs;
  evidence bytes/certificates or a canonical schema language are other routes.
  Deterministic generator replay could reconstruct generated proofs but changes
  the no-regeneration recovery contract. See
  `research/V2-03-resolver-feasibility-2026-10-13.md`.
- An additional independent review recommends a pinned schema language plus
  a small validated equality-certificate extension. This is only a candidate:
  completeness would be relative to that language, not all arbitrary F* type
  equalities. The strict P1/P2 contract remains unchanged pending a decision.
- Current verification: `opam exec -- make -C src/fstar/v2 verify` passes all
  seven modules. This confirms the codec and chain-admission proofs, not P0/P1/P2
  or the generic resolver. Existing builder assumptions/admissions remain in
  `WorkflowV2.Graph.fst`; the chain proof bypasses them.
- Remaining: choose a recovery representation that preserves the intended
  graph expressibility, then implement and prove sound resolution and the
  corresponding completeness theorem. Until then V2-03 stays `in_progress`;
  simplifier and human-review gate remain `not_started`.

### V2-03 progress — exact registry membership and typed ports — 2026-10-13

- `WorkflowV2.Identity.fst`: work/codec resolver results now carry exact
  list-membership evidence and a refinement that the selected package's
  identity equals the lookup key. This proves lookup provenance; it does not
  equate unrelated existential type indices.
- `WorkflowV2.Graph.fst`: replaced assumed port context/reference structure
  with a concrete dependent telescope. Port references are indexed by exact
  telescope shape; `wire_typing_witness` provides typed wire evidence.
  Verified lemmas connect telescope keys to node order and show each typed
  node input references only its prior prefix, giving a concrete DAG rank
  invariant.
- F* check: full six-module `opam exec -- make -C src/fstar/v2 verify`
  passes. Existing warnings 271 and 328 remain. No new `assume`/`admit` was
  added by these changes.
- Still open: no executable resolver constructs `wire_typing_witness` from
  first-order `GraphDesc` syntax. Exact membership and matching identities
  still cannot transport arbitrary hidden `Type0` indices, especially for
  dependent outputs and `PairWire`. V2-03 acceptance remains unmet.

### V2-03 progress — exact witness indexing and structural PairWire — 2026-10-13

- `typed_graph_witness` and `typed_node_sequence` now carry the exact pinned
  registry index. Every node work carries exact membership in that work list;
  plain/indexed constants and pair-family evidence previously carried exact
  codec-list membership. The remaining pair-family evidence has now been
  removed with the codec identity itself.
- Revised `PairWire` to two structural child wires. The F* typing constructor
  derives the dependent pair type from those children. Durable encoding stays
  at the consuming Work boundary: its input codec handles pair inputs, while
  a graph output pair is reconstructed from its durable child sources. This
  removes the impossible requirement to resolve one fixed-environment pair
  codec for every dynamically growing port context.
- Updated `implementation_spec.md` and V2-03 acceptance before source changes;
  the decision and alternatives are in `research/V2-03-pairwire-simplification.md`.
- `WorkflowV2.GraphCodec.fst` now encodes PairWire as a tag followed by its
  two recursive child encodings. Round-trip and accepted-byte canonicality
  still verify. Full six-module F* check passes with warnings 271 and 328.
- Still open: executable typed resolution from first-order graph syntax,
  especially universal `forall env. source_type env == target_input` evidence;
  and a constructed pinned `generator_admission` for a changing-shape graph.
  Existing registry membership, key-refinement, and port proofs do not solve
  those obligations. V2-03 remains `in_progress`.

### V2-03 progress — graph-local edge evidence research — 2026-10-13

- A global producer/consumer compatibility table is insufficient for full
  graph expressibility: a constant input wire can make an indexed output type
  match a consumer at this graph's input even when it does not match for every
  producer input. The concrete counterexample and alternative are in
  `research/V2-03-local-wire-equality-certificates-2026-10-13.md`.
- A graph-local equality-certificate AST could express that edge without
  executing the producer. It is not implemented or verified, and completeness
  would be relative to the certificate calculus unless the API restricts
  `graph_wf` to certified graphs or a more complete proof representation is
  designed. This remains an explicit V2-03 representation decision.
- `generator_admission` now requires membership of the exact
  `GenerateWork generator` in the pinned work registry, in addition to the
  universal graph and allocation-plan contract. `WorkflowV2.ChainProof.fst`
  now constructs a verified admission for the input-shaped chain generator;
  details and the resolver blocker follow below.

### V2-03 progress — verified graph generation admission — 2026-10-13

- Added `WorkflowV2.ChainProof.fst` to the full module check. The example
  builds a typed chain with exactly `x` nodes for every root input `x`, each
  node consuming its predecessor, and outputting the last result (or root for
  the empty chain).
- `chain_typed_graph_witness` constructs the exact typed graph witness;
  `chain_graph_wf` proves all `dag_wf` clauses. `chain_generator_admission`
  proves the required result for every `x` and every parent allocation, and
  includes exact membership for `GenerateWork chain_generator` in the same
  pinned registry as `increment_work`. The allocation plan aligns with the
  graph node order and accounts for zero nested fuel and charge; this example
  therefore fits every parent allocation.
- `TypedNodesSnoc` freshness and `TypedGraphWitness` projection evidence now
  use `squash` packages so erased logical facts can inhabit the F* data
  constructors. These package the same propositions and add no assumptions.
- Root full check passed:
  `opam exec -- make -C src/fstar/v2 verify BUILD_DIR=/tmp/v2-full-clean-21`.
  All seven modules verified, with existing warnings 271 and 328. No new
  `assume` or `admit` was added in `ChainProof.fst` or for generator admission.
- Audit corrected a false scratch result: two earlier scratch inputs declared
  module names different from their filenames, so F* skipped those modules.
  They are not proof evidence. The matching repository module above was
  checked by the full build. The underlying work is captured by the verified
  source, not the scratch claims.
- This closes the concrete generator-admission obligation for the chain
  example only. No executable `resolve_graph` reconstructs typed wires from
  decoded descriptors; the all-environments dependent edge proof and resolver
  completeness remain unmet. V2-03 stays `in_progress`; simplifier and human
  review remain unstarted.

