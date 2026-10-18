# S2-00 — Source and theorem evidence ledger

Audit date: 2026-10-13. Read-only audit of F* source, normative spec, theorem
guide, and historical state. No F* verifier was run. “Historically checked”
means a prior successful full build is recorded in the repository log; this
audit did not run it.

## Evidence classes

- **Proved lemma (historical check):** proof body exists without admit or
  assume, and a past full build records the module as checked.
- **Declaration:** type, record, or theorem signature states a shape/premise;
  it does not prove the system property under review.
- **Assume/admit:** source explicitly trusts a declaration or admits a goal.
- **Contract target:** required by the spec but not implemented/discharged.
- **Host refinement:** concrete executable or storage service must be proved
  to implement an abstract contract.
- **Absent:** no corresponding source transition, executor, or theorem found.

No P0–P16 system theorem is fully discharged by current source. Some useful
supporting lemmas and one concrete generator example have historical
verification evidence; these do not establish the generic theorem.

## P0–P16 traceability

| Target | Evidence and status | Remaining gap |
|---|---|---|
| **P0 pinned identity/codecs** | Partial proved lemmas plus declarations/host refinement. Exact work and codec lookup/membership: [Identity.fst:100](../../current_implementation/src/WorkflowV2.Identity.fst#L100), [Identity.fst:117](../../current_implementation/src/WorkflowV2.Identity.fst#L117), [Identity.fst:203](../../current_implementation/src/WorkflowV2.Identity.fst#L203). Input codec canonicality projection: [Identity.fst:311](../../current_implementation/src/WorkflowV2.Identity.fst#L311). Codec laws are fields: [Kernel.fst:90](../../current_implementation/src/WorkflowV2.Kernel.fst#L90). | No proof binds bundle identity to canonical manifest contents. The bundle carries work/value-codec registries ([Identity.fst:288](../../current_implementation/src/WorkflowV2.Identity.fst#L288)); validators and graph codecs can be nested in resolved work objects ([Kernel.fst:117](../../current_implementation/src/WorkflowV2.Kernel.fst#L117), [Kernel.fst:167](../../current_implementation/src/WorkflowV2.Kernel.fst#L167)). Source has no manifest binding that proves these exact nested objects, graph resolver, and root entrypoint belong to the bundle identity; no restart reload proof. Uniqueness is a supplied registry law. Host identity-to-binary correspondence belongs to P13. |
| **P1 typed graph builder** | Typed declarations and helper lemmas, but builder has assumptions/admissions. Typed ports and graph witness: [Graph.fst:150](../../current_implementation/src/WorkflowV2.Graph.fst#L150), [Graph.fst:600](../../current_implementation/src/WorkflowV2.Graph.fst#L600), [Graph.fst:763](../../current_implementation/src/WorkflowV2.Graph.fst#L763). Assume boundary: [Graph.fst:418](../../current_implementation/src/WorkflowV2.Graph.fst#L418), [Graph.fst:523](../../current_implementation/src/WorkflowV2.Graph.fst#L523). Admitted laws: [Graph.fst:908](../../current_implementation/src/WorkflowV2.Graph.fst#L908). One chain example: [ChainProof.fst:252](../../current_implementation/src/WorkflowV2.ChainProof.fst#L252). | At S2-00, route selection was open. S2-01 later selected the manifest schema resolver and `SchemaSupported` boundary; source-level soundness/completeness remains unproved. |
| **P2 graph codec/resolution** | Syntax encoder/parser and roundtrip/canonicality historically checked: [GraphCodec.fst:284](../../current_implementation/src/WorkflowV2.GraphCodec.fst#L284), [GraphCodec.fst:289](../../current_implementation/src/WorkflowV2.GraphCodec.fst#L289). | No resolve_graph reconstructs typed wiring/proofs from bytes. Syntax roundtrip does not prove dependent edge equality or typed witness reconstruction. |
| **P3 replay/WF/terminal** | Event/action/state declarations: [Journal.fst:47](../../current_implementation/src/WorkflowV2.Journal.fst#L47), [Journal.fst:82](../../current_implementation/src/WorkflowV2.Journal.fst#L82), [Journal.fst:107](../../current_implementation/src/WorkflowV2.Journal.fst#L107). | No replay/apply, transition legality, WF preservation, terminal absorption, or journal codec theorem. |
| **P4 graph commit/substitution** | Generator/allocation/admission declarations: [Kernel.fst:141](../../current_implementation/src/WorkflowV2.Kernel.fst#L141), [Graph.fst:799](../../current_implementation/src/WorkflowV2.Graph.fst#L799), [Graph.fst:881](../../current_implementation/src/WorkflowV2.Graph.fst#L881). Chain proof constructs one typed graph and exact generator admission: [ChainProof.fst:252](../../current_implementation/src/WorkflowV2.ChainProof.fst#L252), [ChainProof.fst:317](../../current_implementation/src/WorkflowV2.ChainProof.fst#L317). | No generic authorized journal transition, commit-before-visibility, typed substitution, global DAG preservation, or ledger-conservation proof. |
| **P5 exact graph recovery** | GraphCommitted event shape only: [Journal.fst:57](../../current_implementation/src/WorkflowV2.Journal.fst#L57). | No recovery function resolves committed graph/plan or proves committed topology is reused without regeneration. |
| **P6 local provenance/no rerun** | CodeRef and completion event declarations: [Kernel.fst:110](../../current_implementation/src/WorkflowV2.Kernel.fst#L110), [Journal.fst:63](../../current_implementation/src/WorkflowV2.Journal.fst#L63). | No append authorization ties bytes to CodeRef.run; no replay decode at reconstructed input, absorbing completion state, or no-rerun theorem. |
| **P7 external safety/progress** | Operation and intent/outcome declarations: [Kernel.fst:117](../../current_implementation/src/WorkflowV2.Kernel.fst#L117), [Journal.fst:69](../../current_implementation/src/WorkflowV2.Journal.fst#L69). | No adapter, keyed in-flight protocol, safe retry/dedup/status/idempotence proof, outcome correlation, effect safety, or liveness theorem. |
| **P8 charge/fuel safety** | Graph-local allocation predicates and chain plan proof: [Graph.fst:799](../../current_implementation/src/WorkflowV2.Graph.fst#L799), [ChainProof.fst:277](../../current_implementation/src/WorkflowV2.ChainProof.fst#L277); journal allocation records: [Journal.fst:30](../../current_implementation/src/WorkflowV2.Journal.fst#L30). | No replay-derived ledgers, reservation/settlement transitions, conservation, or single settlement theorem. |
| **P9 artifact safety** | Artifact-reference declaration only: [Journal.fst:39](../../current_implementation/src/WorkflowV2.Journal.fst#L39). | No artifact store, publish-before-reference protocol, typed restoration, or same-object recovery proof. |
| **P10 every-cut durability** | Spec contract laws/theorem: [implementation_spec.md:1514](../../schema_era_2026-10-14/implementation_spec.md#L1514), [implementation_spec.md:1818](../../schema_era_2026-10-14/implementation_spec.md#L1818). Journal says replay remains open: [Journal.fst:107](../../current_implementation/src/WorkflowV2.Journal.fst#L107). | No journal codec, serial append/load implementation, storage model, crash-cut recovery, or concrete persistence refinement. Graph syntax codec is not journal durability. |
| **P11 frontier/no-stuck** | Action vocabulary only: [Journal.fst:95](../../current_implementation/src/WorkflowV2.Journal.fst#L95). | No reachable-state frontier, enabledness, or no-stuck proof. |
| **P12 no infinite progress cycle** | Spec rank argument only: [implementation_spec.md:1820](../../schema_era_2026-10-14/implementation_spec.md#L1820). No journal transition rank in source. | No event rank-decrease or infinite-append exclusion proof. |
| **P13 concrete refinement** | Host-refinement target only: [implementation_spec.md:1821](../../schema_era_2026-10-14/implementation_spec.md#L1821), [implementation_spec.md:1844](../../schema_era_2026-10-14/implementation_spec.md#L1844). | No controller, worker pool, adapter, journaler, extraction, or runtime-refinement module among current seven source files. |
| **P14 conditional termination** | Spec-only conditional target: [implementation_spec.md:1822](../../schema_era_2026-10-14/implementation_spec.md#L1822). | No scheduler/fairness, service progress, finite-crash, or root-output reachability theorem. Individual Tot callbacks do not prove system termination. |
| **P15 all-interleaving safety** | Absent. Journal action names are declarations only: [Journal.fst:95](../../current_implementation/src/WorkflowV2.Journal.fst#L95). The theorem guide identifies ReadyInputAgreement as a missing proof goal ([key_correctness_theorems.md:233](../../schema_era_2026-10-14/key_correctness_theorems.md#L233)). | No controller state, claims, interleaving relation, stale-head reauthorization, committed-only visibility, or all-schedule proof. Must also prove dependency-local input reconstruction equals full graph evaluation, independent of unrelated unfinished ports. |
| **P16 recovered semantic correctness** | Composite target only: [implementation_spec.md:1718](../../schema_era_2026-10-14/implementation_spec.md#L1718), [implementation_spec.md:1824](../../schema_era_2026-10-14/implementation_spec.md#L1824). | No SemWF, authorized history, store cut, provenance, or recovery theorem. P9 is optional only for persistent backing-object identity. |

## Cross-cutting facts

- Kernel contains type/contract vocabulary. In particular, op_ref validator
  returns option (output x), so external outcomes need not be pure or
  deterministic ([Kernel.fst:117](../../current_implementation/src/WorkflowV2.Kernel.fst#L117)).
- Identity proves useful exact lookup results, but uniqueness is a supplied
  law and the bundle is not bound to canonical manifest content
  ([Identity.fst:284](../../current_implementation/src/WorkflowV2.Identity.fst#L284)).
- Graph has typed port/telescope and topological helper lemmas; builder
  assumptions/admissions remain. No executable resolver constructs the typed
  witness from GraphDesc ([Graph.fst:763](../../current_implementation/src/WorkflowV2.Graph.fst#L763)).
- GraphCodec proves graph syntax roundtrip/canonicality, not typed witness
  recovery. ChainProof proves only the concrete chain family/admission.
- Journal explicitly leaves replay open and has no transition implementation
  ([Journal.fst:107](../../current_implementation/src/WorkflowV2.Journal.fst#L107)).

## Historical verification

The log records a successful seven-module verification at
[run_log.md:377](../../history/run_log.md#L377)
with warnings 271/328. It supports the syntax codec and chain admission only;
it explicitly leaves generic resolution and builder admissions open. The S2
spec/DAG revision ran no F* check ([run_log.md:451](../../history/run_log.md#L451)).
S2-00 ran no F* command.

## Consistency correction

The normative spec said P9 artifact backing was optional but made P15/P16
depend on P0-P10, which includes P9; its P16 composition sentence also omitted
P10. Reconciled this according to the spec's explicit optional-artifact intent:
base P15/P16 treat artifact refs as opaque and depend on P0-P8 and P10; add
P9 only when claiming durable backing-object identity. Corrected the theorem
guide dependency and stale spec line links. This was a consistency repair,
not a DAG or F* source change.

## Current S2 refinement note — 2026-10-13

This ledger is an S2-00 snapshot, not the later graph-design decision. S2-01
selected the canonical schema resolver and `SchemaSupported` boundary; S2-03
then specified `LegalEnv`, `PrefixSupported`, and the full-declared-output
external quantifier. S2-03 resolves the earlier validator-postcondition option
in favor of static type/schema facts only. The dated S2-01 amendment and
[S2-03 report](S2-03-typed-graph-contract.md) preserve that change without
rewriting what S2-00 knew. Current theorem line references above point to the
normative spec after those edits.

## Independent audit inputs

- [Graph/identity audit](/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-00-graph-audit.md)
- [Executor/journal/durability audit](/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-00-executor-audit.md)
- [Theorem/evidence traceability audit](/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-00-theorem-map.md)

Agent reports are evidence inputs. This file is the durable integrated S2-00
artifact.
