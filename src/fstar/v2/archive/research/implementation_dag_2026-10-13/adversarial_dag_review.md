# Adversarial review: future abstract implementation DAG

Date: 2026-10-13  
Scope: planning review only. Normative basis: `implementation_spec.md` and
`key_correctness_theorems.md`; `implementation_packet.md`, DAG, and current
`.fst` files audited only after deriving targets. No F* execution or host
runtime is in this objective.

## Required DAG coverage checklist

Treat each item as an independently reviewable proof layer. Each gate must
inspect theorem statements, dependency graph, source proof paths, and trusted
inputs; declarations, examples, and tests are not proof evidence.

- [ ] **T0 — theorem and trust inventory.** Enumerate P0–P16; classify each
  input law as proved package theorem, explicit conditional service contract,
  or deferred concrete refinement. Audit complete transitive theorem paths
  for `assume`, `admit`, axioms, unchecked solver success, extraction holes,
  and opaque equality. No result marked discharged from a signature alone.
- [ ] **T1 — identity, manifest, codec, and root package.** Prove exact
  projection from actual tables, injectivity/uniqueness across identity
  domains, complete link closure, schema and codec coherence, canonical
  indexed codecs, charge metric coherence, root constructor linkage, and
  same-manifest abstract reload. Keep host binary identity out of this gate;
  that is P13 and outside this objective.
- [ ] **T2 — restricted schema language.** Define the custom first-order
  schema AST, binder/substitution semantics, legal-environment semantics,
  normalization/equality derivations, and exact manifest equations. Prove
  termination, denotational soundness, and completeness for exactly
  `SchemaSupported`. It is a custom restricted schema AST; it is **not** the
  F* compiler AST, and must not claim arbitrary `Type0` equality or compiler
  reflection. Any added solver/rule needs separately pinned soundness and
  completeness.
- [ ] **T3 — resolver and dependent edge theorem.** Prove every input wire
  denotes the exact fixed `A_k` in every legal environment; output is
  `B_k(actual_input)`. Prove builder/resolver soundness and completeness for
  the same supported language, with typed graph isomorphism. Include root,
  constants, pair/projection/composite wires, indexed outputs, refinements,
  constants in output wire, and all earlier ports. No edge proof payload,
  runtime sample, validator narrowing, or equality by identity string alone.
- [ ] **T4 — graph codec and exact typed reconstruction.** Prove canonical
  encode/decode, exact ordered syntax preservation, and resolver reconstruction
  of work, values, ports, edges, and dependent indices for root and child
  graphs using the same pinned resolver. Separate byte canonicality from
  semantic typing.
- [ ] **T5 — generator admission, allocation, and splice.** Prove universal
  generator law for every legal input, metric, and allocation; exact output
  graph and graph-local plan; path-derived child occurrences; local plan fit;
  typed boundary substitution; global uniqueness and acyclicity; hidden
  children before commit. Prove zero-fuel generator cannot emit nested
  generators and nested generators receive positive fuel.
- [ ] **T6 — event transition and replay.** Define initial state, each guarded
  event, expected-head authorization shape, state-WF, terminal absorption,
  deterministic replay, and canonical event/journal codec. Keep replay
  structural; do not claim it establishes `SemWF` or computation origin.
- [ ] **T7 — independent semantic authority lemmas.** Prove exact local result
  origin/reconstructed input (P6); keyed adapter receipt/effect safety (P7);
  generator commit authority and commit-before-visibility (P4); and serial
  store/cut properties (P10) as separable obligations. P7 must bind full
  `(operation identity, NodeOccurrence)` key plus exact canonical request and
  resume bytes to one terminal receipt. Distinct keys may be nondeterministic.
- [ ] **T8 — resource and charge contracts.** Prove occurrence allocation
  projections, metric-consistent charge/fuel equations, reserve/settle once,
  no duplicate settlement (P8). Keep P9 optional and explicit: if resource
  identity is promised, prove publish-before-reference, exact typed inventory
  projection, immutable version, and same logical object after restart. Replay
  must do no resource I/O.
- [ ] **T9 — controller and scheduler model.** Define exact ready-input
  reconstruction from referenced committed dependencies and prove
  `ReadyInputAgreement` with full graph evaluation. Define unique live claims,
  fresh epochs, bounded independent workers, multiple distinct adapter
  requests, serial commit coordinator, current-head reauthorization, stale
  result/permit rejection, recovery barrier, and commit-only visibility.
- [ ] **T10 — all-schedule safety (P15).** Induct over every permitted launch,
  completion, retry, append, crash, and recovery interleaving. Establish
  universal authorization, typing, graph WF, ledger, SemWF, and no
  redispatch after commit. Safety must not assume fairness. Explicitly reject
  duplicate live claims, crossed inputs/allocations, stale append/callback,
  mismatched outcome, early child execution, and outcomes completing in
  arbitrary order but settling the wrong intent.
- [ ] **T11 — every-cut transfer and semantic recovery (P10/P16).** For each
  history and cut, prove loaded bytes are the canonical latest committed
  prefix; all old appends committed or aborted before load; no old append
  crosses the barrier; recovery equals replay; authorized ghost witnesses
  restrict to that prefix. Then prove exact graph, local/external/generator
  provenance, committed work reuse, and same-key pending intent recovery at
  arbitrary cuts. Do not collapse this into “replay succeeds.”
- [ ] **T12 — progress proof layer.** Prove enabled frontier (P11) separately
  from eventual progress. Prove each successful post-start append lowers
  lexicographic `(G,U,W)` rank (P12). State conditional P14 assumptions
  explicitly: weak fairness, result return, append/retry progress, adapter
  resolution, total pure work/validation, finite initial fuel, finite crashes,
  and any needed resource service progress. Liveness assumptions must not
  leak into P15 safety.
- [ ] **Human gates.** Gate A after T1–T4 (identity and graph semantics).
  Gate B after T5–T8 (generation, events, semantic authorities, ledgers).
  Gate C after T9–T11 (scheduler, interleavings, arbitrary-cut recovery).
  Gate D after T12 (conditional liveness and final theorem/dependency audit).
  At each gate require independent review, source theorem-path audit, and
  explicit open-obligation list. No gate promotes status based on packet
  prose or current source resemblance.

## Dependency and counterexample audit

Required dependency spine:

```text
P0 -> schema calculus -> P1 -> P2 -> P3
P0/P1/P2/P3 -> P4; P0/P2/P3 -> P6, P7
P0/P2/P3 -> P10
P3/P4/P7 -> P8; P2/P4/P10 -> P5
P0-P8 + P10 -> P15
P5/P6/P7/P10/P15 (and P0-P8 facts) -> P16
P3-P8 -> P12; P1-P8 + P15 -> P11
P11/P12 plus explicit fairness/service premises -> P14
P13 concrete refinement deferred; not prerequisite to abstract P16.
P9 joins P15/P16 only when promising persistent resource identity.
```

Audit findings / dependency traps for DAG author:

1. **Do not derive edge acceptance from execution.** Counterexample:
   producer returns `Sigma n. vector n`; consumer accepts `vector 3`; one
   observed call returns `n=3`. Must reject unless static schema/context proves
   equality for every legal environment. Validator accepting only `n=3` does
   not narrow `LegalEnv`.
2. **Quantify external and generated outputs correctly.** Legal environments
   include every inhabitant of declared output family, not merely validator
   outputs. Generated graph is checked at exact reconstructed root input,
   with its internal predecessor values universally quantified. Sampling one
   generator input or one child topology cannot establish admission.
3. **Don't conflate graph soundness with result provenance.** Canonical
   `NodeCompleted` bytes can decode to a well-typed but wrong local result;
   indexed decoding does not prove equality to `CodeRef.run`. An external
   validator result can have right type but wrong key/input/receipt. A
   `GraphCommitted` descriptor can be well typed but not be exact generator
   output. Require P4/P6/P7 witnesses and P15 authorization.
4. **Don't let journal structure prove semantic authorization.** A fabricated
   structurally legal event may replay. `StateWF` is not `SemWF`; P10 byte
   prefix is not provenance. P16 needs authorized history witnesses carried
   through each cut.
5. **Generator visibility is an append fact.** Child nodes must not enter
   frontier before exact `GraphCommitted` is durable. On recovery reuse exact
   graph bytes and plan; never rerun generator to select topology or
   allocations. A cut after generator calculation but before append may
   recompute; a cut after commit may not.
6. **Arbitrary cut means every append race.** Crash can occur before append,
   at commit before acknowledgement, during another append request, or after
   load. Require barrier settling/fencing old requests before new actions.
   Otherwise a stale `NodeCompleted` may commit after restart loaded prefix,
   causing producer rerun or inconsistent frontier. Same for stale permits
   made against an old head.
7. **No replay of completed work is trace property.** Replay state alone shows
   completed nodes are disabled, not that an old worker was never invoked
   again. P15 must reject dispatch after completion and epoch-stale callbacks;
   P16 transfers trace fact plus replay frontier fact.
8. **Adapter retry safety is not “same intent.”** Lost reply after remote
   effect plus redispatch can double-charge or double-effect. Require stable
   key dedupe/status or operation-specific idempotence/reconciliation, exact
   receipt tuple agreement under overlap/restart, immutable binding, and
   per-key liveness premise. Distinct keys can complete out of order and must
   settle independently.
9. **Controller/service races need explicit semantics.** Two workers cannot
   claim same occurrence; two coordinators require shared fencing beyond a
   serial journal. Late callbacks from old epoch rejected. Multiple adapter
   intents allowed; one slow key cannot block unrelated completed key.
   Journal append stays serial and reauthorizes against exact current head.
10. **Readiness has a hidden evaluator lemma.** Spec runner may schedule node
    from only referenced committed outputs, while source graph evaluator
    accepts full environment. Prove sparse reconstruction equals typed full
    evaluator for every compatible environment; otherwise scheduler's input
    and theorem's input can differ.
11. **Rank proof must cover zero fuel and all schedules.** Positive fuel
    commits lower total unexpanded fuel; zero-fuel root generator must lower
    unexpanded count and cannot generate nested generators. Local/external
    phase ranking must strictly drop per successful append. P11 frontier
    existence alone gives no eventual response.
12. **Manifest is a projection, not parallel user assertion.** Reject
    duplicate identity before sorting; full identity uniqueness must pin
    complete packages, not only `DurableWorkRef`. Digest equality needs
    collision premise. Same identity behind changed implementation or codec
    invalidates recovery.

## Assumptions and theorem targets

| Target kind | Inputs allowed | Must not be hidden as |
|---|---|---|
| Abstract package contracts | Proof-bearing records for pinned total code/generator, codecs, schema denotation/equations, exact registry projection/reload | F* axioms, `assume`, `admit`, second editable signature table |
| Journaler P10 | Atomic serial prefix, canonical load, monotonicity, barrier and no external mutation | “SQLite is durable” or a call to `recover` assumed correct |
| Adapter P7 | Keyed safe-effect/reconciliation, exact receipt correlation, eventual per-key outcome under explicit conditions | Exactly-once transport, deterministic operation, or “same request means same effect” |
| P9 resource extension | Typed immutable resource versions and restart-stable resolution | Typed opaque ref silently implying durable object identity |
| P14 liveness | Weak fairness, service/result completion, finite crashes/fuel, capacity | P11 frontier existence or a prompt assertion |
| P13 concrete refinement | Host, worker pool, compiled-code, loader, filesystem/network facts | Part of abstract theorem or this abstract-only objective |

External contract values are explicit theorem inputs carrying proofs; abstract
theorems are conditional on inhabiting those records. Their laws are not
system theorems unless proved for the concrete instance. This review does not
require a host runtime or P13 implementation.

## Missing milestones / DAG risks

`work_dag.md` is a good specification-design DAG, but it cannot serve as the
future proof-execution DAG: its nodes mark targets designed, not F* terms
verified. `implementation_packet.md` architecture is broad and mostly
acyclic, but future execution needs smaller source-proof milestones and the
gates above. Specifically split:

- schema AST/denotation/substitution; each judgment soundness; equality
  calculus completeness; resolver; builder prefix characterization; graph
  codec reconstruction;
- generator universal admission; allocation lift; splice substitution;
  append authority and visibility;
- replay transition induction; local provenance; P7 binding/receipt/effect
  safety; charge ledger; P10 cuts/fence;
- `ReadyInputAgreement`; controller state/action definitions; one-claim and
  epoch lemmas; exact-head append; each crash interleaving; P15 composition;
  ghost-witness prefix restriction; P16 composition;
- separate P11/P12/P14 proofs so fairness does not contaminate safety.

Dependency correction to preserve: P15 can use P10 as a journaler contract,
but P10 alone cannot establish P15 authorization. P16 needs P5 explicitly
(exact committed generated graph/plan), plus P6/P7 and P15 trace authorization.
P13 and P14 are outside the requested abstract core; keep them as deferred
branches, with P14 conditional on P13 only if concrete termination is later
claimed. P9 is a conditional extension, never silently required for opaque
artifact values.

## Strongest objection

Current `.fst` source is not a partial proof of this full system: it contains
explicit `assume` boundaries for graph builder types/operations and `admit()`
for start/add/finish properties (`WorkflowV2.Graph.fst`, lines 418, 421,
523, 525, 910, 929, 942, 956). Graph codec syntax round-trip or the chain
example cannot bridge this gap. More broadly, a theorem parameterized by
proof-bearing contract records proves only a conditional abstract theorem;
it does not show the records can be instantiated by a real system. DAG must
state this trust boundary plainly and must not call contract declarations
“verified end-to-end.”

## Unresolved obligations

- Exact source-level universe-safe representation and proof of custom schema
  AST soundness/completeness, including locally nameless substitution and
  refinement equivalence.
- Feasibility of proving full builder completeness for all and only
  `SchemaSupported` graphs while making public add/finish reject precisely
  unsupported prefixes; preserve typed isomorphism, not raw label/wire
  isomorphism.
- Acyclic executable/proof ownership for universal `GeneratorMember`: pin
  exact generator law before resolver/builder relies on it; avoid a cycle
  among Bundle, GeneratorAdmission, GraphResolve, Allocation, and Builder.
- Formal controller transition semantics where calls can overlap across
  recovery yet one run has one commit coordinator; define claim ownership,
  duplicate callbacks, append requests, and adapter restart in one trace model.
- Exact P10-to-P15-to-P16 cut-transfer interfaces: distinguish store history
  witness, semantic append witness, replay state, and controller trace.
- Whether `SchemaSupported` has any hidden restriction from chosen manifest
  constructors or resource limits. API remains unbounded in finite topology;
  deployment admission limits cannot silently narrow it.
- What contracts are intended to be constructed for actual total pure F*
  programs, external validators, generator plans, and run identity uniqueness.
  Abstract proof can quantify over records, but examples need actual records.
- Trusted base audit for admitted F* primitives, termination checker,
  extraction/compiler assumptions, and any proof-producing normalization code.

## Next investigation

Before creating execution DAG, independently map every P0–P16 theorem to
exact F* module/interface owner and proof dependency, then write a minimal
model of `LegalEnv`, sparse input reconstruction, and controller cut history.
Use counterexample traces (not tests as proof) to challenge P4/P7/P10/P15/P16
interfaces. Obtain Gate A review of the custom schema language and universal
dependent-edge theorem before source implementation begins.
