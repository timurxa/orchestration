# F* v2 run log

Append entries in chronological order. Do not replace earlier outcomes; add a
correction entry if evidence changes. Entries before the redesign pivot record
the former schema-centered plan and are historical. Current design and task
status are in [system_spec.md](../../theory/system_spec.md) and
[work_dag.md](../../state/work_dag.md).

## A00 started — 2026-10-13

- Began the read-only source/build inventory. Three independent assignments
  cover source/build mapping, adversarial theorem/trust gaps, and architecture
  simplification. Their reports and approach registry are under
  `research/A00-2026-10-13/`.
- No F* implementation edits. Verifier baseline pending; A00 remains
  `in_progress`, C0 remains `not_started`.
- The prior DAG policy is committed as `2a618d4` so execution begins from a
  recoverable canonical plan.

## A00 completed; C0 started — 2026-10-13

- Completed the module-by-module source/build map, P0–P16 gap audit, and
  simplification comparison. Root integrated them into
  `research/A00-2026-10-13/source_refactor_map.md`; an independent adversarial
  pass caught and resolved the A15/A16 milestone mapping and a resolver-layer
  mismatch in the proposed proof experiment.
- Baseline command: `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m
  make -C src/fstar/v2 verify`. Exit 0: all seven modules verified.
  Environment: F* 2026.03.24, Z3 4.13.3, OCaml 5.3.0. This typechecks the
  existing source but does not close its explicit `assume`/`admit` boundaries.
- The source audit worker first tried the Makefile outside `opam exec`, where
  `fstar.exe` was absent from PATH. Root reran it through opam successfully;
  the inventory records the successful full command and result.
- No F* source changed. A00 is `complete`; C0 is `in_progress` for the scoped
  audit commit. A01 remains unstarted until the commit hash is recorded.

## C0 completed — 2026-10-13

- Scoped A00 checkpoint commit: `62b5a5f` (`docs(fstar): complete A00 source
  audit`). It contains all four A00 research artifacts and synchronized status
  records. `git diff --cached --check` passed before the commit.
- The hash is recorded in this log and `node_summaries.md` before A01 begins.
  No F* source changed. A01 remains `not_started` pending this state commit.

## A01 started — 2026-10-13

- C0 hash `62b5a5f` is recorded in the canonical DAG and node summary;
  state-record commit `2f0d5d1` closed C0 before this A01 start.
- Assigned three independent read-only audits: module import graph/ownership,
  `.fsti` contract and trust semantics, and adversarial minimality/cycle review.
  Their task brief and approach registry are under
  `research/A01-2026-10-13/`.
- A01 will produce `module_boundary_design.md`. No F* source changed; no theorem
  is claimed here.

## Autonomous execution and commit checkpoints added — 2026-10-13

- Revised the planned A00–H5 DAG to A00–C6. Former human-review gates are
  nonblocking commit checkpoints; future execution proceeds without waiting
  for review.
- Added scoped commits after the source audit, identity/API contract, typed
  graph, replay, provenance/durability, schedule-safety/progress, and final
  integrated proof milestones. The graph syntax codec now starts after the
  identity/API checkpoint so its work cannot overlap that commit.
- Added a rule to commit completed serial work when safe and to join parallel
  work before committing shared changes. Checkpoints reuse existing scoped
  commits instead of creating empty commits; preserve coherent old artifacts
  before a substantial redesign when safe. Each commit hash must be recorded
  in the node summary and run log.
- Added an autonomous ambiguity policy: research and resolve issues while the
  project intention and theorem strength remain intact; revise the DAG and
  state before affected dependents proceed; isolate only irreducible decisions
  and continue independent work.
- Synchronized the active-plan descriptions in `state.md`,
  `node_summaries.md`, `research/registry.md`,
  `system_overview_and_reading_guide.md`, and `implementation_packet.md`.
- This is a planning/state update only. No A00–C6 node started, no F* code or
  proofs changed, and no verifier or tests were run.

## PairWire boundary correction — 2026-10-13

- Clarified the earlier PairWire decision wording: the Work input codec handles
  a pair passed into a node; the graph codec encodes descriptor syntax only.
  A graph output pair is reassembled from durable root, constant, and node
  output sources. No graph-output value codec is implied.
- This corrects the wording in the earlier PairWire revision entry below;
  source/spec semantics are unchanged by this clarification.

## Graph-specific type-equality evidence — 2026-10-13

- Independent audit showed that producer/consumer compatibility rows requiring
  `forall input. output_family input == consumer_input` reject valid graph
  edges whose exact input wire fixes the producer input (for example,
  `Prime 0` from a constant-zero input). The graph-local certificate proposal
  is recorded in `research/V2-03-local-wire-equality-certificates-2026-10-13.md`.
- The proposal is not implemented or verified. It adds syntax, checker
  soundness, builder evidence, and canonical persistence, and may restrict
  completeness to certificates expressible in its calculus. No design choice
  or V2-03 acceptance has been silently changed.

## Pin generator admission to the registry — 2026-10-13

- Strengthened `generator_admission` in `WorkflowV2.Graph.fst` to carry exact
  `PackedWork (GenerateWork generator)` membership in the bundle's work
  registry, alongside its all-input/allocation graph and plan validity proof.
  This prevents an admission record for an unregistered callback from being
  treated as pinned.
- `opam exec -- make -C src/fstar/v2 verify` passed all six current modules;
  warnings 271 and 328 remain. The declaration adds no `assume` or `admit`.
- Still no concrete admission value; the input-shaped chain is being extended
  with a typed DAG witness and a universally quantified admission proof.

## V2-03 PairWire design revision — 2026-10-13

- Independent source review found `PairWireTyping` constructs a dependent pair
  directly from its recursively typed child wires; it never calls the
  registered family codec. That codec is indexed by one exact port-environment
  type, which cannot be reused for arbitrary dynamically generated prefix
  shapes.
- Revised the implementation spec and V2-03 acceptance: `PairWire` is now a
  structural pair with no codec identity. The consuming Work's input codec or
  graph output codec remains the durable encoding boundary. This removes a
  redundant registry lookup and avoids a separate source of truth; an adapter
  library may still provide pair codecs where useful.
- Added `research/V2-03-pairwire-simplification.md` with alternatives and
  proof effects. The revision does not solve universal prior-output/work-input
  type compatibility; V2-03 remains `in_progress`.
- Next: update the executable syntax codec and typing constructors, then run
  the full F* verifier. No dependent DAG node has started.

## V2-03 structural PairWire implementation — 2026-10-13

- Removed `pair_family_ref` and the codec identity field from `PairWire` in
  `WorkflowV2.Kernel.fst`. Updated `wire_typing_witness` and `pair_wiring` to
  infer the dependent pair from their exact child witnesses.
- Updated `WorkflowV2.GraphCodec.fst`: tag 3 now precedes two self-delimiting
  child encodings; decoder still requires complete input and public decode
  still accepts only exact re-encodings.
- Full `opam exec -- make -C src/fstar/v2 verify` passes all six modules.
  This includes graph descriptor round-trip and accepted-byte canonicality
  under the revised pair syntax. Warnings 271 and 328 remain unchanged.
- PairWire resolution is no longer a V2-03 requirement. General work/codec
  carrier transport and pointwise input-edge compatibility remain open, as
  does constructing `generator_admission` for the dynamic example.

## Initialization — 2026-10-12

- Moved the normative specification to `src/fstar/v2/implementation_spec.md`.
- Created the state hub, initial work DAG, summary ledger, and run log.
- Searched the available skill catalog and repository for a dedicated F*
  proof-writing skill; none was present. V2-00 is specification analysis, so
  no F* source-writing skill was needed for this node.
- No F* checks or tests were run.

## V2-00 started — 2026-10-12

- Status: in progress.
- Scope: inventory specification definitions, premises, P0–P14 targets,
  dependencies, and ambiguities.
- Stop condition: complete V2-00, set V2-HUMAN to `awaiting_human`, and end the
  turn before V2-01.

## V2-00 completed — 2026-10-12

- Recorded the specification-to-proof and theorem dependency maps in
  `node_summaries.md`.
- Marked V2-00 complete and V2-HUMAN `awaiting_human` in `work_dag.md`.
- Identified the v1 heading/schematic-declaration wording as a versioning issue
  to resolve before V2-01 relies on the moved file as a v2 contract.
- No `.fst`/`.fsti` declarations, proof checks, or tests were produced; V2-01
  remains unstarted.

## V2-00 reopened — 2026-10-12

- User asked to retry; `fstar-proof-work` is now available and was read.
- DAG revision: V2-00 now includes a minimal typed-kernel `.fst` module and
  typechecking, so the review gate follows both the theorem inventory and API
  declarations. V2-01 now covers pinned identity/codec laws and event/action
  vocabulary. No `.fsti` files are in scope.
- The previous inventory result is retained. V2-00 is `in_progress` and
  V2-HUMAN reset to `not_started`; V2-01 remains `not_started`.
- F* 2026.03.24 is available through `opam exec -- fstar.exe`; Z3 4.15.4 is
  installed. The V2-00 F* verification is pending.
- Verification attempt 1: `opam exec -- make -C src/fstar/v2 verify` failed on
  an implicit `assume new` warning for the abstract graph type and unbound
  helper type parameters. No proof escape hatch was added; both issues are
  being fixed in the typed declaration.
- Verification attempt 2: `opam exec -- make -C src/fstar/v2 verify` passed:
  `All verification conditions discharged successfully` (F* 2026.03.24, Z3
  4.15.4).

## V2-00 completed after scope revision — 2026-10-12

- Added `src/WorkflowV2/Kernel.fst` with dependent local, external, and graph
  generator work declarations, typed references/packages, and codec laws.
- Added the `verify` target in `src/fstar/v2/Makefile`; full module checking
  passed. No `.fsti`, `assume`, or `admit` was introduced.
- Marked V2-00 `complete` and V2-HUMAN `awaiting_human`. V2-01 and all later
  nodes remain unstarted.

## DAG update — 2026-10-12

- Re-read the updated `fstar-proof-work` skill. It now additionally calls for
  small focused modules, brief comments explaining proof structure, and
  examples for likely specification loopholes when implementing proofs.
- User approved the V2-00 result; marked V2-HUMAN `complete`. V2-01 is ready
  but has not been started.
- Added V2-HUMAN-02 after V2-02. Routed both direct dependents, V2-03 and
  V2-05, through this gate; all other descendants remain blocked transitively.
- No F* source or proof work was performed for this DAG-only change.

## V2-01 started — 2026-10-12

- Status: in progress.
- Scope: pinned identity/ref resolution, codec/work-reference consistency,
  P0, and abstract journal/action vocabulary.
- Independent investigations are recorded in `research/registry.md`; workers
  are read-only with respect to implementation files.
- No V2-02 work has started. It remains dependent on V2-01 completion.

## V2-01 declaration phase completed — 2026-10-12

- Added structural identity comparators and soundness lemmas, a derived
  `work_package`, heterogeneous exact resolvers for work and codecs,
  same-snapshot identity evidence, and canonical codec-decode lemmas in
  `WorkflowV2.Identity.fst`.
- Added first-order event/action vocabulary in `WorkflowV2.Journal.fst`.
  This vocabulary is not yet a transition system and grants no action
  authorization.
- The identity audits found that registry uniqueness is still a proof field,
  not derived from a concrete registry constructor, and same-snapshot F* data
  does not prove host reload across restarts. These are recorded as P0/V2-11
  obligations; no top-level P0 theorem is assumed.
- Marked V2-01 `complete` for the requested top-down declaration phase only.
  This does not claim full P0 discharge.

## V2-02 started — 2026-10-12

- Status: in progress.
- Scope: finite typed DAG semantics, first-order dependent wires, minimal
  start/add/finish builder, explicit `dag_wf`, and P1 theorem interfaces.
- Independent graph-design and adversarial reports were integrated. The
  source representation was revised to use explicit wire-typing evidence and
  a typed topological node-sequence witness. An unnecessary constraint that
  topological order equal numeric key order was removed.
- Independent post-edit audit identified remaining port laws, registry
  membership, and typed-isomorphism obligations; see
  `research/V2-02-implementation-review.md`.

## V2-02 declaration phase completed — 2026-10-12

- Added `WorkflowV2.Graph.fst`: first-order finite DAG, topological ordering,
  raw structural isomorphism, dependent wire typing, builder surface,
  typed-node sequence, and theorem interfaces for soundness/completeness.
- An intermediate strict F* check found syntax/type issues during drafting;
  these were corrected. Final check:
  `opam exec -- make -C src/fstar/v2 verify` passed for Kernel, Identity,
  Graph, and Journal with `--cache_off` and warning 285 fatal.
- The check confirms declaration/type correctness for non-admitted obligations.
  It does not discharge the admitted P1 theorems or validate assumed port and
  builder contracts. `node_summaries.md` names every open assumption/admission
  and its owning proof node.
- To align DAG status with the user's explicit top-down WIP phase, the V2-01
  and V2-02 acceptance rows now mean “interfaces and named holes ready for
  review,” not “P0/P1 fully proved.” This status clarification does not weaken
  the normative P0/P1 obligations in `implementation_spec.md`.
- Marked V2-02 `complete` for this review milestone and V2-HUMAN-02
  `awaiting_human`. **Stopped here.** V2-03 and every other node behind the
  human gate remain `not_started`.

## V2-01/V2-02 reopened — 2026-10-12

- User-directed revision: remove the unused per-work registry wrapper and
  proof-unhelpful helpers; remove graph-size bounds; remove generic captures;
  prefer `GraphDesc` for runtime generation; and minimize duplicated durable
  facts. Per the DAG protocol, V2-01 and V2-02 were reopened and the
  V2-HUMAN-02 gate reset before downstream work.
- Independent review evidence already in `research/registry.md` and
  `research/V2-01-02-adversarial.md` was revisited. The selected design removes
  captures for all node kinds because per-run settings belong in typed input
  and fixed definitions/configuration belong to pinned identities. The
  generator returns `GraphDesc`; its child graph provides the occurrence's
  indexed result.

## V2-01 simplified interface completed — 2026-10-12

- Removed `local`/`external`/`generate` wrapper functions and the duplicate
  `work_ref`/`work_package` layer. Each `Work` derives exactly one
  `durable_work_ref`; the pinned heterogeneous registry remains to resolve that
  durable label. `CallKey` is the node occurrence, `CallIntent` stores only
  resume data in addition to that key, and graph parent, request, operation,
  input, and charge reservation are derived from committed state. Added the
  root input codec identity to `RunStarted` so root bytes have a decoding law.
- Updated the normative spec and DAG acceptance conditions. P0 remains open:
  uniqueness, exact registry membership, and restart identity resolution are
  proof targets rather than checked outcomes.

## V2-02 simplified graph interface completed — 2026-10-12

- Removed `is_typed_dag`, the definitional `graph_sound` wrapper, and one-use
  optionality helpers. `dag_wf` and `graph_wf` carry the pinned registry
  bundle; the witness still lacks proof of exact registry membership. Renamed
  the current erased-label relation `wire_label_isomorphic` so it is not
  confused with the typed isomorphism P1 requires.
- Added indexed-constant wiring to the normative API contract. Removed
  `graph_fits_bounds` and `graph_complete_bounded`; graph expressibility is
  unbounded over finite DAGs, while runtime expansion fuel and charge come from
  one occurrence allocation plan.
- Simplified journal fields to remove derivable parent, occurrence, operation,
  request, and reservation duplicates. External reply behavior remains
  nondeterministic; only actual validated output bytes are committed.
- Verification: `opam exec -- make -C src/fstar/v2 verify` passed for all four
  modules (Kernel, Identity, Graph, Journal) with F* cache disabled and
  warning 285 fatal. This checks declarations and non-admitted obligations;
  it does not close P0/P1/P2 or runtime proof gaps.
- Marked revised V2-01 and V2-02 complete for the declaration review milestone
  and reset V2-HUMAN-02 to `awaiting_human`. V2-03 and all descendants remain
  `not_started`; execution stops here for human review.

## Final simplification audit — 2026-10-12

- Independent source/spec audits found the generator `GraphDesc` split,
  allocation accounting, removal of captures and graph-size bounds, and
  derivation of journal facts consistent across the current source and spec.
- Removed the unused `event_identity` field. `(event_run, event_sequence)` is
  the unique event identity, avoiding a second independently supplied key.
- Corrected the pinned-bundle comment and made the missing registry-ID to
  exact-manifest relation explicit in the spec and P0. The current F* bundle
  declaration still lacks that proof, so P0 remains open; host reload and
  build-to-extracted-code refinement remain separate obligations.
- Marked prior research reports as historical where they describe superseded
  source shapes. Current decisions remain in the simplification record and
  implementation spec.
- Final verification after the journal-field and identity-comment edits:
  `opam exec -- make -C src/fstar/v2 verify` passed for Kernel, Identity,
  Graph, and Journal with cache disabled and warning 285 fatal.
- V2-HUMAN-02 remains `awaiting_human`; no downstream DAG node was started.

## DAG revision — graph codec implementation and simplification review

- User resumed through V2-HUMAN-02 and directed work through V2-03, a
  dedicated simplification pass, then a human-review stop.
- Added V2-03-SIMPLIFY after V2-03 and V2-HUMAN-03 after the simplifier.
  Routed V2-04, V2-05, and V2-08 through V2-HUMAN-03; all their descendants
  remain blocked transitively until review.
- Expanded V2-03 acceptance to require actual graph work round-trip and
  canonical encode/decode proofs, exact typed resolution of work/codecs from
  the pinned manifest, and root/generated graph support. Merely declaring a
  graph codec with laws is insufficient.
- Marked V2-HUMAN-02 complete, V2-03 `in_progress`, and all new downstream
  nodes `not_started`. V2-03 research brief is in
  `research/V2-03-brief.md`.

## V2-03 started — 2026-10-12

- Three independent investigations are assigned: graph codec/canonicality,
  registry and dependent typed resolution, and generator/allocation proof
  obligations. Root owns source edits and integration.
- No implementation change has yet been made for V2-03. Existing F* graph
  codec laws and resolver lemmas are starting interfaces only; acceptance
  requires a concrete bridge and discharged proofs.

## V2-03 investigation and codec draft — 2026-10-12

- Independent codec, typed-resolution, generation, and adversarial reviews
  completed. Results are in the `V2-03-*.md` research files. They support one
  fixed structural format over unbounded `list nat`, followed by a separate
  resolver, using the same path for root and generated graphs.
- Added `V2-03-schema-bridge.md`: exact dependent typed resolution needs a
  unique manifest-owned schema selection and builder membership; current
  codec implementation identities alone cannot transport arbitrary
  existential Type0 indices. This is implementable with additional contracts,
  but current source declarations do not establish them.
- A draft `WorkflowV2.GraphCodec.fst` now encodes/parses all graph syntax and
  rejects malformed/trailing input. Strict isolated verification fails at
  `wire_depth_fits`; the draft round-trip and canonicality lemmas are not
  verified. It has no `assume`/`admit` and is not integrated into the build.
- Existing four-module project verification still passes. This is baseline
  only; V2-03 stays `in_progress`, and V2-03-SIMPLIFY remains `not_started`
  until all graph-codec, exact resolution, and generation acceptance criteria
  are met.

## V2-03 implementation progress — 2026-10-12

- Integrated the structural graph codec and proved descriptor round-trip and
  accepted-byte exact canonicality. Its parser rejects unknown tags,
  truncation, and trailing input; the format uses length-prefixed variable
  fields and unbounded `list nat` bytes. PairWire encodes its family codec ID.
- Added a concrete input-shaped chain generator and graph-local plan. Proved
  backward edge ranks, changing graph size, matching ordered plan keys,
  unique generated keys, exact work lookup in the example registry, and the
  full local allocation-plan accounting theorem.
- Simplified `GraphAllocationPlan`: entries now align with `GraphDesc.nodes`
  in order. Validation and both resource folds consume node/plan pairs in one
  pass. Updated `implementation_spec.md` before relying on this representation.
- Verification: `opam exec -- make -C src/fstar/v2 verify` passes all six
  modules. One attempted Unicode-bound adjustment was rejected by F*'s
  `FStar.Char.char_code` refinement, which itself excludes `0xd7ff`; restored
  the decoder to the exact library domain and documented that boundary.
- Resolver investigation: an independent closed-schema prototype verifies
  recursive resolution for a homogeneous Nat registry, including dependent
  output families and prior-node ports. It does not establish the current
  source's arbitrary heterogeneous resolver, PairWire family transport,
  descriptor-to-package membership, or the manifest identity relation.
- V2-03 remains `in_progress`; the strict typed-resolution and generator
  admission criteria are unmet. Simplifier and human-review nodes remain
  `not_started` by DAG dependency.
- Sharpened V2-03 acceptance to require an executable manifest-backed resolver
  with soundness and builder completeness; the schema/type bridge is an
  implementation route that must be proved, not only declared. Expanded the
  later simplifier node to review ordered-plan alignment and codec/resolver
  alternatives. The DAG remains acyclic and its human gate still depends on
  that simplifier.

## V2-03 typed-port and exact-membership progress — 2026-10-13

- Replaced assumed port context/reference representations in
  `WorkflowV2.Graph.fst` with a concrete telescope indexed by prior node keys
  and environment-dependent output families. Port references now prove
  membership in their exact telescope shape.
- Added verified proofs that typed wiring references only existing prior
  ports, telescope key order matches descriptor-node order, and every node's
  incoming edges target its strict prefix.
- Strengthened work/codec lookup in `WorkflowV2.Identity.fst`: successful
  results carry exact registry-list membership and a refinement proving the
  selected package identity equals the requested key.
- Full six-module F* verification passes. This does not close dependent type
  transport from descriptor syntax; identity equality still cannot prove
  equality of opaque existential types or indexed families. V2-03 remains
  `in_progress`; no downstream node started.

## V2-03 graph generation proof — 2026-10-13

- Added `WorkflowV2.ChainProof.fst` to the ordered F* build and constructed a
  typed proof for the `chain_generator`: input `x` emits `x` local nodes, a
  typed topological witness, a valid node-aligned allocation plan, and the
  declared output wire. `chain_generator_admission` quantifies over every
  input and every parent allocation and proves graph well-formedness plus
  allocation validity. Admission includes exact registry membership for the
  generator itself.
- To make erased propositions usable as constructor evidence, changed
  `TypedNodesSnoc` freshness and `TypedGraphWitness` projection fields to
  `squash` packages. Their underlying propositions are unchanged; no
  assumption/admit was added.
- F* initially exposed missing concrete lemmas hidden by prior scratch
  verification claims. Audit found those scratch files declared module names
  that did not match their filenames; the compiler skipped the proof modules.
  Marked their claimed proof results invalid and verified the matching source
  module instead. Several new induction facts and explicit existential witness
  construction were proved in `ChainProof.fst`.
- Full check passed with a clean build directory:
  `opam exec -- make -C src/fstar/v2 verify BUILD_DIR=/tmp/v2-full-clean-21`.
  Seven modules verified; warnings 271 and 328 are unchanged.
- V2-03 is still `in_progress`: no executable `resolve_graph` reconstructs a
  typed witness from decoded graph syntax, and universal dependent edge typing
  remains open. The syntax codec and this concrete generator admission do not
  meet the full V2-03 acceptance. V2-03-SIMPLIFY and V2-HUMAN-03 remain
  `not_started`.

## V2-03 resolver feasibility audit — 2026-10-13

- Root and two independent audits compared raw syntax resolution, a
  Work-pinned resolver, schema expressions, explicit edge evidence, and pure
  generator replay. The result is recorded in
  `research/V2-03-resolver-feasibility-2026-10-13.md`.
- Current descriptor bytes preserve work/codec identities, node keys, and wire
  syntax. Exact registry lookup proves package membership, while
  `typed_node_sequence` contains erased `Type0` indices and universal input
  typing proofs. No function in the present interface reconstructs the latter
  from the former; arbitrary `Type0` equality has no generic runtime reifier.
- A pure Work-pinned input resolver is constructive and needs no per-edge
  evidence bytes when the pinned manifest includes the handler. It proves
  completeness for graphs accepted by that resolver, not for every graph
  admitted by the current existential `graph_wf`. A graph-level registry
  wrapper avoids the Kernel/Identity/Graph cycle but must bind handler code to
  exact Work identity in the manifest.
- Alternatives are: extensible canonical schema language, canonical edge
  proof evidence, resolver-certified graph well-formedness, deterministic pure
  generator replay (which changes recovery contract), or a general proof
  reification/checker layer. No option was silently selected because each
  changes the completeness boundary or the representation.
- Full source check rerun:
  `opam exec -- make -C src/fstar/v2 verify`. All seven modules verified;
  warnings 271 and 328 remain. This verifies the graph syntax codec and chain
  admission, not the absent generic resolver. Existing builder admissions and
  assumptions in `WorkflowV2.Graph.fst` remain outside the chain proof.
- DAG remains unchanged: V2-03 `in_progress`; V2-03-SIMPLIFY and
  V2-HUMAN-03 `not_started`. A resolution/completeness design decision remains
  before V2-03 acceptance can be met.

## V2-03 resolver candidate synthesis — 2026-10-13

- A third independent review compared durable edge certificates, pinned schema
  expressions, and Work-specific resolvers. It recommends a schema-plus-small
  validated-certificate hybrid, with resolver callbacks allowed only under
  the same proved contract.
- This preserves graph topology and dependent types representable by the
  chosen schema/certificate language. It still does not recover arbitrary
  erased F* equality; completeness must name the supported language unless a
  general proof checker is built.
- Recorded candidate and theorem sketch in
  `research/V2-03-resolver-feasibility-2026-10-13.md`. No normative spec or
  F* source changed. No option selected; DAG status remains unchanged.


## S2 specification and planning-DAG revision — 2026-10-13

- Updated ../implementation_spec.md to define the abstract system around a
  serial journaler, concurrent independent local/generator execution, and a
  multi-inflight keyed adapter. Adapter resume now requires stable-key
  deduplication/status lookup or operation-specific idempotence/reconciliation.
- Formalized universal all-legal-environment dependent edge typing, pinned
  GraphResolver boundary, replay-WF versus ghost SemWF, expected-head
  reauthorization, ReadyInputAgreement, bounded claims, and arbitrary legal
  completion order.
- Added P15 abstract executor interleaving safety and P16 recovered semantic
  graph correctness. Kept P13 concrete runtime refinement and P10 storage
  prefix durability distinct.
- Replaced active work_dag.md with S2 spec-only planning DAG. Copied prior
  V2 implementation DAG unchanged to legacy_v2_work_dag.md and preserved its
  V2-03 in_progress and dependent statuses as paused history.
- Updated state.md and node_summaries.md to identify active S2 planning and
  historical V2 execution evidence. Stored independent audits under
  research/spec_refresh_2026-10-13 and recorded them in research/registry.md.
- No S2 node started or executed. No V2 implementation DAG node executed.
  No .fst/.fsti file changed. No F* verification or tests run.
- Remaining design gate: S2-01/S2-03 must settle the constructive graph
  resolver and exact completeness boundary without weakening universal edge
  typing. Current specification explicitly bars proof bytes and runtime
  observations; arbitrary erased Type0 equality is not presumed reifiable.

## S2 concurrency and theorem-spine clarification — 2026-10-13

- Clarified the adapter interface: each submission accepts one committed
  `CallIntent`; the workflow may submit additional distinct intents while
  earlier calls remain unfinished. Outcomes remain keyed and may arrive in
  any order. Journal append remains one-at-a-time.
- Added the P0-P16 theorem-spine diagram to the implementation spec and synced
  `key_correctness_theorems.md`: P15 is abstract all-interleaving safety,
  P16 is every-cut recovered semantic graph correctness, and P13 is concrete
  refinement. Corrected the concrete-refinement diagram edge and stated
  recovery provenance as ghost `SemWF` over an authorized history prefix.
- Removed circular theorem dependencies by separating graph/local/external
  transition correctness from aggregate ledger conservation: P4/P6/P7 no
  longer require P8; P8 composes P3/P4/P7.
- Updated the active S2 DAG and state wording to match the one-intent-per-
  submission adapter contract. All S2 nodes remain `not_started`.
- No DAG node was executed; no `.fst`/`.fsti` file changed; no F* check or
  tests were run.

## S2-00 started — 2026-10-13

- User authorized execution of the canonical S2 DAG.
- Marked S2-00 `in_progress`; every other S2 node remains `not_started`.
- Scope: build source/theorem evidence ledger for P0-P16, including current
  source declarations/proofs, contract targets, open admissions, and host
  refinement boundaries. Parallel read-only audits assigned to three workers.
- No F* source edit or verification; no later S2 node started.

## S2-00 completed — 2026-10-13

- Integrated P0-P16 source/evidence classifications in
  `research/S2-execution-2026-10-13/S2-00-evidence-ledger.md`. Reviewed seven
  F* modules, implementation spec, theorem guide, and prior state history.
- Independent graph/identity, executor/journal/durability, and theorem-map
  audits were synthesized; a separate DAG/source reviewer checked references
  and flagged the ReadyInputAgreement proof gap. Root verified corrections
  against source.
- Reconciled obvious theorem-table contradiction: P9 is optional for base
  semantic recovery and required only for persistent backing-object identity;
  P16 includes P10. Updated implementation spec and theorem guide, including
  stale line references. DAG structure and dependencies unchanged.
- S2-00 acceptance met: every P0-P16 target has source/spec evidence and a
  truthful status. No target is claimed proved end-to-end; historical full
  builds are not presented as current runs or proof of admitted statements.
- Marked S2-00 `complete`; S2-01 is now ready. No S2-01 work started.
- No `.fst`/`.fsti` changes, implementation, F* verifier command, or tests.

## S2-01 started — 2026-10-13

- S2-00 is complete; its evidence ledger is the prerequisite artifact.
- Started representation research across four routes: typed constructor AST,
  schema/type-expression checker, proof reflection, and pinned GraphResolver.
- Acceptance holds fixed universal all-environment edge typing, no runtime
  output observation, no serialized per-edge proofs, and one graph language
  shared by builder and decoder/recovery.
- Three read-only independent design investigations assigned. No F* source or
  verifier work; no later S2 node started.

## S2-01 completed; S2-02/S2-03 started — 2026-10-13

- S2-01 integrated three independent route investigations and an independent
  adversarial review. Selected a canonical manifest type/value schema
  calculus with one registry-pinned resolver shared by builder and recovery.
- Fixed P1/P2 completeness to the explicit `SchemaSupported` language. This
  is not arbitrary erased F* `Type0` completeness; unsupported schemas are
  rejected visibly and symmetrically. No edge-proof bytes are serialized.
- Clarified the generated-graph boundary: the exact input to a committed pure
  generator may itself come from an external outcome, but P4 admission proves
  schema validity for every legal input/allocation. Internal graph ports
  remain universal; observed outputs cannot repair a static edge. A stronger
  external-validator postcondition must be pinned and proved.
- Updated §2.2.1, P1 expressibility, open-representation work, and the key
  correctness theorem guide. S2-01 acceptance met; DAG dependencies and
  structure are unchanged.
- Started S2-02 and S2-03 in parallel because each depends only on completed
  S2-01. Independent manifest/codec and graph typing investigations are
  underway.
- No F* source edits, implementation, verifier command, or tests.


## S2-02 and S2-03 complete; S2-04 started — 2026-10-13

- Completed S2-02 at specification-contract level. The canonical bundle
  projection, bidirectional identity coherence, identity-level uniqueness,
  codec canonicality, root-entry linkage, abstract reload, and acyclic
  manifest/resolver boundary are recorded in
  [S2-02-pinned-manifest.md](../research/S2-execution-2026-10-13/S2-02-pinned-manifest.md).
  Independent P0 review passed. No F* source or verification changed.
- Completed S2-03 at specification-contract level. The normative spec now
  defines the schema AST interpretation and judgments, inductive legal
  environments, exact root/constant/refinement assumptions, `PrefixSupported`,
  builder characterization, resolver/codec targets, and typed isomorphism.
  Evidence is in [S2-03-typed-graph-contract.md](../research/S2-execution-2026-10-13/S2-03-typed-graph-contract.md).
- S2-03 resolved a conflict with the original S2-01 note: graph typing ranges
  over the full declared external output family and does not narrow via a
  validator postcondition. This follows the stricter requirement that edge
  equality come from types and static graph facts alone. The S2-01 report has
  a dated amendment; no DAG dependencies or node scope changed.
- Updated the theorem guide and S2-00 evidence links to match the normative
  spec. No F* files changed, verifier or tests ran, and no proof target is
  claimed discharged.
- S2-04 is now the only ready node. Its start is recorded here after S2-02 and
  S2-03 completion; S2-05 remains not_started because it depends on S2-04.

## S2-04 completed; S2-05 started — 2026-10-13

- Completed S2-04 at specification-contract level. The normative spec now
  states exact generator admission for every input/allocation, graph-local
  plan validity and deterministic occurrence lifting, append authorization,
  typed global-DAG splice, child visibility only after commit, and recovery
  without generator replay. The evidence and boundaries are in
  `research/S2-execution-2026-10-13/S2-04-generator-commit.md`.
- Independent review confirmed P4/P5 acceptance coverage and caught the
  zero-fuel `(G,W)` rank counterexample. Replaced it with natural
  lexicographic `(G,U,W)`: positive-fuel commits lower `G`; zero-fuel commits
  have no child generators and lower `U`; ordinary completion and adapter
  transitions lower `W`. Generic proof predicates remain implementation
  obligations; no theorem is claimed proved here.
- No DAG structure or acceptance condition changed. Marked S2-04 complete and
  started S2-05, whose prerequisites are now all complete.
- S2-05 scope: define canonical journal/replay state, event transitions,
  expected-head append, structural `WF`, ghost `SemWF`, terminal state, and
  encoding canonicality. Three independent read-only reviews are assigned.
- No `.fst`/`.fsti` changes, implementation, F* command, or tests.

## S2-05 completed; S2-06 started — 2026-10-13

- Completed S2-05 at specification-contract level. The event machine now has
  five explicit structural guard/update rules; append authorization is a
  proof-bearing exact-prefix transition; `StateWF`, `GlobalGraphWF`, and
  ghost `SemWF` are separate; terminality is derived and absorbing; and event
  and journal byte canonicality have distinct laws. See
  `research/S2-execution-2026-10-13/S2-05-canonical-replay.md` and its three
  audit reports.
- Resolved event identity/encoding alternatives by deriving sequence from
  journal position, storing run identity once in `RunStarted`, and pinning
  format identity in replay context. Physical bytes-to-prefix recovery stays
  in P10; concrete private-write-path refinement stays P13. P3 remains a
  target, not a source theorem.
- No DAG structure or acceptance condition changed. Marked S2-05 complete and
  started S2-06 after its prerequisite was satisfied.
- S2-06 scope: specify the abstract concurrent executor and prove P15 over
  every permitted schedule while preserving serial append, commit visibility,
  exact-input agreement, crash safety, and no-rerun-after-commit. Three
  independent read-only schedule/authorization audits are assigned.
- No `.fst`/`.fsti` changes, implementation, F* command, or tests.

## S2-06 completed; S2-07 started — 2026-10-13

- Completed S2-06 at specification-contract level. Added the P15 controller
  transition system, exact `ReadyInputAgreement`, live attempt/claim/candidate
  invariants, ghost origin witnesses, serial current-head reauthorization,
  commit visibility, and crash/restart behavior. The synthesis and audit
  provenance are in `research/S2-execution-2026-10-13/S2-06-controller-interleavings.md`.
- Closed two audited seams without changing DAG topology: old append requests
  settle or are fenced before a recovery load and cannot commit afterward;
  old worker callbacks are rejected by non-reused attempt epochs. P10's cut
  is the recovery-load barrier, so the loaded journal includes exactly the
  append commits through that barrier. `RunStarted` retries bind to the same
  complete request; run-identity namespace uniqueness remains a P13 allocator
  premise. Final independent review found no S2-06 acceptance gap.
- Marked S2-06 complete. Started S2-07, which is an independent successor of
  S2-05. Initial P7 audits found formalization gaps around exact adapter
  request fingerprints, same-key terminal tuple stability, effect-safe
  recovery across adapter restart, callback races, charge/evidence meaning,
  and bounded-capacity liveness; root is integrating these into §2.1.
- No `.fst`/`.fsti` changes, implementation, F* command, or tests.

## S2-07 completed; S2-08 started — 2026-10-13

- Completed S2-07 at specification-contract level. P7 now binds each logical
  adapter call to `K=(operation_identity, CallKey)`, exact canonical request
  and resume descriptor `Q`, and one immutable terminal receipt `T`. Changed
  bindings conflict; retry and overlap across adapter restarts are covered by
  `EffectSafe`; unsafe unreconciled non-idempotent operations are excluded.
- The raw adapter reply is validated at the replayed input, encoded by the
  pinned indexed output codec, and projected with the same receipt evidence,
  charge, and artifact references into `CallOutcome`. The receipt witness
  connects exact raw reply and effect provenance to canonical journal fields;
  replay decodes the stored typed output without rerunning the adapter or
  validator. Distinct keys remain nondeterministic and may complete out of
  order. Capacity and conditional liveness are explicit.
- Independent retry/effect-safety and interleaving/liveness audits passed the
  integrated contract. The final report and audits are in
  `research/S2-execution-2026-10-13/S2-07-adapter-contract.md` and adjacent
  reports. No remaining P7 acceptance gap was found.
- Marked S2-07 complete and started S2-08; all S2-08 dependencies (S2-04,
  S2-05, S2-07) are complete. S2-08 covers P8 charge/fuel accounting and P9
  generic artifact/resource durability. No DAG topology or acceptance
  condition changed.
- No `.fst`/`.fsti` changes, implementation, F* command, or tests.

## S2-08 completed; S2-09 started — 2026-10-13

- Completed S2-08 at specification-contract level. P8 now pins a single run
  charge metric, treats allocation and settlement maps as canonical
  projections, guards natural subtraction, and states charge/fuel conservation
  plus once-only settlement. P9 now specifies typed packed artifact refs,
  exact value-to-reference inventories, publication-before-commit, immutable
  version identity, and stable logical resolution after restart. The synthesis
  and independent reviews are in
  `research/S2-execution-2026-10-13/S2-08-budget-artifact-contracts.md` and
  adjacent audit reports.
- Resolved metric source of truth by passing the committed run metric to
  `generate_graph`, rather than copying it into each `GenerationAllocation`.
  Replay remains independent of artifact-store I/O; P9 witnesses extend
  semantic recovery only when physical resource identity is claimed.
- The independent integrated audit passed. Corrected its sole report wording
  mismatch so P8 owns aggregate conservation while P3/P4 establish replay and
  allocation transition premises. No S2-08 contradiction or DAG change was
  found.
- Marked S2-08 complete and started S2-09 after S2-05, S2-06, S2-07, and
  S2-08 completion. S2-09 specifies the serial journaler and every-cut
  recovery, then composes P10 with P16 semantic graph correctness. Three
  read-only reviews are assigned. DAG topology and acceptance remain unchanged.
- No `.fst`/`.fsti` changes, implementation, F* command, or tests.

## S2-09 completed; S2-10 started — 2026-10-13

- Completed S2-09 at specification-contract level. P10 now models exact
  physical loaded bytes, proves their decoded projection is the latest
  committed prefix, derives exact byte canonicality, and states serial
  compare-and-append, atomic prefixes, monotone durability, and the
  recovery-load fencing barrier. P16 composes every-cut replay with ghost
  semantic provenance, universal typed root/generated DAGs, exact result
  provenance, committed-work reuse, and safe pending-call retry. See
  `research/S2-execution-2026-10-13/S2-09-serial-recovery-contract.md` and its
  audits.
- Independent review prompted two clarifications: `load_store` is only a
  decoded projection of physical `load_bytes`; no-repeat-after-commit is
  trace-indexed, while replay separately removes committed work from the
  enabled frontier. Pending retry claims are scoped to intents present in the
  cut prefix. A final combined review passed these changes.
- Crash cut remains the post-exit recovery-load barrier. In-flight append may
  commit before that barrier and must then be present; otherwise it aborts and
  cannot commit after load. The concrete fencing, flush, and storage mechanism
  remains a P13 refinement proof. No DAG topology or acceptance changed.
- Marked S2-09 complete and started S2-10 after S2-06, S2-08, and S2-09
  completion. S2-10 covers P11 frontier/no-stuck, P12 well-founded progress,
  and P14 conditional termination. Three read-only reviews are assigned.
- No `.fst`/`.fsti` changes, implementation, F* command, or tests.

## S2-10 completed; S2-11 started — 2026-10-13

- Completed S2-10 at specification-contract level. P11 now cleanly states
  logical frontier existence, while P14 owns eventual progress under explicit
  weak fairness and service premises. The termination claim starts after a
  valid `RunStarted`; local/generator computations must return results to the
  controller, and serial append, adapter response/capacity, retry, resource,
  and finite-crash progress are explicit.
- P12's `(G,U,W)` rank is now consistent with P4: roots may receive zero
  expansion fuel, every nested generator receives positive fuel, and a
  zero-fuel parent cannot have generator children. Independent P11, P12, and
  P14 audits passed; see the synthesis and reports at
  `research/S2-execution-2026-10-13/S2-10-progress-termination.md` and the
  adjacent `S2-10-*-audit.md` files. The normative implementation spec and
  theorem guide were updated consistently. DAG dependencies and acceptance
  were unchanged.
- Marked S2-10 complete and started S2-11 after S2-09 and S2-10. S2-11
  specifies the concrete refinement boundary for P13; independent reviews
  cover controller/worker execution, physical journal recovery, and
  adapter/identity/resource refinement. No S2-11 acceptance or topology
  changes.
- No `.fst`/`.fsti` changes, implementation, F* command, or tests.

## S2-11 completed; S2-12 started — 2026-10-13

- Completed S2-11 at specification-contract level. `implementation_spec.md`
  §6 now states the P13 concrete representation relation, step simulation or
  stutter, exact recovery-load mapping, empty volatile restart state, fresh
  epoch, append fencing, and component refinement obligations. The theorem
  guide records the same boundary; P9 is conditional on claiming physical
  persistent-resource identity.
- Independent controller/worker, journaler/storage, and adapter/identity/
  resource audits passed. The synthesis and reports are linked from
  `research/registry.md`. No DAG topology or acceptance changed.
- Marked S2-11 complete and started S2-12 after all prerequisites completed.
  S2-12 produces an implementation-ready module/interface and proof packet,
  with independent audits of architecture, theorem order, and counterexamples.
- No `.fst`/`.fsti` changes, implementation, F* command, or tests.

## S2-12 completed; S2-HUMAN awaiting review — 2026-10-13

- Completed [implementation_packet.md](../retired_guides/implementation_packet.md) as the
  implementation-ready, non-normative source-module and proof plan. It maps
  the full P0-P16 contracts and P13 refinement boundary to signatures,
  acyclic module owners, journal representation rules, proof order, theorem
  acceptance checks, explicit representation owners, alternatives, and six
  proof-bearing workflow examples.
- Reconciled reviewer findings without changing DAG topology: added the P2
  graph decode/resolver composition owner; separated `GeneratorAdmission`
  below GraphBuilder; split P4 generator/splice reasoning from its
  append-gated visibility theorem; removed the P4/P8 back-edge by separating
  ControllerModel from BudgetProof; split EventAuthority witness types from
  P6/P7 proof modules; and separated P5 GraphRecovery from P16 Recovery.
  `GeneratorMember` is now explicit as a package-author proof contract bound
  to the pinned entry by P0 and consumed by P2/P4.
- Final architecture, proof-order, integrated, GeneratorMember, and P4
  append-boundary audits passed. Failed intermediate audit reports remain
  preserved with follow-ups in [research/registry.md](../research/registry.md).
- Updated `implementation_spec.md` §8 to say source representations remain
  for later implementation, while packet module names are proposals and the
  normative dependency order remains fixed. Updated the theorem guide and all
  active state/status references consistently.
- S2-12 is complete; S2-HUMAN is now `awaiting_human`. Stop here for user
  review. No implementation DAG was created or started. No `.fst`/`.fsti`
  files, implementation, F* verification, or tests were changed or run.

## Implementation/proof DAG planned — 2026-10-13

- User authorized replacement of the active planning DAG with a future DAG
  for implementing and proving the complete abstract system. User explicitly
  prohibited executing that DAG or changing F* code.
- Read the normative implementation spec, theorem guide, implementation
  packet, current state files, Makefile, and all seven existing `.fst` modules.
  This planning-time source inspection does not start A00 or count as node
  completion.
- Three read-only audits were assigned: existing-source/P0–P16 coverage,
  independent theorem dependency order, and adversarial missing-proof/gate
  review. Their reports are under
  `research/implementation_dag_2026-10-13/`.
- Replaced `work_dag.md` with the A00–H5 proof DAG and added its brief/research
  provenance. Updated the state hub and summary index so the new DAG is the
  sole authority. S2 summaries remain historical.
- Every new DAG node remains `not_started`; human nodes pause only when the
  future DAG is explicitly executed. No `.fst`/`.fsti` changes, F* command,
  verification, or tests were made or run in this task.

## A01 completed — 2026-10-14

- Integrated four independent reviews plus source/contract audits into
  `research/A01-2026-10-13/module_boundary_design.md`. The adversarial review
  found that `GeneratorAdmission -> Bundle` conflicted with P0 requiring the
  pinned Bundle to carry the admission law, and the DAG put P0 before the law
  type existed.
- Resolved before A02: define one manifest-indexed `GeneratorPackage` below
  Bundle, containing the exact callback plus universal admission proof;
  Bundle stores that single package and derives registry membership from its
  lookup. Do not compare duplicate function closures. P0/reload now preserves
  the exact identity-to-package association. P0 moved after A07/A15/A16;
  C1 follows P0 before public builder/codec work. This retains P0/P4 strength
  and removes the ownership/order cycle.
- Updated `implementation_spec.md`, `implementation_packet.md`, the active
  DAG, A01 assignments, research registry, and system overview consistently.
  Added the A02 task brief, but A02 has not started until the A01 work is
  committed and its hash recorded.
- A01 is `complete`; no `.fst`/`.fsti` source was changed and no new theorem
  was claimed. The A00 baseline verifier evidence remains unchanged; no
  verifier run or tests were needed for this architecture-only node.

## A02 started — 2026-10-14

- A01 boundary/spec/DAG/state work is committed as `34e1021`; the exact hash
  is recorded in `state.md`, `work_dag.md`, and `node_summaries.md`.
- Started kernel signatures and foundations from
  `research/A02-2026-10-14/task_brief.md`. Three independent read-only reviews
  completed: compatibility map, codec/dependent signature review, and
  adversarial soundness review. A fourth read-only review is checking minimal
  schema/artifact shapes. Root owns F* source and shared state.
- Integrated review findings: preserve high-fanout wire/graph syntax during
  this foundation step; retain external arbitrary-bytes validation and its
  `option (output x)` result; thread the exact run metric through budget,
  operations, and generator calls; add schema syntax and typed opaque artifact
  references without moving resolver or host-resource behavior into Kernel.
  Exact package selection plus membership evidence belongs at Bundle; tagged
  identity uniqueness and codec/schema links remain P0 obligations.
- A02 is `in_progress`; A03 and later are `not_started`. No A02 source changes
  have been made yet, and no theorem is claimed complete.

## A02 completed — 2026-10-14

- Kernel now defines schema, charge-metric, artifact-type, and artifact-store
  identities; the exact first-order schema AST; type-indexed artifact-token
  and packed candidate-reference syntax; and `charge_metric` on `run_budget`,
  `op_ref`, and generator calls. Existing Graph/GenerationExample/ChainProof
  generator call sites pass the metric. Their legacy admission proof shape
  quantifies it; the sample generator ignores it because its output is
  metric-independent.
- Two implementation reviews confirmed the AST and metric flow. Their
  artifact-reference finding was resolved as an explicit validation boundary:
  packed refs are candidate syntax, and ArtifactPackage/P0/P9 must prove the
  exact identity/carrier/codec relation before encoding or commit. This layer
  does not claim token existence, publication, or durable resource identity.
- Full check passed:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify`.
  F* 2026.03.24, Z3 4.13.3; all seven configured modules verified. Existing
  warnings remain in `FStar.UInt` pattern and unused recursive
  `GraphCodec.nodes_decode_encoding`. Kernel source has no `assume`, `admit`,
  or unchecked external declaration. Legacy Graph admissions remain; this
  result is not evidence for P0–P16.
- A02 is `complete`; A03 is next. C1 remains downstream of A04 and P0.
  Source completion commit is `bb4d8ae`.

## A03 started — 2026-10-14

- A02 source and synchronized state are committed as `bb4d8ae`; A03 owns the
  next dependency in the active work DAG.
- Started [A03 task brief](../research/A03-2026-10-14/task_brief.md). Three
  read-only reviewers are investigating registry identity injectivity,
  canonical encoder proofs/module layering, and full manifest metadata/link
  coverage. Root owns implementation and shared files.
- A03 specifically resolves the digest collision boundary: a digest may index
  the canonical manifest, but cannot replace its exact logical identity.
  Need preserve A01 import graph and avoid duplicate identity encoders.
- A03 is `in_progress`; A04 and later remain `not_started`. No A03 source
  changes have been made yet, and no P0 theorem is claimed.
- Review reports completed: exact-byte identity over digest/name-version;
  suffix decoder left-inverses for injectivity and duplicate rejection before
  deterministic sorting; one first-order tagged entry sum with A04 owning
  executable package projection. Reports are
  `identity_design_review.md`, `encoding_proof_review.md`, and
  `manifest_shape_review.md`.
- Independent adversarial review and source migration review completed. The
  former gives concrete duplicate, tag collision, omitted/misdirected link,
  ordering, ambiguity, alias, and one-way projection counterexamples; its
  predicate factoring is adopted. The latter recommends Kernel ownership of
  framing and identity codecs. Root moved the existing definitions/proofs
  from GraphCodec to Kernel, leaving graph syntax in GraphCodec.
- Full verification passed after the move: `opam exec -- gtimeout
  --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify`; F* 2026.03.24,
  Z3 4.13.3, all seven modules, exit 0. Existing warnings 271 and 328 remain.
  This is source-migration evidence only; A03 manifest proofs and P0–P16 are
  still open. See `research/A03-2026-10-14/source_migration_verification.md`.
- The A03 kickoff package was committed as `94e6a62`. After the full verifier
  passed, the shared identity-codec migration and its evidence were committed
  as `e88e1b8`. Canonical state now records both hashes before the remaining
  ManifestCore source work.
- Independent proof-feasibility probes passed in scratch modules using F*
  2026.03.24/Z3 4.15.4: tagged decoder suffix inversion/injectivity and
  insertion-sort sortedness. These are pattern evidence only, not source
  verification. Lexicographic `list nat` ordering, permutation invariance,
  sorted-permutation uniqueness, and manifest-specific proofs remain open;
  see `research/A03-2026-10-14/proof_feasibility_review.md`.
- The integrated proof-design evidence and canonical state update were
  committed as `528eeb2` before starting ManifestCore definitions.

## A03 initial manifest proofs and trust audit — 2026-10-14

- Added `WorkflowV2.ManifestCore` to the configured module set and implemented
  tagged manifest identities, typed row metadata, validation/closure,
  canonical decoding/encoding, exact lookup, and canonicalization proofs.
  A03 projection is clarified as syntax-level list equality; exact projection
  to executable package tables remains A04/P0.
- Full verifier command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify`.
  Result: all eight configured modules verified, exit 0, F* 2026.03.24,
  Z3 4.13.3, OCaml 5.3.0. Warnings 271 (FStar.UInt pattern) and 328
  (unused recursive GraphCodec helper) remain.
- Transitive trust audit found the first sorting implementation constructs
  `total_order` using Classical/Squash helpers; their dependency reaches
  `FStar.IndefiniteDescription.elim_squash`, declared as an axiom and
  implemented with `admit ()` in the installed stdlib. A stricter run of the
  same build with `FSTAR_FLAGS='--cache_off --warn_error @285
  --report_assumes error'` fails with Error 335 at `Prims.fst:663`, exposing
  this use. Source path and the trust decision are recorded in
  `research/A03-2026-10-14/stdlib_axiom_audit.md`.
- Decision: preserve this checked source snapshot and its evidence, but reject
  it for A03 acceptance. Update A03's acceptance before dependent work: replace
  first-class `total_order`/`sortWith_sorted` and all Classical/Squash proof
  helpers with constructive local sorting/proofs. Preserve canonical order,
  rejection behavior, permutation invariance, idempotence, and identity
  injectivity. A03 remains `in_progress`; no P0 theorem is claimed.
- The initial source + trust evidence was checkpointed before the
  proof-architecture replacement in commit `38f8e62` (`feat(fstar): add v2
  manifest proof snapshot`). The hash is also recorded in the canonical DAG,
  state index, and A03 summary. This is explicitly not A03 completion.

## A03 integrated proof and trust re-audit — 2026-10-14

- Replaced the Classical/Squash-based `total_order`/`sortWith_sorted` path
  with structurally recursive insertion sort and checked local lemmas. Kept
  duplicate rejection, canonical ordering, permutation invariance,
  idempotence, and exact codec claims unchanged.
- Migrated identity names, manifest labels, run names, and artifact identities
  to `identity_token = bytes`; the abstract Kernel represents `bytes` as
  `list nat`. This has no text, Unicode, UTF-8, or octet-level promise.
- Added artifact logical-schema/reference-codec-schema agreement to manifest
  canonicality and refined `registry_manifest_identity` to require canonical
  manifest data. Contract slots remain typed owner-row tokens; A04/P0 binds
  each exact token to its proof-bearing package field. A05 parses and proves
  schema AST canonicality before P0.
- Three independent reviewers checked sort/canonicalization proof cases,
  token migration and trust boundary, and manifest closure/field coherence.
  A separate audit of the actually used `FStar.List.Tot` helpers found their
  F* definitions and lemma bodies checked, with no admission in this call
  path. See `research/A03-2026-10-14/acceptance_audit.md` and
  `stdlib_axiom_audit.md`.
- Full configured check:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a03-final`. F* 2026.03.24,
  Z3 4.13.3, OCaml 5.3.0; all eight modules verified, all VCs discharged,
  exit 0. Warning 328 remains for the unused recursive
  `WorkflowV2.GraphCodec.nodes_decode_encoding` helper. No tests were run;
  this node's acceptance is F* proof verification.
- A scoped cached run of `--report_assumes error` for Kernel and ManifestCore
  also passed. Cache-off mode fails on F*'s own `Prims.admit` even for a
  trivial lemma, so the flag is recorded as diagnostic only. The A03 trust
  conclusion is source/call-path scoped and does not claim the legacy Graph
  or ChainProof modules are admission-free.
- Source/proof acceptance is complete. A03 remains `in_progress` only until
  this result and its commit hash are synchronized in the canonical DAG,
  state index, and node summary. No P0 claim is made.

## A03 committed; A05 started — 2026-10-14

- Committed the completed A03 source/spec/research package as `09ed6ea`
  (`feat(fstar): prove canonical v2 manifest core`). `work_dag.md`,
  `state.md`, and `node_summaries.md` now record A03 complete and the full
  verifier evidence. This closes the A03 node; it does not claim P0.
- Started A05, whose independent acceptance brief and approach registry are
  `research/A05-2026-10-14/task_brief.md` and `approach_registry.md`. Scope is
  canonical schema AST parsing/encoding, locally nameless scope/substitution,
  manifest-indexed denotation, and a static `LegalEnv` interface for A06/A07.
- Assigned three independent read-only investigations: schema codec and
  signed-int proof design; dependent denotation/substitution architecture;
  adversarial A05/A06/A07 boundary review. Root owns integration and source.
- At A05 start no new F* module or theorem exists. Baseline remains the A03
  committed eight-module full check. A05 must first return concrete designs;
  no downstream node has started.

## A05 contract clarification — 2026-10-14

- Independent schema reviews found an under-specified binder in the normative
  schema language: `Refine(T,P)` denotes a subset but had no declared value
  binder for `P`. This blocked precise scope, substitution, and
  `PortRefinement` semantics.
- Resolved by giving `P` a typed candidate binder of domain `T`, parallel to
  the binder in a `Sigma` codomain. The base `T` remains in the outer scope;
  only `P` enters the extended scope. Bound indices are nearest-first and
  malformed/free indices reject. The context substitutes the exact candidate
  output port with capture avoidance. Full-family `LegalEnv` quantification
  and the universal P1 edge theorem are unchanged.
- Synchronized the normative spec, key theorem guide, implementation packet,
  A05 contract/approach registry, DAG row, state hub, and node summary. See
  `research/A05-2026-10-14/refinement_binder_resolution.md` for the alternatives
  and proof implications. No AST constructor, codec tag, DAG edge, or module
  dependency changed.
- Committed the coherent contract/state change as `b947175` (`docs(fstar):
  clarify schema refinement binder`). `git diff --check` passed; no repository
  F* source or verifier result is part of this commit.
- Independent review returned a relational denotation scratch prototype at
  `/tmp/A05RelDenote.fst`; agent-reported cache-off verification passed. A
  separate signed-integer codec prototype also passed. These are design
  evidence only; neither is A05 source proof evidence. The root still must
  implement and verify the repository module.
- A05 remains `in_progress`; no downstream node has started. No repository
  source proof or full verifier result is claimed for this clarification.
- Before source work, split the A05 module into `WorkflowV2.SchemaCodec`,
  `WorkflowV2.SchemaScope`, and `WorkflowV2.SchemaSemantics`: the first two
  depend only on Kernel; semantics additionally depends on ManifestCore and
  the syntax modules. This is a cohesion/import-boundary refinement only; A05
  acceptance and theorem dependencies are unchanged.

## A05 partial source milestone — 2026-10-14

- Implemented `WorkflowV2.SchemaScope.fst` and added it to the configured
  module list. Definitions cover locally nameless scope, lifting, parallel
  capture-avoiding substitution, and the exact binder placement for Sigma and
  Refine. Checked lemmas prove lift and substitution preserve scope.
- Added proof examples for singleton refinement scope, free `Bound 0`
  rejection, nested Sigma/Refine indexing, and outer-value substitution under
  both binders.
- Fixed a proof-contract issue found by the verifier: scope conditions are
  refinement-indexed arguments rather than explicit boolean proof parameters;
  the predecessor-bound lemma now exposes its arithmetic obligations as
  preconditions. This is a proof-interface cleanup, not a semantic weakening.
- Full command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-scope-full`.
  Exit 0; all nine configured modules verified, all VCs discharged. F* 2026.03.24,
  Z3 4.13.3, OCaml 5.3.0. Warning 328 in legacy `GraphCodec.fst` remains.
- A05 remains in progress. This milestone does not prove substitution
  identity/composition, denotation commutation, schema codec correctness, exact
  package semantics, `LegalEnv`, or any P0–P16 theorem. No tests were run.
- Commit pending; hash to follow after scoped commit.

## A05 follow-up — substitution algebra and codec foundation — 2026-10-14

- Added pointwise substitution congruence, identity, composition, and
  lift/substitution commutation to `WorkflowV2.SchemaScope.fst`. The scratch
  proof was first checked against the repository module and then integrated;
  no function extensionality is used.
- Integrated `WorkflowV2.SchemaCodec.fst`: every current AST constructor now
  has an encoder and a fuel-bounded parser. Public decoders demand complete
  input and exact re-encoding. Parser audit confirms unknown tags, truncated
  fields, invalid booleans, negative zero, excess argument counts, and trailing
  data reject. Generic AST roundtrip and injectivity remain unproved; sample
  cases do not close those obligations.
- Full configured verifier command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-codec`.
  Exit 0; all ten configured modules verified and all VCs discharged under
  F* 2026.03.24, Z3 4.13.3, OCaml 5.3.0. Existing GraphCodec warning 328
  remains. No tests were run.
- A05 stays in progress; semantics, denotation preservation, typed context, and
  general codec laws remain open. No P0–P16 claim is made.
- Committed as `1cc76f4` (`feat(fstar): add schema codec and substitution
  laws`). This records a partial A05 milestone and does not mark A05 complete.

## A05 scratch comparison — recursive codec and schema denotation — 2026-10-14

- Compared the source's concatenated child encodings with a scratch format
  that wraps each recursive AST child in a length frame. The framed format
  simplifies child boundaries, but it is not accepted until a stable exact
  source verifies all value, predicate, type, and argument-list roundtrip
  cases. An in-progress file once produced an F* internal parse failure; a
  module-shaped scratch path avoided that failure. A concurrent proof edit and
  skeletal constructor branch made that verification stale, so it is not
  counted as evidence. The codec worker is auditing all branches before any
  integration or format decision.
- Verified scratch semantics prototypes use an identity-indexed manifest
  lookup and typed heterogeneous argument lists. The first model exposed two
  design gaps: package lookups must link to exact pinned manifest rows, and
  constructor outputs must be indexed into their declared parent family. A
  corrected constructor contract and a closed Sigma/Refine transport lemma
  verify in separate cache-off scratch files. Root/Port/Constant denotation,
  typed local environments, general substitution, LegalEnv, and generated
  context remain open.
- The LegalEnv shape is clarified as an inductive prefix relation: exact root
  and canonical constants at the base; for each completed prefix node, evaluate
  its declared input and admit any value in its full output family at that
  input. This preserves every validator-accepted external value without
  narrowing the family. A05 supplies a manifest-indexed interface; A04/P0
  binds it to the exact bundle rows, avoiding a dependency cycle.
- Detailed audit and next proof work are in
  `research/A05-2026-10-14/semantic_model_prototype_audit.md`. DAG status stays
  A05 `in_progress`; no downstream node has started. No scratch proof counts
  toward the source acceptance, and no new full-source verifier result is
  claimed. The synchronized documentation checkpoint is committed as
  `2abdf9a` (`docs(fstar): record A05 semantics research`); it contains no
  source proof changes. The follow-up that records this documentation hash is
  `aa0e076` (`docs(fstar): record A05 research checkpoint`).

## A05 correction — framed codec proof was not verified — 2026-10-14

- The preceding scratch note incorrectly said the module-shaped path avoided
  the internal F* crash and described a recursive roundtrip group as active
  audit evidence. The codec worker checked the module path: it did not load
  the file matching the declared dotted module name, so that success is
  withdrawn.
- With the correct flat dotted filename,
  `/tmp/a05stable/WorkflowV2.SchemaCodecFramed.fst`, the source through the
  list-parser equation helper verifies. Adding the recursive fuel-equation
  lemma crashes F* with `Failure("Parse error: </labels> not found")`. Splitting
  the proof on fuel avoids the internal crash but fails the postcondition.
  Therefore no framed generic roundtrip result is verified.
- This corrects the research log only; the committed unframed source is
  unchanged and its generic roundtrip/injectivity remain open. Exact evidence
  and required follow-up are in
  `research/A05-2026-10-14/codec_proof_attempts.md` and the updated approach
  registry. Continue with another parser/proof formulation; do not weaken the
  theorem or rely on the invalid module-path result.
- Follow-up verification on a clean flat module confirms the codec base and
  local child/int/pair lemmas through line 462, plus one fixed-fuel
  `SchemaRoot` suffix roundtrip. This is partial evidence only; symbolic
  recursive fuel, full constructor/list coverage, and generic roundtrip remain
  unproved. Synchronized correction committed as `91f3e47`
  (`docs(fstar): correct A05 codec proof status`).

## A05 codec alternative — suffix grammar — 2026-10-14

- `/tmp/A05SchemaValueParseGrammar.fst` verifies a mutual suffix parse
  relation over all current Kernel AST constructors (13 values, argument
  lists, 4 predicates, 12 types), cache off. The unread suffix is explicit,
  enabling structural induction without a standalone recursive parser
  equation lemma.
- The grammar is not yet connected to the executable decoder or encoder.
  Encoder-to-grammar, determinism, and decoder soundness/completeness are
  still required before deriving generic roundtrip, injectivity, and exact
  accepted-byte laws. `/tmp/A05CodecDirect.fst` still fails at direct
  recursive fuel/length unfolding.
- No repository source changed; the last full-source verification remains
  the ten-module pass recorded for `1cc76f4`. A05 remains `in_progress` and
  no downstream node has started.
- Synchronized research checkpoint committed as `6e0020c`
  (`docs(fstar): record schema parse grammar approach`).

## A05 current source verifier recheck — 2026-10-14

- Re-ran the complete configured source verifier, without relying on scratch
  results:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-current`.
  Exit 0; all ten modules verified and all VCs discharged under F* 2026.03.24,
  Z3 4.13.3, OCaml 5.3.0. Existing `GraphCodec.nodes_decode_encoding`
  warning 328 remains. No source edits were made by this check; A05 stays in
  progress. Evidence checkpoint committed as `4aded38`
  (`docs(fstar): record current A05 verifier pass`).

## A05 semantics source foundation — 2026-10-14

- Added `WorkflowV2.SchemaSemantics.fst` to the configured Makefile. The
  current source proves canonical-manifest schema-family row selection and
  uniqueness lemmas, extracts the row's parsed AST and exact denotation-law
  reference, represents constants indexed by the exact root value, and proves
  a generic append step stores an inhabitant of its full declared output
  family.
- Independent review identified a soundness boundary: the initial carrier
  telescope is not tied to `SchemaBound`'s AST declaration and must not be
  treated as schema denotation or graph `LegalEnv`. Source names/comments now
  label it as carrier-only / generic. Exact local typing, AST denotation, and
  graph/work linkage remain open.
- Scratch proof `/tmp/WorkflowV2.SchemaSemanticsSingleDerivationProbe.fst`
  verifies a single indexed derivation GADT over actual Kernel AST syntax. Its
  `JType` is an environment-indexed carrier family; `ContextSnoc` admits a
  local only from the exact `JType` denotation, and `ValueBound` requires
  syntax and carrier lookup at the same index. Sigma/Refine carrier shapes are
  represented. Its bound/context regression and package/AST coverage remain
  partial; this is scratch, not source acceptance.
- Full configured command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-semantic-source`.
  Exit 0; all eleven modules verified, all VCs discharged, F* 2026.03.24,
  Z3 4.13.3, OCaml 5.3.0. Existing `GraphCodec.nodes_decode_encoding` warning
  328 remains. This is not A05 completion and no downstream node has started.
- The AST-linked single-GADT integration is the next source action. The
  current source module and Makefile progress checkpoint is committed as
  `d8b6f006ecceb37f2de5f2bb50e169a4a8f4ca5b`
  (`feat(fstar): add schema semantics foundation`). Unrelated nested-repository
  and generated user files remain unstaged.

## A05 exact schema-rule row selection — 2026-10-14

- Unified family/rule syntax-row and denotation-law extraction under one
  owner-tagged `schema_entry_expression` / `schema_entry_law` projection.
  Added canonical-manifest-selected rule lookup, membership, uniqueness, and
  expression/law accessors. This eliminates duplicated field parsing and
  prevents a same-payload family identity from being substituted for a rule
  identity.
- Source checkpoint: `c0696b8f16b0ce1ea74d861e9e534afefe08fd19`
  (`feat(fstar): resolve schema rule rows exactly`).
- Full configured verification command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-row-selection`.
  All eleven modules verified and all verification conditions discharged;
  F* 2026.03.24, Z3 4.13.3, OCaml 5.3.0. Existing GraphCodec warning 328
  remains. `git diff --check` passed.
- A full framed recursive codec proof also verifies in scratch, covering every
  current AST constructor, roundtrip, injectivity, malformed/trailing
  rejection and accepted-byte canonicality. It changes the existing flat wire
  bytes, so it is an alternative only until resolver-version/legacy recovery
  consequences are decided; the committed codec remains unchanged. See
  `research/A05-2026-10-14/codec_proof_attempts.md` for exact command/results.
- A single-GADT typed carrier/context prototype verifies positive `Bound`,
  Sigma and refinement cases and rejects a Nat/bool context mismatch. It is
  scratch only and still lacks AST value/predicate denotation, exact symbol
  package linkage and semantic substitution preservation.

## A05 typed-context audit and predicate experiment — 2026-10-14

- Simplified scratch context membership to one paired `schema_member` that
  selects the AST type and carrier at the same index; `schema_lookup` recurses
  jointly over that witness and the HList. This avoids separate, potentially
  mismatched AST/carrier membership proofs.
- The unconstrained predicate callback is unsound. The verified
  `/tmp/A05PredicateOracleCounterexample.fst` term makes
  `SchemaRefine SchemaNat SchemaFalse` denote `{x:nat | true}` and stores `5`
  in its context. Separately, a `JType` can be derived at a malformed context
  because primitive type constructors do not require a context-WF derivation.
  These are scratch counterexamples, not admitted project claims.
- `/tmp/A05BoundPredicateEval.fst` defines a bounded evaluator for
  `True`/`False`/`And`, same-kind primitive literal equality, and reflexive
  `Bound i` equality. It verifies an example refinement and a `Bound 0 ==
  Bound 0` substitution-preservation lemma. This fragment is incomplete and
  cannot define the full schema predicate semantics; unsupported equality and
  symbol cases must be rejected by an explicit typing/derivation relation.
- Combined exact command:
  `PATH=/Users/alex/.opam/ocaml.5.3.0/bin:$PATH
  /Users/alex/.opam/ocaml.5.3.0/bin/fstar.exe --cache_off --warn_error @285
  --include src/fstar/v2/src --include /tmp
  src/fstar/v2/src/WorkflowV2.Kernel.fst
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst
  /tmp/A05CarrierTypedAST2.fst /tmp/A05BoundPredicateEval.fst
  /tmp/A05PredicateOracleCounterexample.fst`.
  All VCs discharge; imported ulib warning 271 remains. This verifies both
  the bounded positive lemmas and the well-typed counterexample. The corrected
  source design must define structural `ValueDenote`/`PredDenote` and either
  gate `JType` with context validity or prove a precise admissibility theorem.

## A05 exact row-bound package contract — 2026-10-14

- `/tmp/A05ExactDenotationPackage.fst` verifies family/rule package types
  indexed by canonical manifest and identity, with selected-row,
  expression-projection and law-projection equalities. Their semantic field
  contains the exact `JType` derivation for every carrier inhabitant rather
  than an arbitrary predicate callback. No `assume`/`admit` is used.
- Exact command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include
  src/fstar/v2/src --include /tmp --odir /tmp/A05exactbuild
  src/fstar/v2/src/WorkflowV2.Kernel.fst
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst
  /tmp/A05UnifiedTypedAST.fst /tmp/A05ExactDenotationPackage.fst`.
  All seven modules verify and all VCs discharge.
- This proves only a package contract shape: the law is restricted to empty
  local context, its AST GADT lacks `Atom`, `Family`, `Constructor`, and
  `IndexCall`, and it remains soundness-only. It does not repair the
  predicate-oracle or `JType` context-WF counterexamples. P0 must bind the
  exact package object returned by existing Bundle lookup; A05 adds no second
  package map.

## A05 unframed codec proof and format decision — 2026-10-14

- `/tmp/A05unframed/WorkflowV2/SchemaCodecUnframedTry.fst` is the existing
  `SchemaCodec.fst` with only the module name changed plus proof lemmas. It
  verifies all value/predicate/type constructor and list roundtrips, public
  decode roundtrip, encoder injectivity, trailing rejection, pointwise
  non-image rejection and accepted-byte canonicality. The existing encoder
  and parser definitions are unchanged; no `assume` or `admit` appears.
- Exact command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include
  src/fstar/v2/src --include /tmp/A05unframed
  /tmp/A05unframed/WorkflowV2/SchemaCodecUnframedTry.fst`.
  All verification conditions discharge. All 13 value, 4 predicate, and 12
  type constructors are covered; this proof shares the current Kernel string
  trust boundary.
- Design decision: preserve current unframed durable bytes and integrate
  these proof additions. The framed alternative's full proof is retained in
  scratch as comparison only; it would change bytes and require a resolver
  version/legacy-recovery policy, with no correctness benefit needed here.

## A05 codec configured-source integration audit — 2026-10-14

- The full unframed roundtrip/injectivity/canonicality proof passes as scratch,
  but the claim that it was ready to integrate was incorrect. Applied the
  proof block to canonical `WorkflowV2.SchemaCodec.fst`; the configured full
  verifier failed with Error 19 (`incomplete quantifiers`) at
  `uvalues_count_bound`. Refactoring the count bound and adding generic and
  specialized recursive-list lemmas advanced the failure to later recursive
  parser VCs, still with incomplete quantifiers. Higher rlimit/fuel did not
  change the result.
- Nested-path control is invalid as module integration: F* resolves by
  basename in that layout and warns about implicit namespace opening; a
  consumer import of `WorkflowV2.SchemaCodec` fails with `No modules in
  namespace WorkflowV2.SchemaCodec`. The standalone proof body is not tied to
  the project module identity. Flat dotted paths preserve imports and expose
  the actual recursive-list VC.
- Removed the unverified canonical source proof block. Exact clean-baseline
  check:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-restored-baseline`.
  Result: exit 0; all eleven modules verified and all VCs discharged, F*
  2026.03.24 / Z3 4.13.3 / OCaml 5.3.0. This establishes only the current
  partial baseline; no codec completeness theorem is integrated.
- A05 remains `in_progress`; A06 and all dependents remain `not_started`.
  DAG acceptance is unchanged. Continue proof-route investigation rather than
  weakening roundtrip/canonicality claims or changing durable encoding without
  evaluating version/recovery consequences. Details:
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


## A05 semantic scratch extension and design audit — 2026-10-14

- Delegated an independent scratch extension of the sound typed-context
  nucleus and a separate audit of the full A05 semantic architecture. Scratch
  work remained outside the repository source tree.
- `/tmp/A05SoundNucleus.fst` now verifies Product/Sum/List/Option carrier
  representations; structural semantic values/equality; pair denotation;
  evaluator lemmas for its supported `value_denote`/`predicate_denote`
  judgments; and `value_typed_sound`. A concrete locally nameless substitution
  regression covers Product/Sum/Refine/Option/List and binder shadowing.
- Exact command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include
  src/fstar/v2/src --include /tmp --odir /tmp/A05SoundNucleusBuild
  /tmp/A05SoundNucleus.fst`. Exit 0; all scratch VCs discharge; imported
  ulib warning 271 remains. Limits: List is rejected by `type_accepts`,
  Kernel lacks Sum/List/Option value constructors, and no general carrier to
  AST denotation/acceptance theorem exists.
- Independent audit's proof spine: paired schema/carrier WF; typed
  type/value/predicate denotation; exact manifest package linkage; semantic
  substitution under a value-representation relation; generated context
  facts; full-family LegalEnv prefix induction; then universal edge soundness.
  Completion is bounded by `SchemaSupported` and representable values, not
  arbitrary F* quotation. Details are in
  `research/A05-2026-10-14/semantic_model_prototype_audit.md`.
- No source integration or DAG dependency changes. A05 remains `in_progress`;
  all dependent nodes remain `not_started`.

## A05 evidence correction checkpoint — 2026-10-14

- Synchronized the canonical DAG, state hub, A05 summary, task brief, and
  research records after reproducing the configured flat-module codec failure
  and auditing the nested-path namespace behavior. Also recorded verified
  semantics scratch limits and the independent architecture review.
- Documentation-only commit: `e34c425` (`docs(fstar): correct A05 proof
  integration status`). It does not complete A05 or alter theorem obligations.

## A05 row-coherence source proof and scratch alternatives — 2026-10-14

- Integrated the checked theorem `selected_family_components_from_same_row`
  in `WorkflowV2.SchemaSemantics.fst`: schema syntax bytes and the
  denotation-law token are extracted from the same selected canonical family
  row, and the bytes decode to the exact projected AST. This does not bind
  the token to an actual executable package or prove semantic carrier
  adequacy.
- Full configured command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-live-same-row`. Exit 0;
  all 11 modules verified and all VCs discharged. F* 2026.03.24, Z3 4.13.3.
  Existing warning 328: `GraphCodec.nodes_decode_encoding` is recursive but
  its body does not recurse.
- Independent scratch package bridge verifies exact row/token indexing, but
  also proves the contract is too weak: a `False` carrier makes the law
  vacuously true for any schema. Structural carrier denotation/completeness,
  actual package lookup, and graph `LegalEnv` adequacy remain required.
- Codec scratch confirms a first-order mutually recursive parser can compile
  with no higher-order parser callback. Generic recursive roundtrip still has
  opaque-equation VCs; this is exploration only, not a source law. Another
  exact-canonical-module scratch reaches two remaining generic roundtrip
  proof obligations and is under proof search. Unframed wire bytes remain
  unchanged in tracked source.
- A05 remains `in_progress`; no dependent DAG node started. This is partial
  proof progress only. Synchronized status lives in `state.md`,
  `node_summaries.md`, and the A05 row of `work_dag.md`.
- Commit `1f98f8a` (`feat(fstar): prove schema row component coherence`)
  preserves the source theorem, the configured verifier result, and
  synchronized A05 state. It is a progress commit; A05 remains `in_progress`.


## A05 value codec proof closes in flat-module scratch — 2026-10-14

- Re-verified `/tmp/A05StepEq/WorkflowV2.SchemaCodec.fst` with the exact
  project Kernel using: `opam exec -- fstar.exe --cache_off --warn_error
  @285 --include src/fstar/v2/src --include /tmp/A05StepEq --odir
  /tmp/A05StepEq/reverify src/fstar/v2/src/WorkflowV2.Kernel.fst
  /tmp/A05StepEq/WorkflowV2.SchemaCodec.fst`. Exit 0; both modules verified,
  all VCs discharged under F* 2026.03.24 / Z3 4.13.3. Warning 349 is a
  successfully localized split VC.
- Scratch proves suffix and public roundtrips for every value, predicate, and
  type AST constructor; value-list/constructor/index-call parsing; injectivity
  for all three encoders; and rejection of nonempty trailing suffixes. The
  same checked parser-fuel measure covers all AST sorts.
- No repository F* source changed. DAG acceptance is unchanged; A05 remains
  `in_progress`, A06 and all dependents remain `not_started`.


## A05 codec source integration and full verification — 2026-10-14

- Integrated the checked callback-free parser and all Value/Predicate/Type
  codec laws into `WorkflowV2.SchemaCodec.fst`. Existing encoder bytes and
  public codec signatures are unchanged. The parser's low-level fuel meaning
  changes; source search found no other project caller.
- Proved suffix/public roundtrip for each AST sort, all three encoder
  injectivity theorems, nonempty trailing-byte rejection, and sufficient
  input-derived fuel. Removed the count-versus-payload early guard; malformed
  inputs are still fuel-bounded and public decode requires full consumption
  plus exact re-encoding. No `assume`/`admit` added.
- Full configured cache-off command with split proofs: `opam exec --
  gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify
  BUILD_DIR=/tmp/fstar-v2-a05-codec-integrated FSTAR_FLAGS='--cache_off
  --split_queries always --warn_error @285'`. Exit 0; all 11 modules and all
  VCs pass under F* 2026.03.24 / Z3 4.13.3. Existing GraphCodec warning
  328 only.
- A05 remains in progress: semantic denotation, exact package bridge,
  substitution, and `LegalEnv` remain. No dependent node started.

- Source and synchronized state commit: `115fd0bf057f403c32ceeeba57c615b1385de381`
  (`feat(fstar): prove schema codec laws`). A05 remains open.


## A05 exact-codec equality proof and semantic research — 2026-10-14

- Added `schema_plain_codec_encode_injective` and
  `schema_indexed_codec_encode_injective` in
  `WorkflowV2.SchemaSemantics.fst`. Each proof derives actual-value equality
  from equality of encoded bytes by applying the same codec's roundtrip law;
  the indexed result requires the same exact index.
- Full configured verifier command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-codec-eq-rerun
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 11 configured modules and all VCs verified under F* 2026.03.24
  / Z3 4.13.3. Existing warning 328 remains in `GraphCodec`.
- Source and synchronized state commit:
  `a3fea7abe26af6478c9f4d4b6d2b66154103a814`
  (`feat(fstar): prove codec equality reflection`). The preceding codec proof
  hash-recording checkpoint is `c83034cf4ed105577951a80e45c21631fa35f946`.
- Scratch audit found arbitrary atom/family observations can collapse
  distinct values. `SchemaEqual` must consume static typed value derivations
  at the same carrier/index; the exact codec injectivity lemmas then justify
  byte-based equality. Atom/Family packages must expose their exact codec,
  and A04/P0 must bind it to the selected row and Work signature.
- `/tmp/A05ActualValueSubst.fst` verifies capture-avoiding semantic
  substitution for value/predicate/type judgments, including concrete Sigma
  and Refine binder cases. `/tmp/A05TypedASTSemantics2.fst` adds AST-indexed
  contexts and also verifies, but does not prove each target binder inhabits
  the denotation of its substituted declaration. Neither scratch theorem is
  accepted as A05's typed-context proof. `/tmp/A05SemanticsBool` is only a
  finite abstraction. `/tmp/A05SplitJTypeRefine.fst` verifies structural
  membership and native-refinement/List/Option constructors, but lacks the
  bridge from its relational `jtype` to a fixed carrier denotation. Exact
  commands, boundaries, and next proof obligations are in
  `research/A05-2026-10-14/codec_equality_and_typed_substitution.md` and
  `semantic_model_prototype_audit.md`.
- DAG acceptance/dependencies unchanged. A05 remains `in_progress`; A06 and
  all later nodes remain `not_started`.

## A05 staged DAG and schema-package representation decision — 2026-10-14

- Re-read `implementation_spec.md` and the current `SchemaSemantics` and
  `ManifestCore` source after the user-directed execution began. The integrated
  codec/scope work was verified, but the single A05 row combined five
  independent proof boundaries and obscured a package-law dependency cycle.
- Reworked the canonical DAG into A05a–A05f and A05 integration acceptance.
  A05a (syntax codecs/scope) is complete; A05b (exact package interfaces) is
  active. A05c canonical denotation/typed judgments depends on A05b; A05d
  package adequacy follows A05c; A05e semantic substitution follows A05d;
  A05f full-family `LegalEnv` follows A05e. A06 is still blocked on the A05
  rollup. DAG, state hub, node summary, and task brief now agree.
- Independent review found that the current schema AST has no typed argument
  telescope and the rule row is projected as a general type AST plus law
  token. One alternative was a new first-order signature/equation syntax in
  manifest bytes. The chosen representation keeps those finite declarations
  inside the exact proof-bearing schema package selected by its owner row;
  the row law token must equal that package's field, and P0 must prove exact
  bundle projection and reload stability. Package lookup is by owner identity,
  never by a raw token. This follows the spec's exact package-projection
  model, avoids a duplicate signature table, and keeps all equation soundness
  proofs mandatory. `implementation_spec.md` now states this boundary, and
  A06 consumes exactly the finite equations in those manifest-selected
  packages. This representation decision changes no theorem strength and no
  durable bytes.
- `SchemaRulePackage` must be a typed sum (Constructor or IndexCall). A
  mismatching AST constructor rejects. Typed heterogeneous args use an
  inductive relation over a dependent telescope; constructor results are
  built directly in their exact parent family at computed indices. Package
  contracts must make telescope/equation data finite; package-driven recursive
  evaluator expansion cannot be left without a termination argument.
- Re-ran the full configured cache-off baseline:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05-stage-baseline
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 11 modules and all VCs verified under F* 2026.03.24 / Z3
  4.13.3. Existing `GraphCodec.nodes_decode_encoding` warning 328 remains.
  This is baseline verification, not A05 semantic completion.
- No F* source changed in this planning/review checkpoint; no A06 or other
  dependent node started. Stage documentation awaits a scoped commit before
  A05b source integration.

## A05b package-interface increment and verification — 2026-10-14

- Continued active A05b. Added `WorkflowV2.SchemaPackages.fst` and configured
  it in Makefile order after `Identity`. Package telescope arity is now a
  dependent natural index equal to the AST signature length. Family/rule
  packages carry the exact selected owner row, its expression/law projections,
  one exact codec object with membership in the shared global codec registry,
  and typed Constructor/IndexCall variants. Constructor interpretation is
  exposed through a helper that gets its parent only from the exact
  `family_at` map lookup. Type-AST matching enforces nullary `SchemaAtom` and
  matching `SchemaFamily` arity; rule AST matching enforces variant, identity,
  and argument count.
- Independent A05b source audit and proof-boundary review confirmed the
  A05b→A05c→A05d order. It flagged that equal telescope arity is not typed
  compatibility, codec registry membership is not yet manifest/P0 coherence,
  parent functions must only be called via the exact map helper, and law-token
  equality is not denotation soundness. These are kept explicit for A05c,
  A05d, and P0; no stronger claim is made. No manifest bytes or theorem
  strength changed.
- Full configured cache-off run:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05b-codec-membership-final
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 12 modules verified and all VCs discharged under F* 2026.03.24
  / Z3 4.13.3. Existing GraphCodec warning 328 remains. Earlier runs exposed
  two omitted `codec_registry` arguments in helper calls; these were corrected
  before the passing run. This only checks interface consistency; A05b is
  still active and semantic judgments are not yet defined.
- `implementation_spec.md`, this log, `work_dag.md`, `state.md`,
  `node_summaries.md`, and the A05 task/approach records were synchronized.
  Scoped `git diff --cached --check` passed. No `assume`/`admit` occurs in
  `SchemaPackages.fst`. Source and synchronized state were committed as
  `e70c0ce01dfb8006c6386cb39a559023bd99d547`
  (`feat(fstar): define schema package interface`). No dependent node has
  started.

## A05b close and A05c start — 2026-10-14

- Independent final source audit found the A05b interface coherent and no DAG
  reorder necessary. Its guarantees are structural only: the exact manifest
  row/token projection is not a semantic law, codec membership is not
  schema/codec denotation coherence, and scoped/equal-length telescopes do not
  prove binder typing. This matches the A05b acceptance boundary.
- Independent law-boundary review found that A05c may define judgments over
  the exact base map, but any callback/schema soundness must remain conditional
  until an A05d adequacy witness exists. The selected design is an
  `AdequateSchemaPackages` wrapper indexed by the same package map, with
  checked binder, family, constructor, index-call/equation, and codec laws.
  P0 pins/reloads that exact map plus the witness. The owner token is never
  treated as proof. The design note is
  [`package_law_boundary_review.md`](../research/A05-2026-10-14/package_law_boundary_review.md).
- Updated implementation spec, canonical DAG, state, A05 task brief, approach
  registry, and node summary before starting affected A05c work. A05b is now
  `complete`; A05c is `in_progress`. This is a clarification of the staged
  contracts, not a theorem weakening or source change.
- A05c scratch design uses an indexed judgment/argument telescope with paired
  AST and carrier environments. The first F* scratch attempt encountered a
  universe/GADT-refinement obstacle and has not verified a complete relation.
  No project F* source changed and no A05c theorem is claimed yet. Continue
  proof exploration and implement only after resolving the representation.
- Canonical implementation-spec/DAG boundary checkpoint committed as
  `28e23f348997380177bb5a6a9e40ebe933276125`
  (`docs(fstar): close schema package interface stage`).

## A05c first integrated proof increment — 2026-10-14

- Added `WorkflowV2.SchemaJudgments.fst` after `SchemaPackages` in the build.
  The indexed derivation relates formal AST argument types, actual syntax
  arguments, the exact dependent carrier telescope, and its dependent tuple of
  values. Formal argument substitution is nearest-first and binder-aware.
  Exact family/rule lookup helpers return only the registry-selected object
  after its AST matcher succeeds; the nullary Atom consequence is proved.
- The initial tuple projection approach failed: F* could not establish the
  recursive carrier index and termination from the indexed derivation. The
  source was redesigned to index the derivation by the actual tuple itself;
  this removed the projection, recursion, and cast obligation. F* also
  exposed a constructor-name collision and a missing matcher precondition;
  both were corrected before acceptance.
- Full cache-off configured verification command:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05c-args-indexed-4
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0, all 13 modules verified, all verification conditions discharged;
  F* 2026.03.24 / Z3 4.13.3. Existing GraphCodec warning 328 remains.
- Scope remains partial and explicitly unaccepted as A05c completion: the
  indexed value relation is a parameter; the example chooses `unit`; canonical
  contexts and complete JType/JValue/JPredicate semantics are still open.
  No A05d or downstream node has started. Scratch context/judgment exploration
  continues. A separate verified scratch `/tmp/A05JArgsParam.fst` replaces the
  generic relation with a context-indexed JValue for NatLit and Bound(0), a
  total value projection, and a dependent argument tuple indexed by the exact
  telescope. It does not prove context AST/carrier adequacy or cover the full
  AST; it is design evidence only. Its cache-off proof command and limits are
  recorded in [`typed_jvalue_scratch.md`](../research/A05-2026-10-14/typed_jvalue_scratch.md).
- Further verified scratch `/tmp/fstar-a05c-universe/ContextJValue.fst`
  proves paired AST/dependent-value context lookup for `SchemaBound 0` and
  `SchemaBound 1` (`vec 4` and `nat`) under a small Nat/Vec type relation.
  `/tmp/A05SchemaArgValues.fst` proves a GADT-spine tuple alternative, but
  round-tripping the spine into the package's `dtuple2` alias remains blocked;
  because current package callbacks already consume that alias, the integrated
  design retains direct tuple-indexing. Commands and limits are in
  `typed_jvalue_scratch.md`. These are scratch proofs, not A05c source closure.
- Updated `work_dag.md`, `state.md`, this log, `node_summaries.md`, the A05
  task brief, and approach registry consistently. Scoped whitespace check
  passed. Source and synchronized state committed as
  `9ba432b` (`feat(fstar): add schema argument judgment scaffold`). The state
  hash reference is recorded in the immediate follow-up state-record commit.

## A05c paired-context scratch extension — 2026-10-14

- The `/tmp/fstar-a05c-universe/ContextJValue.fst` scratch prototype now
  checks paired syntax/runtime lookup for newest `vec 4` and earlier `nat`
  bindings. A small structural relation verifies types unit/bool/nat/int,
  product/sum/list/option and indexed Vec; value rules cover bound, unit,
  bool, nat, int, and product forms.
- Root independently reran cache-off F* after the agent's extension. Exact
  command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include src
  --include /tmp/fstar-a05c-universe --odir /tmp/fstar-a05c-universe
  src/WorkflowV2.Kernel.fst /tmp/fstar-a05c-universe/ContextJValue.fst`.
  Exit 0; both modules verified and all VCs discharged. This is one scratch
  proof, not the full v2 verifier or A05c source acceptance.
- Paired lookup alone does not prove the declaration AST/carrier relation for
  arbitrary context entries. Sigma/Refine, predicates, package-based
  family/rule judgments, root/port/constants, and sum/list/option value rules
  remain open. No DAG acceptance or dependency changed; no source code
  changed. The scope and command are in
  `research/A05-2026-10-14/typed_jvalue_scratch.md`.

## A05c declaration-witness context scratch — 2026-10-14

- `/tmp/fstar-a05c-universe/ContextJValuePaired.fst` passed cache-off F*:
  it stores each context declaration's prior-prefix `j_type` and value
  witness, then derives the same-index bound path and type witness. Example
  context `[Vec Bound(0); Nat]` has `Vec 4` newest and `4 : nat` older.
  Command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include
  src/fstar/v2/src --include /tmp/fstar-a05c-universe --odir
  /tmp/fstar-a05c-universe /tmp/fstar-a05c-universe/ContextJValuePaired.fst`.
- `/tmp/fstar-a05c-paired-context/ContextSigma.fst` passed cache-off F* with
  `WorkflowV2.Kernel` and its local `ContextJValue` copy. It proves the
  specialized `Sigma Nat (Vec Bound(0))` carrier and corresponding context
  lookups. Command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include src
  --include /tmp/fstar-a05c-paired-context --odir
  /tmp/fstar-a05c-paired-context src/WorkflowV2.Kernel.fst
  /tmp/fstar-a05c-paired-context/ContextJValue.fst
  /tmp/fstar-a05c-paired-context/ContextSigma.fst`.
- Both are scratch-only fragments. A declaration's type witness is at its
  prior prefix; arbitrary weakening/substitution remains A05e. No full
  `JType`/`JValue`/`JPredicate`, package-selected interpretation, or complete
  A05c claim is made. No source or DAG status changed. These findings and
  limits are in `research/A05-2026-10-14/typed_jvalue_scratch.md`.

## A05c witness-universe correction and Sigma/predicate probes — 2026-10-14

- Source review found the `schema_argument_derivation` comment overstated its
  relation as context-indexed. It has no context/environment parameter, and
  its example uses `unit` evidence. Corrected the comment and generalized the
  relation codomain from `Type0` to `Type`; its example is explicitly typed
  in `Type`. This is only scaffold cleanup and a more suitable evidence
  universe, not canonical JValue proof.
- Full cache-off configured verification passed after the source edit:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05c-proof-sort-final
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  Exit 0; all 13 modules verified and all VCs discharged. Existing
  GraphCodec warning 328 remains.
- Independent Sigma scratch found structural recursive `j_type`/`j_value`
  functions returning `Tot Type` that prove Nat and dependent Sigma with
  existing `dtuple2`. Exact command:
  `opam exec -- fstar.exe --cache_off --include src/fstar/v2/src --include
  /tmp/fstar-a05c-universe --include /tmp/fstar-a05c-generic --odir
  /tmp/fstar-a05c-generic
  /tmp/fstar-a05c-generic/SigmaRecursiveDtuple.fst`. Exit 0; all VCs
  discharged. Inductive recursive Sigma constructors instead fail F* Error
  67, even without context and with either carrier. This supports a candidate
  definition strategy only; no general context or full AST is proved.
- Predicate scratch confirms a `Type0` JValue derivation is not itself a
  `prop`; a negative probe fails with `Expected type Prims.prop got type
  Type0`. A positive probe uses JValue derivation data plus a soundness lemma
  to establish the proposition used by native subset refinement. Therefore
  `PredDenote` needs to be proposition-valued, and equality evidence must be
  extracted through a sound bridge from same-carrier JValue witnesses. Exact
  passing/negative commands and limits are in the typed-value scratch note.
- Updated DAG context, state, node summary, and scratch index; no status or
  dependency changed. A05c remains active; all dependent nodes remain
  unstarted. Source and synchronized proof-state checkpoint committed as
  `8c0dcc7` (`feat(fstar): clarify A05c judgment evidence boundary`); the hash
  is captured here and in the DAG/state/node summary before further A05c work.

## A05c canonical witness and predicate evidence exploration — 2026-10-14

- Full current-source cache-off verification completed successfully:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05c-denotation-package-review
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'`.
  All 13 configured modules verified and all VCs discharged under F*
  2026.03.24/Z3 4.13.3. Existing GraphCodec warning 328 remains. No source
  changed during this run; it does not close A05c.
- Rejected direct recursive denotation bridge: a function
  `TypeDenote : AST -> Tot Type0` may produce a dependent Sigma type, but
  recursive projection remains opaque to JValue's dependent pair elimination.
  Explicit equality/tactic attempts did not provide safe transport. Separately
  rebuilding a `noeq` GADT codomain witness would be unsound as a proof step.
- Selected candidate for integrated A05c: canonical interpretation returns a
  sealed `(carrier, constructor-indexed shape witness)` package. `TypeDenote`
  is its carrier projection; JType/JValue/JPredicate consume the exact
  returned package and must not recompute or reconstruct its witness. Root
  reran `/tmp/A05cCanonicalVecWitness.fst` with
  `opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285
  --odir /tmp /tmp/A05cCanonicalVecWitness.fst`; exit 0, all VCs discharged.
  It types `Mkdtuple2 n xs` at `dtuple2 nat (vec n)` using the same canonical
  Sigma witness, without function extensionality. It is a hardcoded fragment,
  not a full recursive interpreter. Explicit native-dependent-pair/dtuple2
  conversions verify, but these representations are not definitionally
  interchangeable in indexed GADT results.
- Predicate follow-up verifies
  `/tmp/A05PredicateEvidenceGADTVerified.fst` against the actual Kernel:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include
  src/fstar/v2/src --include /tmp --odir
  /tmp/a05-predicate-evidence-gadt-verified-build
  src/fstar/v2/src/WorkflowV2.Kernel.fst
  /tmp/A05PredicateEvidenceGADTVerified.fst`. Exit 0, all VCs discharged;
  only stdlib warning 271. Type-valued PTrue/PEqual/PAnd evidence, wrapped
  once in squash, proves Nat equality and conjunction. EqualWitness shares
  the exact carrier and includes both typed operand witnesses plus
  `squash (Prims.equals x y)`. This verified piece avoids separate-squash
  conjunction and uses neither admissions nor Classical choice. It uses
  native equality only and does not yet consume the exact manifest-selected
  codec or prove codec equality reflection, as A05c requires.
- Refine remains unresolved: the direct recursive TypeDenote projection for
  a native subset still fails with Error 12, even with its exact predicate.
  The failure is carrier conversion/opacity, not inability to inhabit the
  subset. Reusing the canonical package is a candidate, not yet evidence of
  the Refine theorem. Full typed contexts, package-based denotations, all AST
  constructors, semantic soundness, and exact shared-carrier equality remain
  unproved.
- Synchronized `work_dag.md`, `state.md`, `node_summaries.md`, A05 approach
  registry, and typed JValue scratch note with the representation choice,
  evidence, and limits. No node status/dependency changed; A05c remains
  `in_progress`; downstream nodes remain `not_started`. No F* source changed.
  Scoped research/state commit: `d8a3f4f` (`docs(fstar): record A05c
  canonical witness route`).

## A05c package representation and hidden-interface follow-up — 2026-10-14

- Refined the earlier carrier-plus-shape candidate to one source of truth:
  the package is a sealed shape witness indexed by context and schema type;
  `package_carrier p` is `shape_denote p`. Do not store a duplicate carrier
  and propositional equality. Direct recursive `TypeDenote` remains rejected.
- Independent scratch `/tmp/A05cShape.fsti/.fst` and
  `/tmp/A05cShapeClient.fst` verifies a constructor-hidden type-family API
  with a toy `context = nat`, an AST with Nat/Sigma/Refine tags, dependent
  carrier `dtuple2 nat vec`, and native refinement `x:nat{x == 7}`. Exported
  value helpers create terms at the opaque projected carriers; JValue helper
  functions produce evidence for those exact terms. Implementation and client
  both verified, all VCs discharged, with:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include /tmp --odir /tmp/a05c_shape_build6 \
    /tmp/A05cShape.fsti /tmp/A05cShape.fst
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include /tmp/a05c_shape_build6 --odir /tmp/a05c_shape_build6 \
    /tmp/A05cShapeClient.fst
  ```

- An independent interface probe `/tmp/a05c-interface/sigma/S.fsti` and
  `S.fst` also verifies a private noeq package/witness, exact Sigma JValue at
  `dtuple2 nat (fun _ -> nat)`, and native Refine with a checked carrier
  equality/introduction API. A public client cannot assume an abstract
  carrier reduces to a native pair or Nat; expose value builders/eliminators
  or carrier transport explicitly. The viable interface is an abstract
  type-family `val package : indices -> Type u#1` implemented as an alias to a
  private representation, not an unindexed term-level `eqtype` handle.
- The carrier-indexed record alternative `{carrier; shape Γ t carrier}` hit
  F* Error 197 / Error 67 universe constraints. Shape-only packages avoid the
  duplicate carrier and this universe issue. This remains toy AST/context
  evidence; actual dependent `hlist` contexts, full Kernel AST, exact package
  map, codec-reflecting equality, and general predicate soundness remain
  unverified.
- A context-member scratch `/tmp/A05cPrefixEnv.fst` also verifies same-index
  AST/carrier selection for `SchemaBound 0 : SchemaNat : nat`. It is not a
  runtime environment lookup theorem; selected-value evidence contains its
  own value. Root reran it cache-off; all VCs discharged. Context weakening,
  Sigma/Refine reindexing, and Root/Port/Constant remain open.
- Rewrote the active DAG's representation note to require the shape-only
  package and record these limits. No node status or dependency changed; A05c
  remains `in_progress`; downstream nodes remain `not_started`. No project
  F* source changed. Current-source full cache-off verification remains the
  earlier recorded 13-module success; scratch proofs do not close A05c.

## A05c package representation audit and codec reflection — 2026-10-14

- Corrected the package decision from “shape-only selected” to the actual
  invariant: use one sealed AST/context-indexed canonical package, reused by
  every judgment; do not keep an independently chosen carrier plus an
  unrelated shape/equality. Shape-only and dependent-existential encodings
  remain candidates until both work on the actual context.
- Shape-only toy `.fsti` implementation/client remains successful for toy
  Sigma and native Refine. The real-Kernel-AST `.fsti` probe is Nat-only. A
  new Kernel-AST/local-context scratch, `/tmp/A05CanonicalPackageRefine2.fst`,
  fails at subset introduction: the projected carrier does not reduce to the
  expected native subset. F* Error 189 occurs before JValue. Its `hlist` is
  locally modeled and does not import production `SchemaSemantics.hlist`; it
  is a representation-opacity failure in this experiment. A carrier-indexed
  record previously hit Error 197/67; the production-context dependent
  existential alternative is under independent verification. Thus no source
  integration has begun from the toy result. Exact failed command is in
  `research/A05-2026-10-14/typed_jvalue_scratch.md`.
- Exact package codec reflection is verified separately. For the same
  manifest-selected package and index, equality of encoded bytes implies
  equality of represented values by `schema_indexed_codec_encode_injective`
  (and the plain-codec analogue), which follows from roundtrip. The
  `/tmp/A05EqualManifestPackage.fst` command passed cache-off with all VCs:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include src/fstar/v2/src --include /tmp \
    --odir /tmp/a05-equal-manifest-build \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.Identity.fst \
    src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
    src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
    src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
    /tmp/A05EqualManifestPackage.fst
  ```

  A same-package/index JValue byte-equality fragment also verifies separately.
  This does not prove that independently inferred values share an index or
  package. The eventual equality judgment must quantify one exact selected
  package/index and feed both operands and the selected codec from it; two
  separate existentials do not prove type equality.
- Updated `work_dag.md`, `state.md`, `node_summaries.md`, the approach
  registry, and `typed_jvalue_scratch.md` to capture this correction and the
  exact limits. No dependency/status changed. The source remains unchanged;
  the last full current-source cache-off run is the recorded 13-module pass
  under F* 2026.03.24 / Z3 4.13.3. This research synchronization is pending a
  scoped commit before additional integration work.

## A05c production-context refinement and builtin-shape probes — 2026-10-14

- Re-ran `/tmp/A05cActualContextExists.fst`, which imports the production
  `WorkflowV2.SchemaSemantics.hlist`. It defines a dependent Sigma carrier
  `dtuple2 nat (fun n -> x:nat{x == n})`, with a codomain AST refinement
  comparing `SchemaBound 0` to `SchemaBound 1`. A specialized evaluator over
  the production `hlist` proves any inhabitant of the codomain carrier makes
  the AST predicate evaluate `Some true`.
- Exact command:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include src/fstar/v2/src --include /tmp \
    --odir /tmp/a05c-exists-build \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.Identity.fst \
    src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
    src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
    src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    /tmp/A05cActualContextExists.fst
  ```

- Root independently reran this command: all six dependency modules and the
  scratch module verified; all VCs discharged. This is a specialized AST
  evaluator and carrier-membership theorem, not generic JPredicate semantics.
- Independent `/tmp/A05cSimpleShapes.fst` covers shape interpretations for
  `SchemaUnit/Bool/Nat/Int`, Product, Sum, List, Option; JValue covers the
  four literals, Product pair, and Fst/Snd. Exact command:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include src/fstar/v2/src --odir /tmp/a05c-simple-shapes-build \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    /tmp/A05cSimpleShapes.fst
  ```

- The independent run exited 0 with all VCs discharged. It has no direct AST
  constructors for List/Option/Sum values, and no selected package path for
  those forms; it is builtin structural evidence only. Bound/root/port/
  constant interpretation, selected constructors/index calls, generic
  predicates, full canonical package semantics, and soundness remain open.
- A third scratch `/tmp/A05cActualVecSigma.fst` verifies the production-context
  dependent family codomain: Sigma over Nat with second type
  `SchemaFamily family_id [SchemaBound 0]`, interpreted as `vec n` under
  `HCons n rho`. It constructs a JValue for a pair whose second component is
  typed at that exact dependent vector. Root reran:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include src/fstar/v2/src --include /tmp \
    --odir /tmp/a05c-actual-vecsigma-root \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.Identity.fst \
    src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
    src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
    src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    /tmp/A05cActualVecSigma.fst
  ```

  All six dependencies and the scratch module verified; all VCs discharged.
  The scratch hardcodes `family_id` and the `vec n` interpretation. It does
  not select the exact manifest-backed family package/codec or prove package
  adequacy; that is still A05c work.
- Updated DAG, state, node summary, A05 approach registry, and scratch note to
  include these results without changing node statuses. A05c remains active;
  no project source changed and no downstream node started. The previous full
  current-source cache-off verification remains the recorded 13-module pass;
  scratch verification is not source acceptance evidence. This scoped state
  synchronization is ready for its own commit before source integration.

## A05c shared-package predicate equality probe — 2026-10-14

- `/tmp/A05PredicateProbe.fst` imports production `Identity`,
  `SchemaSemantics`, and the `A05ActualJValue.fsti` abstract interface. It
  fixes one package and exact carrier for both operands, then proves
  proposition-valued equality reflection from encoded-byte equality using a
  codec that is a member of the shared global codec registry. The indexed
  version fixes one exact index. Both call the existing roundtrip-derived
  codec injectivity lemmas.
- Root reran cache-off with split queries; all VCs discharged:

  ```sh
  opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
    --include src/fstar/v2/src --include /tmp/a05actual-interface \
    --odir /tmp/a05-predicate-root \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.Identity.fst \
    src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
    src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    /tmp/a05actual-interface/A05ActualJValue.fsti \
    /tmp/A05PredicateProbe.fst
  ```

- This proves equality once one package/index and a registry-member codec are
  given; it does not infer shared carrier equality from separate existential
  judgments. Key unresolved link: the scratch codec membership is not the
  exact codec field projected from the AST-selected manifest package or tied
  to its denotation. Integrating `SchemaEqual` must establish that link before
  using the reflection theorem. This result does not close generic
  `JPredicate` or A05c.
- Canonical state, summaries, A05 approach registry, and typed scratch note
  are updated; no source or DAG status changed. The changes are ready for a
  scoped state commit before source integration.
- Scoped research/state checkpoint committed as `c42b948`
  (`docs(fstar): record A05c semantic proof probes`). It contains only the
  six synchronized A05c state/research files; unrelated worktree changes and
  all scratch files under `/tmp` remain uncommitted/outside the repository.

## A05c exact family codec/reflection probe — 2026-10-14

- `/tmp/A05cFamilyPackageCodec.fst` uses the production
  `schema_family_package`: its one `family_codec` encodes the same
  `family_denotation` at the same exact `indices`. A proof derives native
  value equality from byte equality using that package codec's roundtrip law.
  A helper also obtains one package from `packages.family_at` and passes that
  exact dependent package to one continuation.
- Root independently reran the full dependency-ordered scratch command with
  cache off and split queries; every module and VC passed:

  ```sh
  opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
    --include src/fstar/v2/src --include /tmp \
    --odir /tmp/a05c-family-codec-root \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.Identity.fst \
    src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
    src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
    src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
    /tmp/A05cFamilyPackageCodec.fst
  ```

- The codec source-of-truth gap is resolved for this lemma: it uses the
  selected family package's codec, not an independently selected registry
  codec. The remaining semantic integration is to derive that exact package
  and index from the `SchemaFamily` AST, then keep one existential shared by
  both equality operand derivations. The proof is a helper, not generic
  `SchemaEqual` elaboration or JPredicate soundness. A05c remains active;
  scratch only, no project source changed.
- Synchronized the DAG, state hub, node summary, A05 approach registry, and
  typed-JValue scratch record to this sharper boundary before source work.
  The package-linked helper supersedes the earlier generic-registry-member
  equality probe as the selected route; the earlier proof remains recorded as
  exploration. A05c stays `in_progress` and downstream statuses are unchanged.
- Scoped proof-state checkpoint committed as `6cee517`
  (`docs(fstar): record package-linked equality proof`). It records only the
  synchronized A05c evidence and its verifier commands; no implementation
  source changed.

## A05c integrated-shape probe and source baseline — 2026-10-14

- The production-context scratch `/tmp/A05cActualVecRefineProduct.fst`
  combines dependent Sigma, a `Vec n` family-shaped field under `Bound 0`,
  and a `{x:nat | x == n}` refinement with Kernel AST bound equality. Root
  reran it cache-off; all seven dependencies/scratch modules verified and all
  VCs discharged. The family ID and `vec n` interpretation are hardcoded, so
  this proves expressibility only, not exact package selection, package codec
  use, generic predicate semantics, or A05c acceptance. Full command and
  detailed boundary are in `research/A05-2026-10-14/typed_jvalue_scratch.md`.
- Before source integration, root reran the configured full source verifier:

  ```sh
  opam exec -- gtimeout --signal=TERM --kill-after=5s 10m \
    make -C src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a05c-preintegration \
    FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'
  ```

  Exit 0; all 13 configured modules verified and all VCs discharged. F* is
  2026.03.24; the existing GraphCodec warning 328 remains. This establishes
  the source baseline only; it does not close A05c. No source files changed.
- Latest documentation hash before this update is `5b42a90`
  (`docs(fstar): pin A05c family reflection checkpoint`). The combined-shape
  result, full baseline, and source-integration boundary are now synchronized
  across the DAG, state, node summary, approach registry, and scratch note.
  Scoped synchronization commit: `7428189` (`docs(fstar): record A05c
  combined shape proof`). A follow-up state-record commit pins this hash.
  No DAG status changes; A05c stays `in_progress`.

## A05c positivity-safe refinement and recursive binder law — 2026-10-14

- Root independently verified the positivity-safe builtin/refinement fragment:

  ```sh
  opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
    --include src/fstar/v2/src --include /tmp \
    --odir /tmp/a05c-builtin-refine-root \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.Identity.fst \
    src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
    src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
    src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    /tmp/A05cBuiltinRefineCore.fst
  ```

  Exit 0; seven modules verified, all VCs discharged. A separate
  proposition-valued predicate denotation makes the current builtins/True
  subset fragment positivity-safe. It does not yet provide generic
  `SchemaEqual`, all AST values, context typing, exact package semantics, or
  a soundness theorem.
- Root independently verified the recursive package binder-alignment shape:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 \
    --include src/fstar/v2/src --include /tmp \
    --odir /tmp/a05c-family-telescope-root \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.Identity.fst \
    src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
    src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
    src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
    src/fstar/v2/src/WorkflowV2.SchemaJudgments.fst \
    /tmp/A05cFamilyTelescopeLaw.fst
  ```

  Exit 0; nine modules verified, all VCs discharged. F* emitted the existing
  SchemaCodec Warning 349. The law checks each binder at its declaration
  prefix and checks the tail under extension by every value of the exact
  prior carrier. The Nat example derives `Mkdtuple2 n ()` for `SchemaBound 0`
  using production `hlist` and the existing argument-derivation relation.
  It does not construct the complete exact manifest package or its adequate
  wrapper.
- The direct family-index attempt without this binder law does not typecheck:
  an AST argument's carrier cannot be unified with the corresponding
  dependent package carrier. The existing A05d adequacy boundary resolves
  this as one package-level alignment field; A05c must derive call-site
  arguments internally and share one exact package/index across denotation,
  codec, and both equality operands. No graph/work author supplies a
  per-use proof.
- `/tmp/A05cPredicateMutual.fst` now verifies the mutually indexed evidence
  GADTs and `predicate_evidence_sound` for Nat literal equality and
  conjunction. The independent `pred_eval` proposition drives native
  refinement; its proof is used to construct the subset value explicitly.
  The scratch also uses production codec reflection and a selected plain
  codec with actual registry membership. Root reran cache-off/split-queries:

  ```sh
  opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
    --include src/fstar/v2/src --include /tmp \
    --odir /tmp/a05c-pred-mutual-root-final \
    src/fstar/v2/src/WorkflowV2.Kernel.fst \
    src/fstar/v2/src/WorkflowV2.Identity.fst \
    src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
    src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
    src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
    src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
    /tmp/A05cPredicateMutual.fst
  ```

  Exit 0; seven modules verified, all VCs discharged. Earlier iterations
  failed first the strict positivity check and then explicit squash
  construction/refinement introduction; the successful revision resolves
  those fragment-level issues. It remains a hardcoded Nat evaluator: no
  arbitrary `SchemaValue` evaluation, context lookup, package-selected family
  or constructor, or all-AST JPredicate soundness has been proven.
- These are `/tmp` probes, not source integration. The current
  `SchemaJudgments.fst` remains a placeholder scaffold; A05c stays
  `in_progress`, with downstream statuses unchanged. Details are in
  `research/A05-2026-10-14/typed_jvalue_scratch.md`.
- Synchronized DAG, state hub, node summary, approach registry, and scratch
  provenance committed as `e21a9f2` (`docs(fstar): record A05c positivity and
  binder laws`). No source code or downstream DAG state changed.

## A05c dependency correction and package-call closure audit — 2026-10-14

The earlier A05c scratch note and run-log conclusion that no DAG dependency
change was needed is superseded. The module order makes it impossible for
A05c to consume an alignment proof defined in A05d because A05d depends on
A05c. The dependency-safe plan is now explicit: A05c defines the alignment
proposition/interface and conditional judgments; A05d provides a
proof-bearing adequacy wrapper over the exact pinned package map; A05e proves
semantic substitution; A05g derives use-site evidence and closes package
calls; A05f establishes `LegalEnv` using that closure.

Independent adversarial review found that alignment cannot be limited to
`SchemaFamily`: `SchemaConstructorValue` and `SchemaIndexCallValue` also have
separate dependent argument ASTs/carrier telescopes. A05d now requires
proof-bearing alignment fields for family, constructor, and index-call
signatures, plus constructor result-index/inhabitance laws and index-call
result/equation/codec laws. A05g must consume the corresponding fields for all
three AST forms. The implementation spec already requires checked law fields
in `AdequateSchemaPackages`; the DAG clarifies these are proved contracts
carried by the wrapper, not theorems derivable from arbitrary raw package
fields or identity tokens. This is a proof/module-order correction only; the
all-environments edge theorem and no-per-use-proof interface are preserved.

The production-backed shape probe `/tmp/A05cExactFamilyAlignment.fst` was
independently rerun by root with cache off and split queries:

```sh
opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05c-exact-family-root \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
  src/fstar/v2/src/WorkflowV2.SchemaJudgments.fst \
  /tmp/A05cExactFamilyAlignment.fst
```

Exit 0; all nine modules verified and all VCs discharged. The scratch selects
the exact production family package and constructs a `SchemaBound 0` Nat
argument at its dependent telescope carrier under production `hlist`. Its
`JFamily` constructor still requires `schema_argument_derivation`, so this
validates judgment indices and exact package reuse, not automatic call-site
derivation. It does not cover constructors, index calls, generic context
substitution, or adequacy fields. A05g owns those closure obligations. No
project F* source changed; A05c remains active.

Synchronized state affected: `work_dag.md`, `state.md`, `node_summaries.md`,
`research/A05-2026-10-14/approach_registry.md`, and
`research/A05-2026-10-14/typed_jvalue_scratch.md`. The synchronized correction is committed as `3d11410`
(`docs(fstar): correct schema adequacy proof order`). No F* source changed.


## A05 adequacy result-index and codec coherence audit — 2026-10-14

A follow-up adversarial pass found two subtle package laws that needed a more
explicit acceptance statement. For constructors, the package callback
`constructor_build parent args` returns a value indexed by
`constructor_parent_indices parent args`, while the result AST is
`SchemaFamily parent constructor_result_indices`. The current base package
record provides no law that evaluating/substituting the first-order result
index expressions under the actual well-typed arguments produces the callback
index. A05d must carry this semantic equality; A05g must consume it before
constructing the value judgment. This is necessary for the exact output type
to match the syntax used by downstream graph typing.

The audit also confirms that registry membership and the codec's own
roundtrip/canonicality do not prove that the manifest codec input/output
schema tokens denote the package's actual argument/result carriers. The exact
adequacy wrapper must carry these schema/carrier coherence laws for family
and index-call codecs, and use the exact parent-family codec where applicable.
The spec already requires codec/index coherence; the DAG now names the fields
and their role. No weakening or new user-supplied per-use proof is introduced.
The audits found no module-cycle change: these remain A05d package laws and
A05g consumes them.

Synchronized files: `work_dag.md`, `state.md`, `node_summaries.md`, and this
log. No project F* source changed. The prior DAG correction is committed as
`3d11410`, pinned by `29d0a17`. The adequacy-detail update is committed
as `cec8cd6` (`docs(fstar): specify schema result coherence laws`).

## A05c source integration started — 2026-10-14

The A05c source node remains `in_progress`. The proof-order correction is
committed and pinned (`3d11410`, `29d0a17`); package result-index and
codec/schema coherence laws are committed and pinned (`cec8cd6`, `b156f31`).
Current project source is still the pre-integration baseline. Root is starting
the canonical judgments integration in `WorkflowV2.SchemaJudgments.fst` under
the revised boundary: A05c defines conditional judgment/law interfaces only;
package adequacy fields and call-site closure belong to A05d/A05g. No claim
that the existing placeholder or `/tmp` scratches close A05c. Independent
context and AST-shape probes are running in `/tmp` only; shared source edits
remain with root for this step.

## A05c exact-package family-type rule integrated — 2026-10-14

`WorkflowV2.SchemaJudgments.fst` now defines the conditional
`schema_family_type_judgment`. Its constructor is indexed by the exact AST
`SchemaFamily identity arguments` and carrier, requires the package selected
by the production `select_family_for_type`, one index value in that package's
dependent telescope, and a `schema_argument_derivation` against that same
package. Its result carrier is exactly `package.family_denotation indices`;
the selected package also carries the indexed codec. This rules out a family
judgment that silently selects a different package or carrier.

This is a verified conditional judgment shape, not a canonical A05c closure.
The `jvalue` relation remains a parameterized scaffold and can still be
instantiated with a vacuous relation; it lacks the paired context and all AST
constructors. The constructor also requires its call-site argument proof.
A05d/A05e/A05g must supply package law, semantic transport, and automatic
construction before the resolver can use it. No completeness, generic
soundness, root/port/constant, constructor, index-call, or predicate theorem
is claimed. No `admit` or `assume` was added.

The first verifier attempt rejected the new constructor because the
parameterized datatype's manifest/package binders were not repeated in its
constructor telescope (Error 72: `manifest` not in scope). Rebinding those
parameters explicitly resolved it. Full configured verification then passed:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m \
  make -C src/fstar/v2 verify \
  BUILD_DIR=/tmp/fstar-v2-a05c-family-rule-integration-2 \
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'
```

Exit 0; all 13 configured modules verified and all VCs discharged under F*
2026.03.24. The pre-existing GraphCodec Warning 328 remains. The earlier
fixed version of the same command failed with Error 72, as recorded above.
This is source progress inside A05c, not A05c acceptance. The family judgment and synchronized evidence are committed as `202ab1e`
(`feat(fstar): add exact package family judgment`).

## A05c paired-context lookup scratch; safe pause — 2026-10-14

Root independently verified `/tmp/A05cContextLookup.fst`, a scratch fragment
for carrier-indexed Bound lookup, Root/Port/Constant plumbing, Pair, and
same-carrier equality/conjunction evidence. Command:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 3m fstar.exe \
  --cache_off --split_queries always --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05c-context-lookup-root \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/A05cContextLookup.fst
```

Exit 0; F* verified all seven listed modules and discharged all VCs. Warning
331 says one scratch name is ignored. The scratch `value_base` permits
arbitrary Root/Port/Constant carriers and values; it does not establish root
schema, graph edge typing, constant codec membership/decode, or canonical
context semantics. It also lacks JType-linked context declarations,
Sigma/Refine, package-backed calls, and generic soundness. A proposed context
GADT storing each declaration's JType proof with its value could make Bound
inherit the exact declared AST type, but the mutual GADT positivity,
termination, and integration are unverified. This is a next-step hypothesis,
not a theorem or DAG acceptance change.

Scratch agents were stopped at the user's pause request. No project F* source
changed after `202ab1e`; A05c remains `in_progress`, downstream nodes remain
unstarted, and the canonical DAG's dependency/acceptance contracts are
unchanged. The incomplete local `/tmp/A05cContextGADTProbe.fst` was removed.
The synchronized state-only pause record is committed as `750cb33`
(`docs(fstar): pause A05c at verified checkpoint`); unrelated pre-existing
worktree paths remain unstaged.

## Package-owned redesign documentation — 2026-10-14

- Replaced the active schema-centered theorem text with a draft centered on
  indexed value codecs, typed graph values, package-owned graph decode,
  authorized append history, and exact-prefix recovery.
- Replaced the A00-A36 execution plan with R0-R14 redesign tasks. The former
  A05 schema work is historical and no theorem implementation has restarted.
- Reduced theorem guides, overview guides, state hub, packet, and prior DAG to
  pointers to the two active authorities. The research registry now labels its
  contents historical; node summaries and this log remain evidence only.
- Open decisions D1-D7 are recorded in the spec. No F* source or Makefile was
  changed, and no verifier was run. This entry records a documentation pivot,
  not a completed proof milestone.
