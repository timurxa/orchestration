# F* v2 node execution summaries

This file preserves historical V2 implementation evidence, S2
specification planning, and A00–C6 schema-plan execution summaries. Those
statuses are frozen history. Current tasks are in
[work_dag.md](../../state/work_dag.md), and the theorem authority is the
[top-down system specification](../../theory/system_spec.md).

Keep one durable summary per stable node ID. The chronological sequence of
starts, finishes, and checks belongs in [run_log.md](run_log.md).

## A00 — Source/build inventory (complete)

- Started/completed: 2026-10-13, after the DAG-policy checkpoint `2a618d4`.
- Scope: inspect all current v2 F* modules and build setup; map source to
  P0–P16 and A00–C6; identify reusable proof structure, admissions, module
  cycles, simplifications, and exact refactor boundaries.
- Integrated artifacts: [source inventory](../research/A00-2026-10-13/source_inventory.md),
  [proof-gap audit](../research/A00-2026-10-13/proof_gap_audit.md),
  [simplification audit](../research/A00-2026-10-13/simplification_audit.md),
  [refactor map](../research/A00-2026-10-13/source_refactor_map.md), and the
  [approach registry](../research/A00-2026-10-13/approach_registry.md).
- Result: all seven current modules passed `opam exec -- gtimeout
  --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify` with F*
  2026.03.24, Z3 4.13.3, and OCaml 5.3.0. Existing `assume`/`admit` trust
  gaps remain, especially generic builder operations/laws in `Graph.fst`;
  successful typechecking does not discharge them. No P0–P16 system theorem
  is complete in current source.
- Decision: split future source by acyclic proof boundaries in the packet;
  preserve useful typed-wire/codec/identity foundations selectively; replace
  the assumed builder with a resolver-aligned constructive implementation;
  keep manifest/package projection canonical and derive any lookup views.
- No F* source changed. A00 was checkpointed under C0.

## C0 — Source audit checkpoint (complete)

- Completed: 2026-10-13. Commit `62b5a5f` (`docs(fstar): complete A00 source audit`)
  records the A00 inventory, independent audits, integrated refactor map,
  theorem-guide status, and synchronized state.
- `git diff --cached --check` passed before commit. The nested research
  gitlink and unrelated untracked build artifacts were excluded.
- Hash recorded before A01 starts. No source code changed.

## A01 — Proof/module boundary (complete)

- Started: 2026-10-13 after C0 artifact commit `62b5a5f` and state-record
  commit `2f0d5d1`; completed: 2026-10-14, commit `34e1021`
  (`docs(fstar): resolve v2 module boundaries`).
- Scope: settle acyclic module ownership, public `.fsti` policy, proof
  implementation split, build order, and trust-audit convention.
- Integrated [module boundary design](../research/A01-2026-10-13/module_boundary_design.md)
  from the import-graph, interface/trust, adversarial, generator-boundary,
  and module-contract reviews under `research/A01-2026-10-13/`.
- Resolved a real A04/A16 cycle without weakening P0: `GeneratorAdmission`
  defines a manifest-indexed package containing one callback and its
  universal law before Bundle; Bundle stores the exact package and derives
  membership from lookup. P0 now preserves exact identity-to-package mapping
  across reload. The DAG orders A03→A05→A06→A07→A15→A16→A04→C1.
- Clarified codec layering: P0 binds law-bearing codec packages; A09 proves
  the graph syntax codec implementation. No duplicated function closure
  equality is required.
- Spec, implementation packet, active DAG, state index, research registry,
  and system overview were synchronized. A01 creates no F* interface stubs.
- No theorem is discharged and no F* source changed in A01. Full baseline
  evidence remains the A00 check; no new verifier run was needed for these
  design edits.

## A02 — Kernel signatures and foundations (complete)

- Started: 2026-10-14, after A01 commit `34e1021`; source and review work
  checkpointed in `edf0b0f` before source edits; completion commit
  `bb4d8ae` (`feat(fstar): complete v2 kernel foundations`).
- Scope: added schema/charge/artifact identities, the specified first-order
  `Ty`/`Value`/`Pred` syntax, typed artifact-token candidate syntax, and
  charge metric fields on budgets, operations, and generator calls. Updated
  legacy generator admission/example call sites to pass the metric.
- Acceptance and evidence: [A02 task brief](../research/A02-2026-10-14/task_brief.md),
  compatibility/signature/adversarial/schema/artifact/code-change reviews in
  the same research directory. Artifact packing remains candidate syntax;
  exact identity/carrier/codec membership must be proved before encoding or
  commit by later P0/P9 layers.
- Full `make -C src/fstar/v2 verify` passes all seven configured modules using
  F* 2026.03.24 and Z3 4.13.3. Kernel adds no `assume`/`admit`; current legacy
  Graph admissions remain and are not theorem evidence. No P0–P16 theorem is
  claimed. A03 is next; C1 remains after schema, allocation, generator-package,
  and P0 work.

## A03 — Canonical manifest core (complete)

- Started: 2026-10-14, after A02 source commit `bb4d8ae`.
- Scope: define first-order manifest/schema entries and canonical encoding;
  prove tagged identity injectivity/uniqueness, duplicate rejection, exact
  cross-reference closure, and first-order projection-shape lemmas. Actual
  package-table projection belongs to A04/P0. Executable closures and proofs
  remain outside journal bytes.
- Root owns source/shared state. Independent reviews research encoding
  alternatives, uniqueness/projection proofs, and adversarial identity/link
  cases. Acceptance brief and evidence are tracked under
  `state/research/A03-2026-10-14/`.
- Integrated reviews select exact canonical bytes as the registry identity,
  shared identity codecs in Kernel, and a first-order tagged manifest whose
  duplicate/link/order/projection predicates are independently explicit.
  Their reports are in the A03 research directory.
- Source submilestone: moved byte framing and existing identity
  encoder/decoder suffix proofs from GraphCodec into Kernel; graph syntax
  codecs remain in GraphCodec. Full seven-module verification passed with
  F* 2026.03.24/Z3 4.13.3, exit 0; see
  `research/A03-2026-10-14/source_migration_verification.md`. This does not
  complete A03's manifest proofs or claim P0.
- A03 kickoff commit: `94e6a62`; verified source submilestone commit:
  `e88e1b8` (`refactor(fstar): centralize v2 identity codecs`).
- Proof design evidence: scratch F* modules verify tagged-sum suffix
  roundtrip/injectivity and insertion-sort sortedness without admissions.
  This does not discharge manifest-specific ordering or uniqueness laws; see
  `research/A03-2026-10-14/proof_feasibility_review.md`.
- Proof/review evidence synchronization commit: `528eeb2`.
- The initial ManifestCore snapshot defined all 12 tagged identity domains,
  typed entry-field validation, closed/tag-checked references, codec/schema
  row coherence, exact framed codecs, duplicate rejection, canonical order,
  decoder rejection of unsupported/noncanonical data, canonical identity
  injectivity, exact lookup uniqueness, and first-order projection equality.
  It also proves sorting count preservation, no-repeat preservation,
  canonicalization idempotence/permutation invariance, and unique sorted
  representatives. This first implementation encodes lexicographic
  non-strict order as `-1/1` because F*'s verified `sortWith_sorted` requires
  a reflexive `bool_of_compare` relation; duplicate IDs reject before this
  order can tie distinct valid entries. This initial sort proof used
  `FStar.Classical`/`FStar.Squash` and is preserved in `38f8e62`; source audit
  traced that helper path to `elim_squash`, so the implementation was replaced
  with a structurally proved insertion sort. The constructive sort passes the
  full eight-module verifier. Independent review found artifact
  reference-codec schema agreement missing; it is now part of canonicality.
  Contract-slot existence/equality is explicitly assigned to A04/P0 and
  schema-AST canonicality to A05. `--report_assumes` is diagnostic only:
  cache-off mode fails at `Prims.admit` even for a trivial lemma, while cached
  mode does not flag the old Classical path. See
  `research/A03-2026-10-14/stdlib_axiom_audit.md` and
  `research/A03-2026-10-14/acceptance_audit.md`.
- Initial manifest proof snapshot and its trust audit are committed as
  `38f8e62` (`feat(fstar): add v2 manifest proof snapshot`). This is a
  preservation commit, not A03 completion; the source passes ordinary
  verification but uses the rejected Classical/Squash sort route.
- Superseding verified source: local insertion sort replaces the
  Classical/Squash path; identity names/labels and durable run/artifact names
  use `identity_token = bytes` (`bytes = list nat` in this abstract kernel).
  Artifact logical-schema/reference-codec-schema agreement is included in
  manifest canonicality, and the manifest-to-registry-identity constructor
  requires canonical data. Schema parsing remains A05; exact contract-slot
  package association remains A04/P0.
- Full final check passed:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a03-final`, F* 2026.03.24,
  Z3 4.13.3, OCaml 5.3.0; all eight modules verified and all VCs discharged.
  Warning 328 remains for the unused recursive graph-codec helper. Three
  independent source/proof reviews and the installed List.Tot helper audit
  found no A03 blocker. The scoped A03 proof path has no project-owned
  admission/unchecked declaration and invokes no admitted helper; this does
  not claim legacy Graph/ChainProof admission freedom. Details:
  `research/A03-2026-10-14/acceptance_audit.md` and
  `stdlib_axiom_audit.md`.
- Completed and committed as `09ed6ea` (`feat(fstar): prove canonical v2
  manifest core`). A03 does not establish P0; A04/A05 obligations remain.

## A05 — Restricted schema syntax and semantics (in progress)

- Started after A03 commit `09ed6ea`. The normative source is implementation
  spec §2.2.1; exact acceptance and boundaries are in
  `research/A05-2026-10-14/task_brief.md`.
- A05 will implement canonical type/value/predicate schema codecs, locally
  nameless scope and substitution laws, exact manifest-indexed denotation, and
  the static legal-environment model consumed by A06/A07. It does not own the
  equality calculus, graph resolver, builder, or executable bundle projection.
- Source ownership is split into `WorkflowV2.SchemaCodec` (wire syntax),
  `WorkflowV2.SchemaScope` (binders and substitution), and
  `WorkflowV2.SchemaSemantics` (package model and contexts), keeping the proof
  units independently reviewable and acyclic.
- Contract review found that `Refine(T,P)` needs a typed candidate binder in
  `P`, parallel to the `Sigma` codomain binder. The spec, A05 contract, A06/A07
  boundaries, and key theorem guide are clarified; no AST constructor or
  universal edge quantifier changed. The resolution and alternatives are in
  `research/A05-2026-10-14/refinement_binder_resolution.md`, committed as
  `b947175` (`docs(fstar): clarify schema refinement binder`).
- Independent reviews recommend a structural suffix parser, a relational
  typed denotation environment, and exact A05/A06/A07 boundaries. A signed
  integer scratch proof verified, but the recursive schema codec and dependent
  semantics remain unimplemented and require root verification. Evidence and
  status are in `research/A05-2026-10-14/approach_registry.md`.
- Start baseline: A03 commit `09ed6ea`; full eight-module verification passed
  under F* 2026.03.24/Z3 4.13.3/OCaml 5.3.0. Three proof-design investigators
  were assigned.
- Current source adds `WorkflowV2.SchemaSemantics.fst` to the Makefile. It
  verifies canonical-manifest family-row selection/uniqueness, AST and exact
  denotation-law extraction, root-indexed constant carriers, and a generic
  full-output-family append kernel. The names/comments explicitly do not claim
  this is yet the AST-linked graph `LegalEnv`.
- Review found that an independent carrier-only context does not prove the
  carrier is the declared `SchemaBound` AST type. The integrated module still
  lacks the required AST-linked context and semantic denotation. A single
  indexed-derivation GADT prototype in `/tmp/WorkflowV2.SchemaSemanticsSingleDerivationProbe.fst`
  verifies a stronger context shape with environment-indexed carrier families
  and Sigma/Refine constructors; this remains scratch pending extension and
  integration. A positive `Bound` regression verifies; malformed Nat/bool
  contexts are rejected in scratch, but no generic soundness/substitution
  theorem is established yet.
- Full configured source command now checks eleven modules:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-semantic-source`.
  Exit 0, all VCs discharged, F* 2026.03.24/Z3 4.13.3/OCaml 5.3.0; the
  existing GraphCodec warning 328 remains. This proves current source
  compiles, not the A05 acceptance contract. The source/Makefile progress
  checkpoint is commit `d8b6f006ecceb37f2de5f2bb50e169a4a8f4ca5b`.
  No downstream node has started.
- The next source checkpoint, `c0696b8f16b0ce1ea74d861e9e534afefe08fd19`,
  removes duplicated family/rule row parsing and adds exact schema-rule
  selection, uniqueness and AST/law extraction. It is a canonical-manifest
  plumbing result, not a denotation or package-link theorem. Full eleven-module
  verification passes after the change; exact command is in `run_log.md`.
- The paired-context scratch uses one `schema_member` to connect an AST slot
  and its carrier; a separate carrier lookup is unnecessary. But
  `/tmp/A05PredicateOracleCounterexample.fst` exposes two remaining soundness
  gaps: caller-chosen `always_true` makes `SchemaFalse` a true refinement, and
  a `JType` judgment can be built under a malformed context without `JCtx`
  well-formedness. A small typed predicate evaluator proves only true/false/
  conjunction, primitive same-kind literal equality and reflexive bound
  equality, plus one bound-substitution case; unsupported forms remain open.
  No scratch semantics is accepted for integration until both gaps close.
- `/tmp/A05ExactDenotationPackage.fst` verifies family/rule package shape
  indexed by the canonical manifest and exact row projections; its law field
  contains a `JType` derivation for every carrier inhabitant. This is
  soundness-only and limited to empty context; user-symbol constructors and
  carrier completeness are absent. P0 must bind the same package object
  returned by its existing lookup. No second A05 package registry is planned.
- Codec exploration now has a complete proof for the existing unframed bytes
  in `/tmp/A05unframed/WorkflowV2/SchemaCodecUnframedTry.fst`: every AST/list
  roundtrip, all-sort injectivity, malformed/non-image and trailing rejection,
  and accepted-byte canonicality. Decision: integrate this route and preserve
  canonical bytes; framed encoding remains scratch-only because it would add
  migration/version obligations. Exact verifier command is in `run_log.md`.

Latest production-context scratch combines dependent Sigma, a `Vec n`
family-shaped field at `Bound 0`, and a subset refinement `{x:nat | x == n}`
whose Kernel AST equality relates `Bound 0` and `Bound 1`. Root's cache-off
run for `/tmp/A05cActualVecRefineProduct.fst` discharged all VCs. It
hardcodes family identity/semantics and does not select the exact package or
codec; it is expressibility evidence only. Root also reran the full
pre-integration source verifier with cache off, split queries, and warning
285 as error: all 13 configured modules pass; existing GraphCodec warning
328 remains. Exact commands and limits are in `run_log.md` and
`research/A05-2026-10-14/typed_jvalue_scratch.md`.

Independent source architecture audit confirms the next integration should
keep `SchemaPackages` as data/lookup, add a denotation/judgment module with
one private canonical package family and exact dependent package reuse, and
export only checked builders/eliminators through an abstract `.fsti`.
Required order: paired context alignment; builtin and dependent constructors;
exact family/rule selection; native subset refinement with proposition-valued
predicates; then full AST soundness. Structural termination, exact AST-derived
family indices, constructor/index-call adequacy, and all-constructor coverage
remain blockers. Details and hazards are recorded in the A05 approach
registry. A05c remains `in_progress`; no downstream node has started.
The synchronized evidence checkpoint is commit `7428189`
(`docs(fstar): record A05c combined shape proof`); its hash is pinned in the
follow-up state-record commit.

## S2-00 — Source and theorem evidence ledger (complete)

- Started and completed: 2026-10-13. Read-only source/evidence audit covered
  all seven current F* modules, P0-P16, normative spec, theorem guide, and
  historical V2 records. Two independent source audits plus root integration.
- Result: [S2-00-evidence-ledger.md](../research/S2-execution-2026-10-13/S2-00-evidence-ledger.md)
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
- Result: [S2-01-graph-resolution.md](../research/S2-execution-2026-10-13/S2-01-graph-resolution.md)
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
- Result: [S2-02-pinned-manifest.md](../research/S2-execution-2026-10-13/S2-02-pinned-manifest.md).
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
- Result: [S2-03-typed-graph-contract.md](../research/S2-execution-2026-10-13/S2-03-typed-graph-contract.md).
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
  Evidence: [S2-04 report](../research/S2-execution-2026-10-13/S2-04-generator-commit.md).
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
  [S2-05-canonical-replay.md](../research/S2-execution-2026-10-13/S2-05-canonical-replay.md).
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
- Result: [S2-06-controller-interleavings.md](../research/S2-execution-2026-10-13/S2-06-controller-interleavings.md).
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
- Result: [S2-07 adapter contract](../research/S2-execution-2026-10-13/S2-07-adapter-contract.md).
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
  [research registry](../research/registry.md).
- S2-07 complete; S2-08 started after its dependencies S2-04, S2-05, and
  S2-07 were complete. No DAG topology or acceptance condition changed.
- No `.fst`/`.fsti` edits, implementation, F* run, or tests.

## S2-08 — Budget and artifact contracts (complete)

- Start/completion: 2026-10-13, after S2-04, S2-05, and S2-07. Scope was P8/P9:
  occurrence-keyed charge/fuel conservation and settlement, plus generic typed
  durable references to files, trees, and other external resources.
- Result: [S2-08-budget-artifact-contracts.md](../research/S2-execution-2026-10-13/S2-08-budget-artifact-contracts.md).
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
- Result: [S2-09-serial-recovery-contract.md](../research/S2-execution-2026-10-13/S2-09-serial-recovery-contract.md).
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
  [S2-10-progress-termination.md](../research/S2-execution-2026-10-13/S2-10-progress-termination.md),
  [frontier audit](../research/S2-execution-2026-10-13/S2-10-frontier-audit.md),
  [rank audit](../research/S2-execution-2026-10-13/S2-10-rank-audit.md), and
  [termination audit](../research/S2-execution-2026-10-13/S2-10-termination-audit.md).
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
- Result: [S2-11-concrete-refinement.md](../research/S2-execution-2026-10-13/S2-11-concrete-refinement.md)
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
- Result: [implementation packet](../retired_guides/implementation_packet.md) now maps the
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
  [research registry](../research/registry.md).
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

## A05 partial milestone — scope and substitution preservation — 2026-10-14

- Added `WorkflowV2.SchemaScope.fst` with locally nameless bound-variable
  scoping for value, predicate, and type syntax. `Sigma` codomains and
  `Refine` predicates each add exactly one nearest-first binder.
- Implemented cutoff lifting and parallel capture-avoiding substitution for
  values, value lists, predicates, and types. Proved lifting preserves scope;
  proved substitution preserves scope using a refinement-indexed substitution
  contract. The proof includes both binder cases.
- Added proof examples for
  `Refine(Nat, Equal(Bound 0, NatLit 3))`, rejection of free `Bound 0`, and
  nested `Sigma`/`Refine` nearest-first indexing and outer-value substitution.
- Added `SchemaScope` to the configured Makefile. Full configured command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-scope-full`.
  Result: exit 0; all nine configured modules verified with all VCs discharged
  under F* 2026.03.24, Z3 4.13.3, and OCaml 5.3.0. Existing warning 328 in
  `GraphCodec.fst` remains.
- No tests were run. This is partial A05 progress, not A05 completion. Still
  open: substitution identity/composition and binder commutation laws; semantic
  denotation preservation; all-constructor schema codec roundtrip, injectivity,
  malformed-input and canonicality proofs; exact package denotation; and
  `LegalEnv`/context laws. No P0–P16 theorem is claimed.
- Commit `0ace03d` (`feat(fstar): prove schema binder scope preservation`)
  contains this coherent partial source milestone and its synchronized status.

## A05 follow-up — substitution algebra and codec foundation — 2026-10-14

- Extended `WorkflowV2.SchemaScope.fst` with pointwise substitution congruence,
  exact identity, composition, and lift/substitution commutation. The laws cover
  value, list, predicate, and type syntax; Sigma codomains and Refine predicates
  use the lifted substitution cases. Function equality/extensionality is not
  assumed.
- Added `WorkflowV2.SchemaCodec.fst` to the Makefile. It defines encoders and
  total fuel-bounded suffix parsers for all current value, predicate, and type
  constructors. Public decoders reject unknown tags, truncation, trailing
  bytes, invalid booleans, negative zero, and any accepted bytes that do not
  exactly re-encode. Argument lists frame their AST item count and guard it by
  available input length.
- Codec proofs currently show accepted-input canonicality and sample suffix /
  roundtrip cases; **generic recursive roundtrip and encoder injectivity are
  still open**. Public re-encoding alone does not establish parser completeness.
- Full configured command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-codec`.
  Result: exit 0; all ten configured modules verified, all VCs discharged;
  F* 2026.03.24, Z3 4.13.3, OCaml 5.3.0. Existing GraphCodec warning 328
  remains. No tests were run.
- A05 remains in progress. Schema denotation/substitution preservation,
  manifest-indexed packages, typed `LegalEnv`/context laws, and generic codec
  roundtrip/injectivity remain required. No P0–P16 theorem is claimed.
- Committed as `1cc76f4` (`feat(fstar): add schema codec and substitution
  laws`); the canonical DAG, state hub, run log, and this summary record the
  checkpoint.

## A05 scratch research — codec framing and relational semantics — 2026-10-14

- Codec work is comparing the committed concatenated-child encoding with a
  scratch version that length-frames each recursive AST child. The framed
  syntax is not integrated. A recursive proof group is being audited for
  genuine constructor/list coverage; a successful cache-off command is not
  accepted as evidence until the exact final file is stable and every branch
  contains a valid proof.
- `/tmp/A05ManifestRel.fst` verifies a relational schema interpreter prototype
  with identity-indexed packages, heterogeneous argument lists, and dependent
  Sigma/Refine denotations. Audit found it is not source-ready: IDs are not
  linked to canonical manifest rows, constructor results were initially
  unconstrained, Bound lookup lacks a typed local context, Root/Port/Constant
  cases and LegalEnv are absent, and no general substitution theorem exists.
- `/tmp/A05ConstructorTyped.fst` verifies a correction: constructor packages
  are indexed by the exact parent family and build values at that family and
  the computed dependent indices. `/tmp/A05SigmaRefineCommute.fst` verifies
  only a closed Sigma/Refine transport example. These are scratch research,
  not integrated proof evidence.
- The accepted direction for `LegalEnv` remains an inductive graph prefix:
  exact root and canonical constants at the base; each prior port is any
  inhabitant of its full declared output family at its reconstructed input.
  It excludes validator postconditions and never narrows external results.
  A05 defines the manifest-indexed semantic interface; A04/P0 binds it to the
  exact pinned bundle rows to avoid an import cycle or second registry source.
- Full source status is unchanged: only the prior ten-module verification
  through `1cc76f4` is current source evidence. No scratch theorem is counted
  toward A05 completion; generic codec laws and integrated semantics remain
  open. Details: `research/A05-2026-10-14/semantic_model_prototype_audit.md`.
- The synchronized research/state documentation checkpoint is committed as
  `2abdf9a` (`docs(fstar): record A05 semantics research`). It contains no
  F* source proof evidence.
- The follow-up synchronization that records this checkpoint is `aa0e076`
  (`docs(fstar): record A05 research checkpoint`).
- Correction to the codec scratch status: the framed recursive proof is not
  verified. On the correctly named dotted module file, F* crashes internally
  when the recursive fuel-equation helper is added; a rewritten helper has an
  unproved postcondition. A module-shaped-path pass did not load the module
  and is invalid. Exact bisection and next directions are in
  `research/A05-2026-10-14/codec_proof_attempts.md`.
- The clean framed scratch base, local child/int/pair results, and one
  fixed-fuel root suffix case do verify cache-off. They do not establish any
  generic recursive roundtrip; source acceptance remains unchanged.
- Correction and synchronized research record committed as `91f3e47`
  (`docs(fstar): correct A05 codec proof status`).
- A verified mutual suffix grammar now covers every Kernel value, predicate,
  and type constructor in scratch. It is not yet connected to encoding or
  executable decoding, so generic codec laws remain open. Exact proof status
  and obligations are in `research/A05-2026-10-14/codec_proof_attempts.md`.
- Synchronized research checkpoint committed as `6e0020c`
  (`docs(fstar): record schema parse grammar approach`).
- Rechecked the unchanged configured source set after the codec research:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-current` exited 0. All ten
  modules verified and all VCs discharged (F* 2026.03.24, Z3 4.13.3, OCaml
  5.3.0); existing GraphCodec warning 328 remains. This does not discharge
  A05's open generic codec or semantics obligations. Evidence checkpoint:
  `4aded38` (`docs(fstar): record current A05 verifier pass`).

## A05 codec source-integration correction — 2026-10-14

- Reproduced the standalone unframed scratch proof, then tried its recursive
  proof block in canonical `src/WorkflowV2.SchemaCodec.fst`. Configured full
  verification failed at the list-count bound with F* Error 19
  (`incomplete quantifiers`). A separate count lemma and generic/specialized
  recursive-list proof variants did not yield a flat-path source proof.
- Nested-path control is not valid module integration: F* resolves the file
  by basename there and warns about implicitly opening namespace `workflowv2`;
  a consumer importing `WorkflowV2.SchemaCodec` fails with `No modules in
  namespace WorkflowV2.SchemaCodec`. The proof body can check standalone, but
  it is not tied to the configured module identity. Flat dotted paths preserve
  imports and expose the recursive-list VC.
- Removed only the unverified source proof block. Re-ran
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-restored-baseline`;
  exit 0, all eleven modules verified, all VCs discharged (F* 2026.03.24,
  Z3 4.13.3, OCaml 5.3.0). This proves the partial tracked baseline still
  checks; it does not prove generic codec laws.
- Current source codec remains unframed and has only checked examples. Scratch
  complete codec laws are not credited to A05 acceptance. Unframed remains
  the design preference, but integration method is unresolved; explore
  flat-path proof refactoring, import/build arrangements, and alternate
  executable-parser proof decompositions before considering a wire-format
  change.
- A05 remains `in_progress`; no A06 or other dependent node has started. DAG
  acceptance is unchanged. Exact analysis is in
  `research/A05-2026-10-14/codec_proof_attempts.md`.


## A05 semantics scratch extension and independent architecture review — 2026-10-14

- Extended `/tmp/A05SoundNucleus.fst` without repository source edits. Added
  Product/Sum/List/Option carrier representations, semantic values/equality,
  pair-value denotation, generic evaluator lemmas for supported value and
  predicate judgments, and `value_typed_sound`. Added a concrete locally
  nameless substitution regression across Product/Sum/Refine/Option/List,
  preserving nearest `Bound 0` while replacing outer `Bound 1`.
- Exact cache-off command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include
  src/fstar/v2/src --include /tmp --odir /tmp/A05SoundNucleusBuild
  /tmp/A05SoundNucleus.fst`. All VCs discharge; imported ulib warning 271
  remains. This is scratch-only and incomplete: List is rejected by
  `type_accepts`; Kernel has no Sum/List/Option value constructors; no general
  carrier-to-AST denotation or acceptance-preservation theorem exists.
- Independent architecture review recommends one carrier-indexed typed
  denotation for types/values/predicates, paired well-formed contexts, exact
  manifest-selected package rules, and a full-family `LegalEnv` prefix
  induction. It flags arbitrary package carriers, unbound package projections,
  unconstrained constructors/index calls, unpaired contexts, indexed constants,
  and arbitrary non-quotable F* values as proof risks. Full staged findings
  are in `research/A05-2026-10-14/semantic_model_prototype_audit.md`.
- This changes no A05 acceptance or dependencies. No semantic scratch result
  is integrated; A05 remains `in_progress` and all dependents remain
  `not_started`.

- Evidence correction and research synchronization committed as `e34c425`
  (`docs(fstar): correct A05 proof integration status`). It changes no F*
  source and records the configured-source codec failure, restored baseline,
  and latest semantics scratch/audit.

## A05 row coherence and codec parser experiment — 2026-10-14

- Added `selected_family_components_from_same_row` in
  `src/WorkflowV2.SchemaSemantics.fst`. From the exact selected family row,
  its syntax field and law field now jointly yield the decoded schema
  expression, exact denotation-law token, and correct row identity. This
  prevents the two projections from silently coming from different rows.
- Ran the configured cache-off verifier:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-live-same-row`. Exit 0; all
  eleven modules verified and all VCs discharged with F* 2026.03.24 / Z3
  4.13.3. Existing GraphCodec warning 328 remains. This theorem is partial:
  it does not bind a token to an executable package or prove the package's
  carrier is the AST's denotation.
- A scratch package theorem in `/tmp/A05PackageVacuity.fst` binds the law
  token to an indexed proof package and proves row-to-package projection.
  F* verifies it, but a package with carrier `False` satisfies the law
  vacuously for any AST. Therefore row/token linkage plus semantic soundness
  is insufficient: structural carrier denotation or an equally strong
  completeness/equivalence law is required. Actual package lookup and
  `LegalEnv` adequacy remain absent; no source edits came from this scratch.
- A separate scratch refactors `SchemaCodec` to a first-order mutually
  recursive value/list decoder without a higher-order parser callback.
  Parser definitions verify, but the all-constructor roundtrip is still
  blocked at opaque recursive-equation VCs. A callback-free parser is a
  promising route, not a verified codec law; wire format remains unframed and
  tracked source still has only checked codec examples.
- A05 remains `in_progress`; no A06 or other dependent work started. Full
  verifier evidence is a partial-source check, not A05 acceptance. Source and
  synchronized DAG/state evidence are preserved in the following commit.
- Source and synchronized DAG/state/research evidence committed as `1f98f8a`
  (`feat(fstar): prove schema row component coherence`). This is an A05
  progress commit, not A05 completion or a DAG checkpoint.


## A05 callback-free value-codec scratch proof — 2026-10-14

- `/tmp/A05StepEq/WorkflowV2.SchemaCodec.fst` verifies generic roundtrip for
  every value AST constructor, including constructor/index-call argument
  lists, using a first-order mutually recursive value/list parser and
  input-derived fuel. It proves suffix preservation and public
  `decode_schema_value (enc_schema_value v) == Some v`.
- Independent re-verification against the repository Kernel and the flat
  dotted module path passed cache-off: both modules verified, all VCs
  discharged (F* 2026.03.24 / Z3 4.13.3). Warning 349 reports a localized
  successful split query. This remains scratch-only.
- The scratch now proves predicate/type suffix and public roundtrips, all
  three encoder-injectivity theorems, and nonempty trailing-suffix rejection
  for each public decoder. Cache-off re-verification with
  `--split_queries always` against project Kernel passes. Source integration,
  full project verification after integration, and all A05 semantics remain
  open. A05 remains `in_progress`, all dependents `not_started`.


## A05 codec integration verified — 2026-10-14

- Integrated the callback-free, fuel-bounded parser and generic codec proofs
  into `src/WorkflowV2.SchemaCodec.fst`. Encoder clauses, wire tags, and
  public codec signatures remain unchanged. Removed callback helper names
  have no tracked F* callers; the low-level fuel meaning changes but no
  in-repo caller relies on the previous budget.
- Proofs cover every Value/Predicate/Type AST constructor: suffix-preserving
  parser roundtrip, public decode/encode roundtrip, encoder injectivity, and
  nonempty trailing-byte rejection. Input-derived fuel sufficiency is proved
  for each AST sort. The changed source has no `assume`/`admit`.
- Full configured command: `opam exec -- gtimeout --signal=TERM
  --kill-after=5s 10m make -C src/fstar/v2 verify
  BUILD_DIR=/tmp/fstar-v2-a05-codec-integrated FSTAR_FLAGS='--cache_off
  --split_queries always --warn_error @285'`. Exit 0; all 11 modules verify,
  all VCs discharged (F* 2026.03.24 / Z3 4.13.3); existing GraphCodec
  warning 328 remains. `git diff --check` passes.
- Source and synchronized state committed as `115fd0bf057f403c32ceeeba57c615b1385de381`
  (`feat(fstar): prove schema codec laws`). This closes A05 codec work only.
  Semantics/package/LegalEnv obligations remain; A05 stays `in_progress`,
  all dependents stay `not_started`.


## A05 codec equality and semantic substitution — 2026-10-14

- Added `schema_plain_codec_encode_injective` and
  `schema_indexed_codec_encode_injective` to
  `WorkflowV2.SchemaSemantics.fst`. At one exact carrier/index, codec
  roundtrip proves encoded-byte equality reflects F* value equality.
- Full configured cache-off command with split queries:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-codec-eq-rerun
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 11 modules verified and all VCs discharged under F* 2026.03.24
  / Z3 4.13.3. Existing GraphCodec warning 328 remains. `git diff --check`
  passes. Source and synchronized evidence are committed as
  `a3fea7abe26af6478c9f4d4b6d2b66154103a814` (`feat(fstar): prove codec
  equality reflection`).
- This is a semantic foundation only. `SchemaEqual` still needs a static
  typed-value derivation proving both operands use the same carrier and exact
  codec/index. Arbitrary carrier-to-observation callbacks are unsound without
  equality reflection; exact codecs provide a possible route.
- Scratch proves the dependent substitution recursion for values,
  predicates, Sigma, and Refine without function extensionality, but current
  carrier-only/schema-AST contexts do not prove that every substituted
  binding inhabits the denotation of its substituted declaration type.
  See `research/A05-2026-10-14/codec_equality_and_typed_substitution.md`.
  A05 remains `in_progress`; no dependents started.

## A05 staged semantic plan and verified source baseline — 2026-10-14

- Split A05 into canonical subnodes A05a–A05f plus an integration rollup to
  expose proof dependencies: verified syntax codecs/scope (A05a), exact
  package interfaces (A05b), canonical denotation and typed judgments
  (A05c), package adequacy (A05d), semantic weakening/substitution (A05e),
  and universal `LegalEnv` prefixes (A05f). Only A05a is complete; A05b is
  active; all later stages and A06 remain not started.
- This ordering removes a proof dependency cycle: package interfaces must be
  available to state judgments, but package adequacy is only meaningful after
  those judgments are defined. The package interface is selected by exact
  schema owner identity; the law token is a checked projection field, not a
  package lookup key. A04/P0 later proves that the Bundle returns that same
  package object and preserves selection across reload.
- Independent reviews reject caller-chosen interpretation witnesses,
  arbitrary predicate oracles, carrier-only contexts, function
  extensionality, and vacuous soundness-only package laws. They agree on a
  canonical hidden-constructor interpretation, exact typed telescopes,
  paired context well-formedness, and inductive full-family `LegalEnv`.
  Detailed findings, the package/signature representation decision, and its
  remaining proof conditions are in
  `research/A05-2026-10-14/semantic_architecture_checkpoint.md`.
- Baseline verifier after the DAG split:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-stage-baseline
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 11 modules and VCs passed under F* 2026.03.24 / Z3 4.13.3.
  Existing GraphCodec warning 328 remains. This verifies current source only;
  no semantic judgment or A05 completion is claimed.
- DAG/state documentation is synchronized before A05b source work. No A06 or
  other dependent work has started.

## A05b package-interface source increment — 2026-10-14 (in progress)

- Added `WorkflowV2.SchemaPackages.fst` to the configured module set. The
  first source interface defines exact family/rule owner-row projections,
  a dependent argument telescope indexed by AST arity, family and
  Constructor/IndexCall packages, finite first-order equation declarations,
  and one exact manifest-indexed package map. The telescope's carrier types
  remain paired with AST domains for A05c/A05d; equal arity is not claimed as
  typed compatibility.
- Each schema package's indexed codec is one exact object with membership in
  the shared `global_codec_registry`. Its codec identity is projected from
  that object; no duplicate codec identity field is added. P0 must bind that
  shared registry to canonical manifest codec rows. `SchemaAtom` matches only
  a nullary package; `SchemaFamily` requires matching arity, including zero
  indices. Constructor interpretation helper obtains the parent only via
  `packages.family_at`, and returns the selected parent with its result.
- Independent reviews confirmed A05b→A05c→A05d remains acyclic. They
  identified and preserved the remaining proof obligations: per-binder
  AST/carrier typing, Constructor result-index denotation, IndexCall equation
  adequacy, codec/schema row coherence, and proof of actual package laws.
  These belong to A05c/A05d/P0; no token-only meaning or manifest-format
  change is accepted. Reviews also confirmed that the parent helper's exact
  lookup path is the one semantic consumers must use.
- Full configured cache-off command after source changes:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05b-codec-membership-final
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 12 modules verified and all VCs discharged under F* 2026.03.24
  / Z3 4.13.3. Existing GraphCodec warning 328 remains. This is interface
  verification, not A05b completion or semantic theorem evidence.
- No dependent node has started. A05b remains `in_progress`; A05c–A05f,
  A05 integration, and A06 remain `not_started`. Verified source increment
  commit: `e70c0ce01dfb8006c6386cb39a559023bd99d547`
  (`feat(fstar): define schema package interface`).

## A05b complete; A05c started — 2026-10-14

- Closed A05b as the exact base package-data interface after the full
  12-module cache-off verifier and independent source/proof-boundary audits.
  Source checkpoint `e70c0ce01dfb8006c6386cb39a559023bd99d547`; follow-up
  state-record commit `b639283` recorded the checkpoint hash.
- Review confirmed that exact owner-row/token projection, codec-registry
  membership, AST matcher predicates, and the parent lookup helper establish
  package structure and identity, but not denotation. The token is not a law:
  the base source does not prove binder-to-carrier agreement, constructor
  result-index agreement, index-call result/equation soundness, or
  codec/schema adequacy.
- Resolved the boundary without a cycle: A05c defines canonical interpretation
  and typed judgments over the exact base map, enforcing exact matchers and
  map lookup. Judgment soundness depending on package semantics is conditional
  on A05d. A05d must build `AdequateSchemaPackages`, indexed by the same exact
  map, with checked binder/result/equation/codec laws. A04/P0 and all later
  semantic consumers use only that wrapper; the manifest token is an identity
  projection, never evidence. The review and alternatives are recorded in
  [`package_law_boundary_review.md`](../research/A05-2026-10-14/package_law_boundary_review.md).
- Updated `implementation_spec.md`, the A05 rows in the canonical DAG, A05
  task brief, and approach registry before A05c source work. No `.fst` code
  changed in this design resolution; no theorem was added or weakened.
- The specification/DAG/state boundary revision is committed as
  `28e23f348997380177bb5a6a9e40ebe933276125`
  (`docs(fstar): close schema package interface stage`).
- A05c design began with independent scratch explorations. One candidate
  `JArgTelescope` is an indexed inductive over AST argument declarations,
  actual syntax arguments, a prefix substitution, and carrier telescopes.
  F* scratch hit a universe/GADT refinement problem; no complete typed
  relation has verified yet. Exact parent lookup and nullary Atom must be
  enforced at interpretation. Details are in the approach registry and
  ongoing scratch artifact; source integration and a full verifier run remain
  required.

## A05c verified argument-telescope increment — 2026-10-14

- Added `src/WorkflowV2.SchemaJudgments.fst` and placed it after
  `SchemaPackages` in the v2 module build. Its argument derivation tracks the
  exact dependent carrier telescope and an explicit `schema_arguments_denote`
  tuple. Each argument's AST type is substituted by prior actual syntax
  arguments before the value-judgment premise; the tail carrier is selected by
  the preceding actual F* value. The example checks the refinement binder
  shift and a two-argument dependent telescope.
- Added exact `family_at`/`rule_at` selected-package helpers that reject a
  failed AST matcher, and a nullary-Atom consequence. These consume the exact
  selected base-map object; they do not prove package semantic adequacy.
- Full cache-off verification passed using F* 2026.03.24 / Z3 4.13.3:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05c-args-indexed-4
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 13 modules verified and all VCs discharged. Existing warning
  328 in `GraphCodec.nodes_decode_encoding` remains.
- This is not canonical `JValue`: the relation is still a parameter, and the
  example instantiates it with `unit`. There is no complete canonical type,
  value, predicate interpreter or paired context. This is verified scaffolding
  only; A05c remains `in_progress`, and A05d–A05f and all dependents remain
  `not_started`.
- No DAG or theorem acceptance changed. Full dependent-context and AST work
  continues in scratch with independent proof exploration. In particular,
  `/tmp/A05JArgsParam.fst` verifies a concrete context-indexed `JValue` for
  NatLit and Bound(0), a total value projection, and dependent argument-tuple
  construction; its context lookup is carrier-only and does not prove
  AST-binder/carrier adequacy. `/tmp/fstar-a05c-universe/ContextJValue.fst`
  verifies a minimal paired newest-first AST/dependent-value context and
  `SchemaBound 0`/`SchemaBound 1` for `vec 4`/`nat`, with a small structural
  Nat/Vec type relation. It does not cover all schema packages or AST nodes.
  `/tmp/A05SchemaArgValues.fst` verifies a GADT tuple-spine alternative, but
  converting that GADT back to the package's `dtuple2` alias fails; adopting
  it would change package interfaces. The chosen integrated form indexes by
  the exact `dtuple2` and avoids extraction. `/tmp/fstar-a05c-universe/BoundSyntax.fst`
  independently verifies dependent carrier lookup. The source and
  synchronized state are committed in one source checkpoint; the hash is
  `9ba432b` (`feat(fstar): add schema argument judgment scaffold`).

## A05c paired-context scratch extension — 2026-10-14

- Extended scratch `/tmp/fstar-a05c-universe/ContextJValue.fst` verifies a
  paired newest-first syntax/runtime lookup, with an indexed `vec 4` newest
  binding and its earlier `nat` binding. It verifies a small structural type
  relation for unit/bool/nat/int/product/sum/list/option and indexed Vec, plus
  value rules for bound/unit/bool/nat/int/product.
- The root agent independently reran the cache-off proof after the scratch
  extension; `WorkflowV2.Kernel` and `ContextJValue` both verified, all VCs
  discharged. Command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include src
  --include /tmp/fstar-a05c-universe --odir /tmp/fstar-a05c-universe
  src/WorkflowV2.Kernel.fst /tmp/fstar-a05c-universe/ContextJValue.fst`.
- This remains scratch only. Paired lookup does not establish AST/carrier
  agreement for every context declaration. Sigma/Refine, predicates,
  package-selected family/rule judgments, root/port/constants, and
  sum/list/option value rules remain absent. No acceptance condition changed;
  A05c remains `in_progress`, with all dependents `not_started`.

## A05c declaration-witness context scratch — 2026-10-14

- `/tmp/fstar-a05c-universe/ContextJValuePaired.fst` verifies a paired
  context whose declarations retain prior-prefix `j_type` and value evidence.
  Its same-index lookup returns both the declaration-prefix type witness and
  a full-context runtime `j_bound`; the example selects earlier `4 : nat`
  beneath a newest `Vec 4` declaration.
- `/tmp/fstar-a05c-paired-context/ContextSigma.fst` separately verifies the
  specialized `Sigma Nat (Vec Bound(0))` carrier
  `dtuple2 nat (fun n -> vec n)` and typed context lookups. The Sigma and Vec
  rules are specific to this example.
- Both cache-off commands passed under F* 2026.03.24; exact commands:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include
  src/fstar/v2/src --include /tmp/fstar-a05c-universe --odir
  /tmp/fstar-a05c-universe /tmp/fstar-a05c-universe/ContextJValuePaired.fst`
  and `opam exec -- fstar.exe --cache_off --warn_error @285 --include src
  --include /tmp/fstar-a05c-paired-context --odir
  /tmp/fstar-a05c-paired-context src/WorkflowV2.Kernel.fst
  /tmp/fstar-a05c-paired-context/ContextJValue.fst
  /tmp/fstar-a05c-paired-context/ContextSigma.fst`.
- Neither proves general context weakening/substitution: a dependent
  declaration's type evidence is at its prefix. General weakening remains
  A05e. No package-selected families/rules, predicates, external symbols, or
  full AST relation follow. No A05c acceptance/status changed.

## A05c evidence-type boundary and recursive Sigma scratch — in progress

- Independent source review found that the integrated argument relation did
  not have the context parameter claimed by its comment and returned `Type0`.
  Corrected the comment and moved its result sort to `Type`; the example is
  explicitly typed there. This remains a parameterized placeholder, not a
  canonical context-indexed judgment.
- Full configured verifier passed with cache disabled:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05c-proof-sort-final
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 13 modules verified and all VCs discharged. Existing
  GraphCodec warning 328 remains.
- Scratch `/tmp/fstar-a05c-generic/SigmaRecursiveDtuple.fst` verifies
  structurally recursive `j_type`/`j_value : ... -> Tot Type` for Nat and
  dependent Sigma. The Sigma carrier is existing `dtuple2`; the codomain is
  typed under the domain binder and extended runtime environment. This is not
  integrated, and omits full context well-formedness/weakening, predicates,
  refinements, package-selected families/rules, roots/ports/constants, and
  full AST coverage. Exact command and source are in the A05c scratch note.
- Rejected: an inductive judgment constructor with a quantified recursive
  premise for the Sigma codomain fails F* universe checking, even without
  context extension and with either `dtuple2` or a custom carrier. The
  obstacle is the quantified recursive inductive premise, not the carrier.
  A `Type0` derivation datatype cannot be used directly as a logical
  proposition or subset predicate. `Refine` needs proposition-valued
  `PredDenote`, with a sound bridge from typed-value evidence.
- No acceptance or dependency changed. A05c remains `in_progress`; downstream
  nodes remain `not_started`. The source refinement and synchronized status
  are in commit `8c0dcc7` (`feat(fstar): clarify A05c judgment evidence
  boundary`).

## A05c canonical interpretation and predicate architecture exploration — 2026-10-14

- A05c remains `in_progress`; no dependent node started. The source still has
  only the verified argument-telescope scaffold, not canonical denotation or
  the three judgments.
- Direct recursive `TypeDenote : AST -> Tot Type0` did not safely support
  dependent Sigma JValue elimination: recursive projections remained opaque,
  and reconstructing the `noeq` codomain witness is not justified by equality
  or function extensionality. Select a representation that returns one sealed
  canonical package containing `(carrier, shape witness)`; `TypeDenote` is
  its carrier projection, and judgments consume that exact package once.
  Constructors must be hidden so callers cannot pick another carrier.
- Verified Nat/Sigma/VecBound0 fragment: root reran
  `/tmp/A05cCanonicalVecWitness.fst` with
  `opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285
  --odir /tmp /tmp/A05cCanonicalVecWitness.fst`; exit 0, all VCs discharged.
  The exact canonical `WSigma` witness types `Mkdtuple2 n xs` at
  `dtuple2 nat (vec)`, with no function extensionality. This is hardcoded
  scratch, not full AST/context/package semantics. Native dependent pairs and
  `dtuple2` are not definitionally identical; verified explicit conversions
  do not make them interchangeable in a GADT index.
- Predicate evidence alternative: root reran
  `/tmp/A05PredicateEvidenceGADTVerified.fst` with cache off, importing the
  actual Kernel; exit 0, all VCs discharged (only stdlib warning 271).
  `PTrue`/`PEqual`/`PAnd` form Type-valued evidence, EqualWitness fixes one
  exact carrier for both typed operands, and `PredDenote` applies one outer
  `squash`. Nat equality and conjunction construct without admissions or
  `Classical.exists_intro`; no conjunction of separately truncated proofs is
  required. This fragment uses native equality only; it does not yet consume
  the exact manifest-selected codec or prove codec equality reflection, as
  required by the A05c acceptance contract.
- Open proof boundary: using a direct recursive TypeDenote projection for
  native `SchemaRefine` still fails with Error 12: opaque projected
  `type_denote` is not definitionally the native subset, even for exact Nat
  equality. The canonical package route is consistent with eliminating the
  same witness, but its Refine case remains unverified. Full typed context,
  weakening/substitution, package-selected family/rule denotations, shared
  carrier equality construction, soundness, and every Kernel AST constructor
  remain open. Do not call A05c complete.
- DAG/state were clarified before future A05c source changes to require exact
  package reuse and to record the proposition-valued predicate route. The
  full source verifier also passed at this checkpoint: F* 2026.03.24, Z3
  4.13.3; all 13 configured modules verified and all VCs discharged. Exact
  command is in `run_log.md`. This confirms existing source only, not the new
  scratch architecture or A05c acceptance. Research/state checkpoint commit:
  `d8a3f4f` (`docs(fstar): record A05c canonical witness route`).

## A05c canonical package and interface evidence — 2026-10-14

- Settled the invariant: a single sealed package indexed by the exact
  AST/context controls carrier and shape, and every judgment consumes that
  same package. A duplicate independent carrier and equality proof is
  disallowed. The selected integration route is dependent existential
  `a:Type0 & shape rho t a`: the witness is indexed by the exact carrier.
  Direct recursive `TypeDenote` remains rejected.
- `/tmp/A05cShape.fsti/.fst` plus `/tmp/A05cShapeClient.fst` verifies a
  constructor-hidden API on a toy context/AST. It covers a `dtuple2 nat vec`
  Sigma carrier and native `x:nat{x == 7}` refinement. Explicit public value
  builders and JValue helpers let the separate client use opaque carriers.
  Both cache-off commands pass all VCs; exact commands are in `run_log.md`
  and `research/A05-2026-10-14/typed_jvalue_scratch.md`.
- Independent interface scratch verifies abstract package type families
  backed by private noeq records/GADTs and confirms that values at hidden
  carriers need explicit builders, carrier laws, or eliminators. An unindexed
  `eqtype` handle is too weak. The dependent existential package is verified
  with production `SchemaSemantics.hlist` for Nat/Sigma and an isolated
  `.fsti` client. A second actual-context fragment verifies generic `JPair`
  and `SchemaRefine ... SchemaTrue`; its isolated client constructs and
  eliminates both. Keep the internal JValue GADT private and expose an
  abstract `Type u#1` family via a `let` alias. Export smart carrier builders
  because raw values cannot be typed at the opaque carrier in client code.
  An earlier package constrained to the smaller universe hit a universe
  error; the successful existential package family is `Type u#1` and its
  carrier is `Type0`. A toy shape-only API also works,
  but a Kernel-AST Refine attempt over a locally modeled dependent `hlist`
  fails to expose the native subset carrier during introduction. The
  production-context generic JPredicate proof remains open; the
  dependent-existential interface covers `SchemaTrue`, while a separate
  specialized evaluator proves one bound-equality refinement in a dependent
  Sigma.
- The real Kernel AST package fragment `/tmp/TestCanon.fsti/.fst` also passes
  with `schema_type_expr` as its package index, but only for Nat. The complete
  dependent context telescope, all AST cases, package-selected denotation,
  equality reflection through the manifest codec, and general predicate
  soundness remain open. The `SchemaBound 0` member-path scratch is same-index
  lookup only; it is not yet a lookup from one runtime environment object.
- A separate manifest-selected package proof verifies canonical codec
  injectivity at one shared exact schema package/index: equality of encoded
  bytes implies equality of values by the selected codec's roundtrip law.
  This does not prove that arbitrary independently selected judgments infer
  that shared package, nor AST semantic quotation/adequacy. A05c's equality
  rule must existentially select one package/index and use it for both value
  derivations and the codec; two independent package existentials are not
  sufficient.
- Kernel-AST/local-context shape-only trial
  `/tmp/A05CanonicalPackageRefine2.fst` fails before the JValue proof:
  `subset_intro` cannot establish that the projected
  `package_carrier HNil refine7_package` reduces to the native subset (F*
  Error 189). Its `hlist` is locally modeled, not imported from
  `SchemaSemantics`; do not describe this as a completed production-context
  test. Record it as a rejected current encoding attempt, not as evidence
  against Refine or the one-package invariant. The production-context
  dependent-existential interface now verifies Nat/Sigma/True-Refine, while
  specialized production-context dependent Vec and nontrivial Refine
  fragments are separately verified without package linkage.
- A05c remains `in_progress`, with no dependency/status changes. Existing
  source full verification still passes as recorded earlier; no new project
  source was added. The dependent-existential implementation and client
  passed separate cache-off runs under F* 2026.03.24; exact commands are in
  `run_log.md` and `typed_jvalue_scratch.md`. Research/state checkpoints now
  include `4252024`; the current representation result is pending a follow-up
  state commit.

## A05c dependent package against production context — 2026-10-14

- `/tmp/a05actual-interface/A05ActualContext.fst` imports the production
  `WorkflowV2.SchemaSemantics.hlist`. It defines a shape indexed by AST,
  context, and carrier, and a dependent package
  `package rho t = a:Type0 & shape rho t a`. The package carries no second
  carrier/equality pair: the witness itself is typed at the selected carrier.
- The interface and implementation verify cache-off with all VCs:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include src/fstar/v2/src --odir /tmp/a05actual-interface \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    /tmp/a05actual-interface/A05ActualContext.fsti \
    /tmp/a05actual-interface/A05ActualContext.fst
  ```

  It proves package builders for Nat and `Sigma Nat Nat`, pair construction,
  first projection, and its correctness lemma. A separate client directory
  containing only the `.fsti` also verifies all VCs:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include src/fstar/v2/src --include /tmp/a05actual-client \
    --odir /tmp/a05actual-client \
    /tmp/a05actual-client/Client.fst
  ```

- Root independently reran both commands successfully under F* 2026.03.24.
  This selects the dependent-existential representation for integration, but
  does not yet cover a context-dependent Sigma codomain through its sealed
  interface, package-selected family/rule packages, or general JValue. A
  separate local-context and later production-context Kernel-AST fragment
  verify a Sigma codomain `SchemaFamily fid [SchemaBound 0]` at `vec n`. The
  production-context fragment hardcodes the family interpretation and lacks
  the abstract interface and package-selected codec proof.
- The earlier universe error was not a general failure of carrier-indexed
  witnesses. It came from constraining the package record to a smaller
  universe; the successful package family is `Type u#1` and the carrier is
  `Type0`. Preserve this sort boundary in source.
- A later extension `A05ActualJValue` passed the abstract boundary by keeping
  `shape` and the inductive JValue private. The exported `package_jvalue` is a
  `val ... -> Type u#1`, implemented as a `let` alias to the private
  constructor-indexed evidence. Its `.fsti` exports smart carrier builders,
  Sigma/True-Refine value constructors and eliminators, and a projection
  lemma. Root reran the interface/implementation and isolated-client
  commands; all VCs discharged. Directly exposing the GADT as abstract `val`
  fails Error 197. Raw pair/Nat result indices fail against the opaque carrier;
  client builders must refer to exact public carrier constructors.
- This sealed actual-context interface covers Nat, `Sigma Nat Nat`, and
  `SchemaRefine Nat SchemaTrue`. A separate production-context scratch
  instantiates the dependent `SchemaBound 0` Vec codomain, but does not use
  `schema_family_package` or the hidden interface. General predicate
  semantics and all AST constructors remain open.
- A05c remains active; no project source or dependent node changed. Research
  checkpoint `4252024` records the preceding evidence; this representation
  selection and verifier evidence will be recorded in the next state commit.

## A05c production-context dependent refinement evidence — 2026-10-14

- `/tmp/A05cActualContextExists.fst` imports the production `hlist` and
  verifies a dependent Sigma whose second component is the subset
  `{x:nat | x == n}`. The schema AST refinement compares `SchemaBound 0` and
  `SchemaBound 1`, relating the candidate to an outer value. Its specialized
  evaluator proves that a value in the selected dependent carrier makes the
  schema predicate evaluate to `Some true`.
- Root independently reran the cache-off command; all production dependencies
  and the scratch module verified, with all VCs discharged. Exact command and
  limits are in `run_log.md` and `typed_jvalue_scratch.md`.
- This establishes production-context expressibility for one nontrivial
  dependent refinement and one AST evaluator fragment. It does not establish
  generic `JPredicate`, package-selected equality codec reflection, or the
  all-constructor JValue soundness theorem. A05c remains `in_progress`; no
  project source or downstream node changed.

## A05c production-context dependent family codomain — 2026-10-14

- `/tmp/A05cActualVecSigma.fst` verifies a Sigma whose codomain AST is
  `SchemaFamily family_id [SchemaBound 0]` and whose carrier is
  `dtuple2 nat (fun n -> vec n)`. Its JValue derivation checks the second
  component under `HCons n rho` at `vec n`, using the production Kernel and
  `SchemaSemantics.hlist`.
- Root reran the cache-off verifier successfully; all VCs discharged. The
  scratch hardcodes `family_id` and the `vec` interpretation. It does not
  select the manifest-indexed family package, prove its indexed codec is
  used, or establish package adequacy. See exact command in `run_log.md` and
  full scratch in `typed_jvalue_scratch.md`.
- The context-dependent Vec case is proven as a specialized shape/JValue
  scratch; it remains an open package-backed interface and semantic-soundness
  obligation. A05c remains active; no source or downstream node changed.

## A05c shared-package codec-reflecting equality — 2026-10-14

- `/tmp/A05PredicateProbe.fst` proves plain and indexed value equality from
  canonical encoded-byte equality when both values share the same package
  carrier (and, for indexed codecs, one exact index). The selected codec is
  required to be a member of the production shared codec registry. Root
  independently verified the cache-off scratch with all VCs discharged.
- The equality proof itself is sound, but its codec record is not yet tied to
  an AST-derived `schema_family_package` and index. A newer helper proves
  reflection with the exact family package's own `family_codec` and passes
  the same package selected by `family_at` through one continuation. The
  generic JPredicate equality rule must still derive that exact package and
  argument index from the AST, then share it across both operands. Separate
  package existentials cannot justify cross-carrier equality.
- This is scratch evidence only. A05c remains `in_progress`; no F* source or
  downstream node changed. Exact verifier command and proof boundary are in
  `run_log.md` and `research/A05-2026-10-14/typed_jvalue_scratch.md`.
- Synchronized evidence checkpoint: `c42b948`.

## A05c exact selected family codec reflection — 2026-10-14

- `/tmp/A05cFamilyPackageCodec.fst` proves indexed equality reflection using
  the exact codec field from one `schema_family_package`, at that package's
  exact argument index. It also packages a `family_at` lookup around one
  continuation so both operand derivations can share the same dependent
  package witness.
- Root independently verified all production dependencies plus this scratch
  with cache off and split queries; all VCs discharged. Exact command and
  limitations are in `run_log.md` and `typed_jvalue_scratch.md`.
- This resolves the codec source selection for the reflection helper, not the
  AST integration: `SchemaFamily id args` still must produce the exact
  package/index and one shared existential for both equality operands. No
  canonical JPredicate or source theorem is complete; A05c remains active.
- Synchronized research checkpoint: `6cee517`.

## A05c positivity-safe refinement and binder-alignment probes — 2026-10-14

- The naive mutual evidence encoding was rejected by F* strict positivity
  when `JPredicate` determined the native `Refine` carrier and itself
  recursively contained `JValue`. `/tmp/A05cBuiltinRefineCore.fst` separates
  proposition-valued predicate denotation from the evidence GADTs and
  verifies an actual-Kernel fragment with production `hlist`, indexed
  `JValue`, `JPredicate`, product, and `SchemaRefine ... SchemaTrue`. Root
  reran it cache-off/split-queries; all seven modules and VCs passed. It is
  architecture evidence only: no generic predicate, equality, context typing,
  exact package interpretation, or soundness theorem.
- `/tmp/A05cFamilyTelescopeLaw.fst` verifies a recursive family signature law
  and derives a one-argument index `Mkdtuple2 n ()` from `SchemaBound 0` in a
  production `hlist`. Root reran it cache-off; all nine modules and VCs
  passed (SchemaCodec emitted existing Warning 349). This supports the A05d
  package-level binder/carrier alignment contract. A05c must construct
  call-specific derivations internally and share the exact package/index
  across interpretation and codec; there is no per-use proof obligation.
  The scratch does not instantiate a complete manifest-selected package or
  adequate-package record.
- A separate direct-index attempt fails because the schema argument's
  derived carrier cannot be unified with the dependent package telescope
  without the alignment witness. The existing A05d contract resolves this
  boundary; no DAG dependency change is required. Generic predicate
  soundness is now proven for Nat literal equality and conjunction in
  `/tmp/A05cPredicateMutual.fst`, including explicit native subset
  introduction and actual registry-member codec reflection. Root reran the
  scratch cache-off and all seven modules/VCs passed. This remains a hardcoded
  Nat evaluator and does not establish generic AST/context/package soundness.
  No source module changed and A05c remains `in_progress`.
- Full commands, outputs, and limits are in
  `research/A05-2026-10-14/typed_jvalue_scratch.md` and the matching run-log
  entry. This is not a source acceptance or A05c completion checkpoint.
- Synchronized research-state commit: `e21a9f2` (`docs(fstar): record A05c
  positivity and binder laws`).


### Import-order correction and exact-package judgment-shape probe

The preceding positivity/binder-alignment entry's statement that no DAG
dependency change was needed is superseded. A05c cannot import A05d's
alignment proof because A05d depends on A05c. The canonical DAG now has an
acyclic split: A05c declares alignment-law interfaces for family, constructor,
and index-call signatures; A05d's exact-map adequacy wrapper carries their
proof-bearing fields; A05e proves semantic substitution; A05g derives closed
call-site judgments; A05f proves `LegalEnv` using that closure. The wrapper
fields are contracts proved once for the pinned map. Raw package data and
contract tokens alone do not imply them. This preserves the universal edge
theorem and adds no per-use author evidence.

Root independently verified `/tmp/A05cExactFamilyAlignment.fst` cache-off
with split queries. It imports the actual package map and judgment modules,
selects the exact family package via the production AST matcher, indexes the
result by that package's canonical denotation, and constructs the Nat
`SchemaBound 0` argument at the exact dependent telescope carrier under a
production `hlist` Sigma context. Its `JFamily` constructor still requires a
`schema_argument_derivation`, so this validates the judgment shape and exact
package identity but does not prove automatic argument derivation. A05g owns
that closure, and must also cover constructor and index-call package
signatures. No project source changed; A05c remains `in_progress`.

- Synchronized DAG/proof-boundary correction committed as `3d11410`
  (`docs(fstar): correct schema adequacy proof order`).


### Constructor index and codec-schema contract audit

A second independent audit found two concrete laws that must be explicit in
A05d/A05g. `schema_constructor_package.constructor_build` returns a value at
`constructor_parent_indices parent args`, while the AST result type uses the
first-order `constructor_result_indices`. The current raw package fields do not
prove that evaluating those AST indices under a valid argument tuple yields
the callback's dependent index. A05d must carry this semantic equality, and
A05g must consume it before constructing the `JValue` result. Otherwise a
constructor callback could inhabit a different family index from its AST.

Also, indexed codec membership proves registry object identity and the codec
roundtrip proves encode/decode for its own carrier; neither ties the manifest
codec input/output schema projections to the package telescope and result
carriers. The exact adequate wrapper must carry/prove that coherence for
family and index-call codecs (and applicable parent family codec use). This is
consistent with the implementation spec's checked codec/index coherence
fields; no raw-field derivation is claimed. The DAG acceptance conditions now
state these obligations. No project F* source changed; A05c remains active.

- The result-index and codec-schema coherence clarification is committed as
  `cec8cd6` (`docs(fstar): specify schema result coherence laws`).

## A05c exact-package family-type rule — 2026-10-14

Integrated `schema_family_type_judgment` into
`WorkflowV2.SchemaJudgments.fst`. Its only constructor ties a `SchemaFamily`
AST to the exact package returned by `select_family_for_type`, one dependent
argument tuple, an argument derivation at the package's declared telescope,
and the carrier `package.family_denotation indices`. The same selected
package carries the codec. A first full build exposed a missing explicit
constructor binder (Error 72); rebinding all datatype parameters fixed it.

Full configured cache-off/split-query verification passed all 13 modules and
all VCs with F* 2026.03.24. Existing GraphCodec Warning 328 remains. Exact
command/output are in the matching `run_log.md` entry. This is only a
conditional family judgment: `jvalue` remains a parameterized placeholder,
arguments are not automatically derived, and no generic context, predicate,
Root/Port/Constant, constructor/index-call, completeness, or soundness theorem
is closed. No `admit`/`assume` was introduced. A05c remains `in_progress`.

- Source/evidence commit: `202ab1e` (`feat(fstar): add exact package family judgment`).

## A05c paired-context lookup scratch — 2026-10-14

Root independently verified `/tmp/A05cContextLookup.fst` cache-off with
production Kernel and SchemaSemantics imports. The fragment ties `Bound n` to
an exact carrier-list member/value, includes a base record for Root/Port/
Constant, handles Pair, and has equality/and evidence at a shared carrier.
Exact command is in `run_log.md`; all VCs discharged. This remains a fragment:
the base record chooses arbitrary port/constant carriers and values, so it
does not prove graph edge compatibility, root-schema agreement, codec
membership/decode, or pinned constant resolution. It also lacks JType-linked
context declarations, Sigma/Refine, package-selected calls, and a generic
soundness theorem.

An unverified design sketch is to make contexts a GADT whose extension stores
the declaration AST, carrier, actual value, and `JType` proof at the prior
prefix. Then Bound lookup would return that exact declaration/carrier/value
triple. The mutual context/JType/JValue/JPredicate positivity and termination
proof remains open. No project source changed; A05c remains `in_progress`.
Execution is paused at the user's request after this safe, synchronized
scratch-evidence checkpoint. State-only pause commit: `750cb33`.
