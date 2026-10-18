# F* v2 workflow system: overview and reading guide

**Purpose:** explain the proposed system, its proof architecture, the role of
the implementation packet, and how this design differs from the earlier
typed-plan workflow proposal.

**Status:** explanatory guide. The normative contract is
[implementation_spec.md](implementation_spec.md); the
[implementation_packet.md](implementation_packet.md) is its implementation
and proof-organization companion. Neither means the full system is already
implemented or P0–P16 are proved in source.

## 1. The shortest accurate picture

The design is a typed work-graph engine whose only durable workflow state is a
canonical event journal. It supports three kinds of work:

1. total, pure local F* code;
2. fallible, potentially nondeterministic external operations;
3. total, pure graph generators that produce further finite typed DAGs.

Committed results and generated graphs are reused after recovery. Results
that existed only in memory when a process stopped may be recomputed. The
abstract controller permits independent local/generator work and distinct
external calls to overlap, but commits journal events one at a time. Theorems
are parameterized by proof-bearing contracts for the pinned registry, codecs,
executor, adapter, journaler, and optional artifact store.

Keep four levels distinct:

| Level | What it contains | Authority |
|---|---|---|
| **Normative abstract system** | API signatures, graph semantics, journal transitions, service contracts, P0–P16 | [implementation_spec.md](implementation_spec.md) |
| **Proof and source plan** | Suggested module boundaries, proof order, theorem acceptance checklist, alternatives, examples | [implementation_packet.md](implementation_packet.md) |
| **Existing F* source** | Partial types, graph reasoning, codec proofs, and one chain example | Existing source files; useful substrate, not the full system |
| **Execution plan** | Ordered implementation/proof work with autonomous execution and commit checkpoints | [state/work_dag.md](../../state/work_dag.md); A00/C0/A01/A02 complete, A03 in progress |

~~~mermaid
flowchart LR
  A["Pinned bundle<br/>work, codecs, schemas, adapters"] --> B["Typed graph API<br/>builder + schema resolver"]
  B --> C["GraphDesc syntax<br/>root or generated child"]
  C --> D["Canonical journal events"]
  D --> E["replay(journal)<br/>durable logical state"]
  E --> F["Ready inputs from committed values"]
  F --> G["Local/generator executor<br/>bounded parallel work"]
  F --> H["External adapter<br/>multiple keyed calls in flight"]
  G --> I["Candidate result"]
  H --> I
  I --> J["Serial authorize-and-append path"]
  J --> D
  D -. "crash: load latest complete prefix" .-> E
~~~

A candidate is not visible to dependent nodes until its event commits.
Recovery starts from the committed journal prefix, not volatile controller
memory.

## 2. How to read the documents

Recommended order:

1. This guide for the mental model.
2. [key_correctness_theorems.md](key_correctness_theorems.md) for
   dependent-edge correctness and the theorem spine. It explains why graph
   typing, result provenance, canonical bytes, and recovery are separate.
3. [implementation_spec.md](implementation_spec.md): §§1–2 API and graph
   language; §3 resources; §4 journal/execution; §5 invariants/progress; §6
   theorem contracts; §8 open representations.
4. [implementation_packet.md](implementation_packet.md): §2 interfaces; §3
   module ownership; §4 journal fields; §5 proof order; §6 acceptance checks;
   §§8–9 alternatives and expressibility targets.
5. [graph_and_recovery_guide.md](graph_and_recovery_guide.md) for the
   source-oriented graph construction, generation, and recovery walkthrough.
6. [state/work_dag.md](../../state/work_dag.md) for future implementation/proof
   steps and commit checkpoints. Once explicitly started, work proceeds
   without human-review pauses. It does not override the spec.

For provenance, see [state/research/registry.md](../research/registry.md),
the [A00 source inventory](../research/A00-2026-10-13/source_inventory.md),
and its [integrated refactor map](../research/A00-2026-10-13/source_refactor_map.md).
These are research/status material, not semantics.

### What “original implementation spec” means here

There is no separate **src/fstar/v1/implementation_spec.md** in the current
tree. The history has several predecessor documents with different roles:

- [typed-plan outline](../../../../docs/fstar_typed_plan_workflow_api_outline.md)
  summarizes the earlier prototype API;
- [workflow problem specification](../../../../docs/fstar_pulse_workflow_api_problem_spec.md)
  states the requirements the prototype was meant to satisfy;
- [typed-plan report](../../../../docs/fstar_typed_plan_workflow_api_report.md)
  expands alternatives and records prototype limitations;
- [next research spec](../../../../docs/fstar_workflow_api_next_research_spec_draft.md)
  is a successor brief for dependent results, adapters, resources, and proofs.

This guide compares v2 with that line of work, especially the typed-plan
outline, and separately explains what the implementation packet adds. These
predecessors are not interchangeable.

## 3. Core typed API and graph objects

### Work signatures

The central signature is a fixed input carrier and an output family indexed by
the actual input:

~~~fstar
Work A B
(* B : A -> Type0 *)
~~~

A local function has shape:

~~~fstar
run : x:A -> Tot (B x)
~~~

So a dependent result can be expressed directly as:

~~~fstar
Work nat (fun n -> Prime n)
~~~

The result family carries the refinement; there is no separate postcondition
field for a fact already represented in the type. Expected domain failure
belongs in the result type, often **option (B x)**; the journal has no
separate failure-node state.

| Work form | Pinned package | Abstract execution law |
|---|---|---|
| **Local** | CodeRef, total function, input and indexed output codecs | Pure and total by its type. Compiled code must later refine this identity (P13). |
| **External** | Request codec, reply validator to option (B x), charge bound/metric, adapter contract | Not assumed pure or deterministic. A reply becomes a typed result only after validation at its exact request input. Same-key retries need an effect-safe receipt/reconciliation law (P7). |
| **Generator** | Pure function of exact input, the run's `ChargeMetricIdentity`, and parent allocation, returning GraphDesc and child allocation plan | Admission holds for every legal input/metric/allocation. The pinned metric also governs every generated charge; generated graphs use the same typing, journal, and recovery rules as root graphs (P1/P2/P4). |

OpRef is the typed declaration of an external operation; the adapter is the
service that executes it. Inline authoring and reusable adapter libraries
should produce the same operation contract and obey the same P7 laws. This
lets a workflow keep a one-off adapter nearby or use a library package
without changing workflow semantics.

For external work there are two distinct option layers. The validator's
outer option says whether raw reply bytes are accepted as a typed value. If
the operation itself can return a known domain failure, choose its output
family to be option-valued; then an accepted reply can decode to None. That
None means the operation's known result is failure, not that the adapter does
not know whether the remote effect happened.

### Graph syntax and typed meaning

A GraphDesc is durable first-order syntax: ordered nodes, local node keys,
work references, input wires, and an output wire. Wires refer to root input,
an earlier output, a typed constant encoding, a pair, or a projection. The
descriptor contains no closure, runtime output, host handle, or serialized
typing proof.

The local key identifies a node within one graph descriptor. At execution
time, a graph occurrence path is combined with that key to identify the
global node occurrence; generated-child paths are derived from committed
generator occurrences rather than embedded in the reusable graph syntax.

The pinned registry maps each durable work reference to one exact typed
package. A typed builder and resolver interpret the descriptor into a
dependent port context. If a work has input x:A and output family B, its port
has type B x, where x is the value obtained by evaluating that node's input
wire. Graph typing must preserve those input indices through construction,
encoding, and recovery.

The schema AST is the workflow's own restricted schema-expression language,
represented by F* datatypes. It is **not** the F* compiler AST, quotation,
arbitrary type reflection, or a promise to decide equality between all Type0
values. P1/P2 completeness is for the declared SchemaSupported language.
Unknown equations are rejected unless support is explicitly added with
proofs.

### Strict dependent-edge rule

An output may depend on a node's runtime input, but each work currently has
one fixed input carrier. The graph must prove every node input wire matches
that carrier in every legal graph environment, using declared types and
static schema constraints. It may not inspect one execution or rely on an
external validator to narrow an edge.

For example, a producer that may output vector n for unconstrained n cannot
feed a consumer that accepts only vector 3. The graph must statically prove
n = 3 for every legal environment, or the consumer must accept a general
package such as Sigma n. vector n, or explicit validation work must convert
the value into option (vector 3). One run that happens to choose length three
does not make the graph valid. For external work, the rule ranges over every
value admitted by its declared result family.

The minimal primitives are graph construction and the three Work forms.
Sequencing, fan, lift, case, identity/projection helpers, and similar
conveniences should be library compositions, not additional semantic node
kinds.

## 4. Journal lifecycle, durability, and parallel execution

### The five durable events

| Event | Meaning |
|---|---|
| **RunStarted** | Fixes run identity, pinned registry/root entry, root input, root graph, budget, and root allocation plan. |
| **GraphCommitted** | Stores the exact generated graph bytes and child plan for one generator occurrence. |
| **NodeCompleted** | Stores canonical output bytes and artifact references for completed local work. |
| **CallIntent** | Records that one external call with a stable occurrence key and resume binding may be in progress. |
| **CallOutcome** | Stores the validated external result, evidence, charge, and artifacts for that intent. |

There is no generation-prepared event: pure graph generation can be
recomputed before commit. There is no durable failure event: expected domain
failure belongs in a node's output type. There is no snapshot alongside the
journal; logical state is replay(journal).

Some facts are derived on replay rather than redundantly stored: exact work
identity and input, output type index, node readiness, occurrence ancestry,
enabled actions, and ledger projections. They follow from committed graphs,
work references, prior values, and plans. Packet §4 lists event fields and
derived fields precisely.

### Crash and recovery behavior

| Crash point | Recovery behavior |
|---|---|
| Local code or generator returned only an in-memory candidate | Candidate is lost. Pure local/generator work may be recomputed. This is not exactly-once physical execution before commit. |
| NodeCompleted or GraphCommitted committed | Replay restores the output or exact child topology/plan. The local node is not dispatched again; the generator is not rerun to replace committed topology. |
| External intent committed, no outcome committed | Resume/reconcile the same key and exact request binding under P7. Same-key retries must refer to one logical effect and stable terminal receipt. |
| External outcome committed | Reuse the outcome; do not start the operation again. |
| Append was in flight during crash | Old appends must settle or be fenced before the new controller derives work. Recovery loads the exact latest complete prefix. |

P10 is the abstract journaler's every-cut guarantee: each supported recovery
load returns the latest complete committed prefix and its canonical encoding;
committed events do not disappear; old/stale append requests cannot commit
after the recovery barrier. This covers process-crash recovery under the
journaler contract. It does not claim protection against disk loss, external
journal edits, device corruption, or rollback outside the model. A concrete
SQLite/filesystem journaler must prove refinement (P13).

### Bounded concurrency; serial journal commits

The abstract model starts with one commit coordinator per run. It may claim
multiple independent ready local/generator occurrences in a bounded worker
pool. The adapter may have several distinct keyed calls in flight, with
out-of-order completion. Workers and adapters return candidates; they cannot
mutate durable state or expose results to dependents.

The coordinator replays the current journal, reconstructs exact input and
allocation, checks that the occurrence is still pending, and authorizes one
event at the current head. The journaler appends at most one event at a time.
A stale head requires reload and full reauthorization; changing only the
expected head on an old permit is insufficient. Commit is the visibility
point for a result or child graph. Multiple coordinators need a shared
claim/fencing contract; serial appends alone do not prevent duplicate claims.

## 5. What the theorem families establish

P-names are normative targets, not status badges. Full statements and
dependencies are in [implementation_spec.md §6](implementation_spec.md#6-required-proofs).

| Group | Targets | What the group establishes |
|---|---|---|
| **Identity and graph meaning** | **P0** pinned identity/codecs; **P1** builder soundness/completeness; **P2** graph codec plus typed resolution | Every stored reference selects one coherent package; every accepted graph is a finite typed DAG in SchemaSupported; decoded bytes recover the exact graph and indices. |
| **Journal and dynamic topology** | **P3** guarded replay/WF/canonicality; **P4** graph commit and typed splice; **P5** exact generated graph recovery | Replay is deterministic; generated children become runnable only after exact graph/plan commit; recovery preserves committed topology and allocation. Structural WF is not semantic provenance. |
| **Operation provenance/resources** | **P6** local result equals pinned code output and is absorbing; **P7** external intent/receipt safety; **P8** fuel/charge ledger; **P9** persistent artifact identity, if claimed | Correctly typed bytes also have correct origin. Distinct external keys may be nondeterministic; same-key effects obey an explicit adapter law. P9 is conditional on promising persistent backing-object identity. |
| **Durability/schedule safety** | **P10** exact durable prefix at every cut; **P15** all-permitted-interleaving safety | Store recovery preserves the journal; the controller authorizes every schedule and preserves inputs, claims, accounting, visibility, and no-rerun rules. Durable bytes alone do not prove semantic authorization. |
| **Progress/transfer** | **P11** enabled frontier; **P12** decreasing rank; **P13** concrete refinement; **P14** conditional termination | A started nonterminal state has a legal enabled action or same-key resumable intent; successful appends cannot cycle forever; concrete code inherits abstract results only after simulation/refinement. Termination needs explicit fairness, service response, finite-fuel, and finite-crash premises. |
| **Composite recovery** | **P16** recovered semantic graph correctness | At every authorized crash cut, root/child graphs remain semantically typed; committed values retain local/external/generator provenance; committed work is not redispatched; pending calls resume only under their committed binding. |

Four distinctions are especially important:

1. **P1/P2 typing is not provenance.** A value can have the right type and
   still not be the pinned local function's result.
2. **Codec canonicality is not type compatibility.** Round-trip bytes do not
   prove a producer's dependent output matches a consumer's input.
3. **P3 StateWF is not SemWF.** Replay can check event order, shape, and
   decoded types; semantic origin comes from authorized append history.
4. **P10 is not P16.** Exact-prefix recovery preserves bytes; P15 establishes
   authorization for every abstract schedule; P16 composes these into
   semantic recovery. P13 proves that a chosen concrete runtime refines the
   abstract controller. A concrete recovered-semantics claim composes that
   simulation with P16; P13 does not replace P16.

Contracts are values carrying law proofs. They are theorem parameters, not
unchecked calls to F* assume used to skip system proofs. Environmental facts
the model cannot establish—such as remote deduplication or physical storage
atomicity—must be explicit contract laws and later justified by concrete
refinement.

The current A00–C6 plan targets a generic refinement interface/transfer
theorem. A concrete SQLite, filesystem, executor, or adapter instance must
still prove that it satisfies the interface before claiming that its runtime
inherits the abstract guarantees.

## 6. What the implementation packet contributes

The packet does not define a second semantics. It turns the normative spec's
obligations into an implementation shape:

| Packet section | How to use it |
|---|---|
| **§2 Contract surface** | Schematic signatures for work, graphs, bundle, events, services, controller. Normative detail remains in spec §§2–4. |
| **§3 Module architecture** | Proposed acyclic module graph, ownership/import rules, and mapping from current files to future modules. Names may change; theorem ownership and dependency direction must remain. |
| **§4 Journal rules** | Event payloads, fields derived rather than duplicated, serial append and recovery requirements. |
| **§5 Proof order** | Eight phases: package foundations; graph language; replay; independent provenance/store lemmas; compositions; schedule safety; recovery/progress; concrete transfer/termination. |
| **§6 Acceptance checklist** | Pass conditions for P0–P16. A theorem name or interface declaration does not count as completion. |
| **§§8–9 Alternatives/examples** | Decisions, counterexamples, and six future proof constructions: dependent result, recovery reuse, static analysis over files, generated topology, reusable network adapter, deterministic event queue. |

The proposed module layers are:

1. **Typed foundation/schema:** Kernel, ManifestCore, Schema, GraphResolve,
   GraphCodec.
2. **Pinned package boundary:** Allocation, GeneratorAdmission, Bundle.
   GeneratorAdmission defines a manifest-indexed callback-plus-law package;
   Bundle stores that exact package and proves the identity mapping.
3. **Graph construction/generation:** GraphInterpretation, GraphBuilder,
   Generation.
4. **Journal/event authority:** Journal, Services, Durability, EventAuthority.
5. **Semantic lemmas:** AdapterProvenanceProof, optional Artifacts,
   GraphCommitProof, LocalProvenanceProof, BudgetProof.
6. **Execution/compositions:** ControllerModel, ControllerSafety,
   GraphRecovery, Recovery, Progress, Refinement, Termination, Examples.

These boundaries prevent dependency cycles. The resolver cannot import a
bundle that depends on resolver output; GeneratorAdmission is below Bundle
and ahead of GraphBuilder, so Bundle can pin its law without a cycle; the
journal does not depend on services or semantic ghost witnesses; the
controller model does not depend on theorem modules that prove it safe.

The active [state/work_dag.md](../../state/work_dag.md) is more granular than the
packet: source inventory first, then proof modules, with commit checkpoints
after identity/API, typed graph, journal, provenance/durability,
schedule-safety/progress, and integrated proof work. A00/C0/A01/A02 are
complete and A03 is in progress. Older S2 status prose in historical research records is
provenance; [state.md](state_summary.md) and [work_dag.md](../../state/work_dag.md)
are the current DAG authority.

## 7. Changes from the earlier typed-plan proposal

V2 changes the semantic center from compositional workflow closures to
durable typed graph syntax.

| Topic | Earlier typed-plan proposal | V2 design |
|---|---|---|
| **API center** | Workflow<I,O> closures with pure, then_flow, fork, lift, external, so | Three typed Work forms in finite GraphDesc; builder/resolver establish graph typing. Ergonomic combinators may elaborate to this core. |
| **Dynamic work** | so route/continuation shape and in-memory closure evaluator | Pure generator returns arbitrary finite graph descriptor plus plan. Exact result is committed; root and generated graphs share rules. |
| **Dependent types** | Typed endpoints and candidate postconditions, with unresolved proof-boundary questions | Work A B indexes result family by actual input. P1 requires universal edge compatibility; P2 reconstructs typing after decode. |
| **External effects** | external declaration; prototype runner uses dummy adapters | Replies remain nondeterministic. Intent, key, exact binding, validator, and P7 receipt/effect law govern retries and outcomes. A dummy queue is an example adapter, not semantics. |
| **Durability** | Event-sourced reducer and manifest; outline acknowledges incomplete all-cut continuation/runtime refinement | One canonical journal is sole durable state. P10 every-cut prefix; P15 schedule authorization; P16 semantic recovery; P13 concrete refinement. |
| **Parallelism** | Dummy queue demonstrates immediate/deferred adapters | Bounded independent local/generator execution and multiple distinct in-flight calls; serial journal commits. |
| **Resources/files** | Blob/BlobTree and artifact-record ideas without complete materialize-run-collect path | Typed resource refs and pinned interpretations may represent files, trees, network/database handles, etc. P9 proves restart identity when promised. |
| **Proof coverage** | Tests/proof ledger with continuation, artifact, parser, runtime gaps | P0–P16 targets; no assume/admit may discharge system theorems; concrete host facts need P13 evidence. |
| **Completeness** | API expressivity through prototype combinators | Complete only for declared SchemaSupported language, not arbitrary erased F* Type0 graphs. |

The retained goals are typed composition, local/external work, dynamic
routing, durable results, budgets, and reusable adapters. Their representation
and recovery must now share one formal graph and journal model. Fork/lift are
not rejected as conveniences; they leave the trusted primitive set so their
behavior can be derived from the smaller graph core.

Two apparent differences are better understood as representation and contract
choices, rather than missing core features:

- **Relation to so:** in the intended use—compute arbitrary finite wiring
  over available registered work—a v2 generator is ordinary total F* code
  that computes GraphDesc at runtime. It can choose node count, branches,
  joins, and wiring; it is not restricted to a fixed topology template or a
  linear list. The graph must still be a DAG whose nodes and types resolve in
  the pinned SchemaSupported language, and generation is subject to its
  allocation/budget. This is a type/catalog boundary, not a topology
  limitation. Manufacturing new unregistered executable code or arbitrary
  types outside the declared language would be a different requirement.
- **External failure versus uncertain outcome:** the API directly represents
  known operation failure in an option-valued result family. The validator's
  outer option and the operation's result option have different meanings, as
  described above. A lost reply after a possible remote effect is not a known
  domain failure, however. P7 requires the adapter to safely query, deduplicate,
  or reconcile the same committed key; its liveness theorem is conditional on
  adapter progress. An irreconcilable external effect is outside the contract.
  A separate durable Unknown node state is unnecessary for admitted adapters:
  the journal retains the pending CallIntent until a terminal CallOutcome is
  committed, while the adapter contract handles uncertainty about the effect.

## 8. Representative workflows and their proof targets

These are **proof-bearing expressibility targets**, not tests and not claims
that current source runs them end to end.

### Dependent local result

Declare work with output family fun n -> Prime n, an indexed codec for that
family, and a consumer accepting that exact result. P0 pins code/codec
identities; P1/P2 type the edge and reconstruct its index; P6 proves committed
bytes came from the pinned function; P16 preserves this after recovery.

### Static analysis over files

Represent input as a list of typed file/tree references. An external
operation can materialize them in an isolated workspace, invoke a CLI
analyzer, collect and parse a report, and validate it into a typed result.
This is an adapter interpretation of artifact types, not a primitive
assumption that every artifact is an in-memory Blob. If the workflow promises
the files survive restart as the same logical objects, include P9's
publish-before-commit and same-version resolution laws. A typed reference
alone does not guarantee physical file durability.

### Nondeterministic network/model request

An operation declaration fixes request/result types and reply validation.
Distinct call keys may produce different accepted results. Retries of one key
follow the exact committed intent and must reconcile to the same logical
receipt. This is why external work is not modeled as a pure function.

### Data-dependent generated graph

A pure generator may choose a different finite number of nodes, branches, or
joins from its input. It must prove admission for every legal input and
allocation, not just a sample. P4 commits exactly its graph and plan before
children become visible; P5 recovers that exact graph.

### Deterministic dummy event queue

A scripted adapter may return calls in a chosen out-of-order schedule to
exercise retry/recovery traces. It is a proof example for P7/P15 interfaces,
not a replacement for generic theorems or proof of real provider behavior.
Packet §9 also includes recovery reuse and reusable adapter-library examples.

## 9. Current source: useful base, incomplete system

The normative spec says existing F* files are partial evidence and claims no
P0–P16 theorem is discharged. The seven current modules contain:

| Existing module | Useful material | Important limit |
|---|---|---|
| [WorkflowV2.Kernel.fst](../current_implementation/src/WorkflowV2.Kernel.fst) | Identities, plain/indexed codecs, work refs, CodeRef/OpRef/generator declarations, Work, graph syntax, restricted schema AST, typed artifact-token syntax, and metric fields on budget/op/generator | No complete manifest, schema denotation/resolver, metric-coherence proof, abstract controller, or full service contracts. Artifact packing is candidate syntax until its exact manifest package validates the identity/carrier link. |
| [WorkflowV2.Identity.fst](../current_implementation/src/WorkflowV2.Identity.fst) | Identity equality and packed work/codec lookup | No complete manifest projection, root/schema links, or P0 bundle/reload proof. |
| [WorkflowV2.Graph.fst](../current_implementation/src/WorkflowV2.Graph.fst) | Typed wires, dependent port telescope, graph/DAG predicates, allocations, generator-example support | General builder boundary includes assume/admit; generic P1 and v2 resolver remain incomplete. |
| [WorkflowV2.GraphCodec.fst](../current_implementation/src/WorkflowV2.GraphCodec.fst) | First-order graph syntax encoding/decoding and round-trip/canonicality lemmas | Syntax proof only; not P2 typed reconstruction. |
| [WorkflowV2.Journal.fst](../current_implementation/src/WorkflowV2.Journal.fst) | Five event shapes and action vocabulary | No guarded apply/replay, StateWF, semantic authorization, journal codec, or durable recovery. |
| [WorkflowV2.GenerationExample.fst](../current_implementation/src/WorkflowV2.GenerationExample.fst) and [WorkflowV2.ChainProof.fst](../current_implementation/src/WorkflowV2.ChainProof.fst) | One input-shaped chain and generator-admission proof | Example-specific; not generic graph completeness, universal resolution, or P4 journal commit. |

The repository records prior F* verification runs for the existing module
set, including syntax-codec and chain-example results. That means those
checked declarations/proofs were accepted by F*; it does **not** make an
admit/assume true or establish P0–P16. The current work DAG is not started;
its latest planning pass changed no F* source and ran no verification.

There is no complete v2 runner, generic resolver, replay machine, abstract
controller, physical serial journaler, real CLI/network adapter, or concrete
P13 implementation-refinement proof yet. This is an implementation-ready
**abstract design and proof plan**, not an executable end-to-end runtime.

## 10. Glossary

| Term | Meaning |
|---|---|
| **Pinned bundle/manifest** | Immutable mapping from durable identities to one code, operation, generator, codec, schema, resolver, and root-entry package. |
| **SchemaSupported** | Declared schema language for which graph build/resolve completeness is promised. |
| **GraphDesc** | First-order serializable graph syntax; not itself a typed graph witness. |
| **Typed graph / port telescope** | Interpretation recording each node's exact input and input-indexed output family. |
| **StateWF** | Replay-checkable structural validity of event-derived state. |
| **SemWF** | Ghost/history invariant that events came from authorized pinned computation or adapter contracts; not serialized proof bytes. |
| **Candidate** | Volatile computation/adapter return awaiting authorization and append; not visible to dependents. |
| **Commit** | Successful serial append of one authorized event; the durable visibility point. |
| **Every cut** | Any supported process-crash/recovery-load point in the journaler model, subject to its store assumptions. |
| **P13 refinement** | Proof that a chosen concrete runner and services simulate/refine the abstract system; a component name alone is not such a proof. |

