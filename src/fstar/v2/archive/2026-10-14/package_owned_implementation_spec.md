# F* workflow v2: package-owned typing and journal invariants

**Status: archived redesign draft for discussion.** This document was the package-owned proposal before the top-down specification. It is not an implementation claim. The current F* sources still contain schema-specific modules and admitted builder laws; the redesign has not yet been encoded or proved. The current theorem status is tracked in [work_dag.md](../../state/work_dag.md).

**Scope:** specify where each correctness obligation belongs, state the proof targets, and keep unsettled choices visible. The machine may rely on package contracts only when each package is pinned exactly and its law is proved or explicitly included in the trusted boundary. No graph, result, or proof closure is written into the journal as executable code.

## 1. Proposed boundary

A work package fixes an input carrier I and dependent output family O : I -> Type0. Its indexed codec already has the right shape to recover a value from journal bytes at a known input:

    decode_indexed : x:I -> Bytes -> Tot (option (O x))

The option is needed because arbitrary bytes may not encode an O x. The existing round-trip and canonicality laws say that encoding then decoding returns the exact value, and that an accepted byte string is the canonical encoding. This interface is already present in [Kernel.fst, indexed_codec](../current_implementation/src/WorkflowV2.Kernel.fst#L887-L896). It does not serialize O or reflect on F* types.

The redesign moves graph correctness to typed construction and graph-package contracts:

1. A typed graph contains a first-order durable descriptor plus an erased-in-practice F* witness that the descriptor is well formed against the exact pinned work packages.
2. A typed graph constructor can add a node only when its input wire has that node package's input type. The output port then has that package's exact dependent output family.
3. A root or generator graph package encodes typed graph descriptors and decodes bytes to either no graph or a graph carrying a well-formedness witness. Its laws cover canonical bytes and exact descriptor preservation. The decoder is package-specific; the abstract machine does not interpret a universal schema language.
4. A generator package proves its returned graph and allocation plan valid for every input and permitted allocation. Its result is a typed graph, so the contract is a type-level universal theorem, not a sample run.
5. A journal append is accepted only with an authorization witness at the exact current head. The ghost well-formedness invariant is preserved by authorized appends and transferred to exact, immutable journal prefixes at recovery.

The package callbacks, graph descriptions, and durable references are supplied by the pinned installation. The journal stores versioned identities, input/output bytes, graph bytes, plans, and event data. It never stores a closure, code body, F* type representation, or proof term. Pinning a reference to a package does not mean serializing the package.

## 2. Node packages and indexed values

Let I:Type0 and O:I -> Type0. A package identifies one exact implementation of a work form and the codecs/contracts that go with it. The smallest value-decoding contract is:

    IndexedCodec(I,O) = {
      encode : x:I -> O x -> Bytes;
      decode : x:I -> Bytes -> option (O x);
      roundtrip : forall x y. decode x (encode x y) = Some y;
      canonical : forall x b y. decode x b = Some y -> b = encode x y
    }

The current [CodeRef and OpRef declarations](../current_implementation/src/WorkflowV2.Kernel.fst#L898-L913) already index the output codec and operation validator by the exact input. Keep that form. `CodeRef.run x` returns `O x`; `OpRef.validate_reply x bytes` either rejects the bytes or returns an `O x`. An external operation additionally needs an effect/receipt contract for its stable key; a typed decoder alone does not prove that a remote effect happened once.

For a completed node whose input is x and whose journal stores bytes b, the local obligation is:

    decode_indexed x b = Some y
    and y = CodeRef.run x                         (local work)

or, for external work, `y` is the exact value accepted by that package's validator for the committed request/key/receipt. No type AST is needed: x is already known from the typed graph and reconstructed committed inputs.

The decoder form matters. A total function `x:I -> Bytes -> O x` cannot correctly decode every arbitrary byte string. Use an option-returning decoder for untrusted byte input, or use a total decoder only after a separate proof establishes that the bytes are in its valid encoding domain. Which form the journal API exposes is tracked as D1 in Section 9.

## 3. Graph well-formedness in F* types

### 3.1 Typed graph value

For a root input x:I and result family O, define the proposed value shape schematically as:

    TypedGraph(bundle, x, O) =
      { descriptor : GraphDesc(I,O,x);
        typing     : TypedGraphWitness(bundle,x,O,descriptor) }

The descriptor is durable syntax: node keys, exact durable work references, input wires, topological order, and output wire. The witness is not serialized. It records exact resolution to the pinned work packages and a dependent port context.

A port context Γ is a telescope. The root input is available first. When a node has package `Work A B`, its input wire has type A in the current context, and extending Γ adds a port whose type is `B (input_wire environment)`. Thus the output type may depend on the actual value supplied to the node. The final output wire has type `O x`.

    TypedNodeSequence(bundle, x, []) = root context
    TypedNodeSequence(bundle, x, nodes ++ [node]) requires:
      exact_package(node.work_ref) = Work A B
      input_wire(node) : forall rho:Env(Γ). A
      next_context = Γ extended by
        fun rho -> B (input_wire(node, rho))

    TypedGraphWitness requires:
      a TypedNodeSequence for the descriptor's exact node list
      every node key is fresh and every wire only names prior ports
      the descriptor's output wire has type O x
      the typed sequence projects to the descriptor exactly

Write the intended graph predicate as:

~~~text
GraphWF(bundle,x,O,d) :=
  StructuralDAG(d)
  /\ exists Γ nodes output_wire.
       TypedNodeSequence(bundle,x,Γ,d.nodes)
       /\ TypedWire(bundle,x,Γ,d.output_wire, fun _ -> O x)
       /\ ExactProjection(d, nodes, output_wire)
~~~

StructuralDAG covers finite node keys, uniqueness, topological order, and
wire references. ExactProjection prevents a witness for one graph from being
attached to different serialized syntax. TypedNodeSequence is the dependent
telescope rule above, not a second schema language.

This is a direct, reusable shape already visible in [Graph.fst's wire typing](../current_implementation/src/WorkflowV2.Graph.fst#L304-L380), [typed node sequence](../current_implementation/src/WorkflowV2.Graph.fst#L596-L623), and [typed graph witness](../current_implementation/src/WorkflowV2.Graph.fst#L763-L797). The redesign keeps those F* indices and telescopes as useful foundations but removes the schema AST, schema denotation, and custom equality checker. The type checker and explicit F* equality transports establish compatibility.

The key theorem is not a custom propagation algorithm. It is the soundness of the typed constructors:

    typed_graph_sound(bundle,x,g) :
      TypedGraph(bundle,x,O,g) ->
      forall rho:Env(g.typing.context).
        every node input at rho has its package input type
        /\ every node output at rho has its package output type
        /\ eval(g.output_wire,rho) : O x

The quantifier over environments is represented by the dependent function types in the witness. It is not discharged by running the graph at sample values. `finish_graph_sound` is the nearest existing theorem target, but its current body is admitted at [Graph.fst:937-944](../current_implementation/src/WorkflowV2.Graph.fst#L933-L944).

### 3.2 The vector example

Suppose a producer has input n and output family Vec n, and a consumer accepts Vec 3.

- With an unconstrained n, direct wiring is ill typed. The producer's output has type Vec n in the port context, while the consumer input requires Vec 3. The graph constructor cannot build the input wire without F* evidence that n = 3. Testing one execution where n happens to be 3 proves nothing about other environments.
- If a prior typed node supplies a value whose type proves it is 3, the producer's input wire has that refined type. The output family reduces or transports to Vec 3, so the consumer edge can be constructed. A plain prior result of type nat that happens to evaluate to 3 is insufficient; its declared result family must carry the fact.
- If a generator accepts arbitrary n, its admission theorem must prove the graph well formed for every n in its declared domain. It fails if it emits the bad edge for general n. A generator restricted by its input type or precondition to n = 3 can prove the good graph.

This gives the requested static distinction: reject the first graph for all possible environments, accept the second only when the graph's input/output types or explicit F* equality proof establish the needed index equality.

### 3.3 Typed graph codecs and recovery

The old generic `GraphCodec` returns only a `GraphDesc`, with syntactic round-trip/canonicality laws ([Kernel.fst:915-925](../current_implementation/src/WorkflowV2.Kernel.fst#L915-L925)); the structural parser in [GraphCodec.fst](../current_implementation/src/WorkflowV2.GraphCodec.fst) does not recover a typed witness. The proposal replaces this as the trusted interface with a graph-package codec, schematically:

    TypedGraphCodec(bundle,I,O) = {
      encode : x:I -> TypedGraph(bundle,x,O) -> Bytes;
      decode : x:I -> Bytes -> option (TypedGraph(bundle,x,O));
      roundtrip : decoding an encoded graph returns the same durable view;
      canonical : every accepted byte string is the encoding of its durable view;
      exact_refs : decoded durable references select the exact pinned packages
    }

“Same durable view” means exact node keys, work references, topology, wire syntax, and output wire. It does not require equality of erased proof terms or callback closures. A successful decode has a `TypedGraph` result by its F* return type. Bytes that fail parsing, package resolution, or typed construction return `None`.

The codec may use structural encoding, generated code, builder combinators, or package-specific decode logic. Its implementation and proof are owned by the graph/root/generator package. The package proof establishes the contract when that package is constructed and pinned; the machine then consumes the typed result. It has no SchemaSupported language or universal schema evaluator. No code is serialized. Durable work references are resolved against the pinned package table.

The graph package must prove that its decoder is sound, and its encoder can represent every graph value the package promises to persist. The design does not yet promise completeness for every arbitrary first-order DAG. A decoder that always rejects is not an acceptable implementation of a package that also promises graph production: round-trip coverage for every produced typed graph is mandatory. Whether the public builder promises all finite typed topologies is D3.

## 4. Package contracts and machine responsibilities

### 4.1 Delegated local obligations

| Package | Contract owned by the package | Machine obligation that remains |
|---|---|---|
| Value codec | Indexed encode/decode, round-trip, canonical accepted bytes for exact input x | Store exact bytes with exact pinned codec identity; decode at the reconstructed x |
| Local code | Total run x : O x and exact output codec | Authorize and append one completion; after commit never run that occurrence again |
| External operation | Request/reply codec, typed validator, stable-key effect/receipt/reconciliation law, charge bound | Bind intent/outcome to exact current occurrence, input, request, and head; settle once |
| Generator | For every legal x and allocation, return a TypedGraph and valid local plan | Commit exact graph bytes/plan before exposing children; splice graph occurrences into the whole run |
| Root graph package | Typed root graph and codec for its durable descriptor | Commit `RunStarted` only with that exact graph, input, registry, and root plan |
| Artifact package (optional) | Typed reference codec, inventory projection, publication and restart identity law | Include artifact identity claims only when this package is present |
| Journal codec | Event/journal parse, round-trip, framing, and canonical encoding | Use its one pinned codec; do not duplicate canonicality checks in replay |
| Manifest/package constructor | Bind durable identities to exact package values and contract proofs | Resolve one pinned package by exact identity; reject missing or ambiguous refs |

These are proof-bearing package values. A contract cannot be a Boolean “trusted” flag or an identity token unrelated to the callback. Its proof must be indexed by the exact package and arguments it certifies. The host/runtime proof must establish that restart selects the same package version and law implementation.

### 4.2 Obligations that stay global

Delegation ends where facts cross package or event boundaries. The abstract machine still proves:

- graph composition at the generator's parent input, global acyclicity, unique graph occurrences, and exact occurrence-path allocation lifting;
- current-head authorization, unique live claims, serial append, child visibility only after graph commit, and no dispatch after committed completion;
- aggregate charge/fuel conservation and once-only settlement across all nodes;
- exact-prefix crash recovery and fencing of appends from an earlier process epoch;
- all-schedule safety across arbitrary worker and distinct external-call completion order;
- semantic provenance preservation from genesis through authorized journal events and restart.

These are cross-package invariants, not a reason to recreate a universal type system. In particular, generator admission is local to one generator package; P4 still proves that embedding its child graph preserves the whole run's occurrence namespace and ledger state.

## 5. Journal authorization and the no-tampering premise

“Bytes are not tampered with” alone is insufficient. The proof needs a trusted valid genesis and proof that every visible append passed the exact authorization protocol. An append-only file containing an unauthorized first event would still be invalid.

Let H be the ghost history of successful append linearization points and J a
committed prefix. The proposed PrefixWF invariant is defined below from
trusted genesis, inductively authorized appends, and the state projection.

The origin witness is erased and is never a journal field. `AppendPermit` is consumed only by the private append boundary. It binds the event to the replay head, exact package, exact input, output/graph bytes, allocation or receipt, and transition rule. The current source has only event vocabulary and explicitly defers replay ([Journal.fst:82-113](../current_implementation/src/WorkflowV2.Journal.fst#L82-L113)); the definitions and proof target below are proposed, not implemented.

The induction obligation is:

    authorized_append_preserves_prefix_wf:
      PrefixWF(C,H,J)
      -> AppendPermit(C,J,e)
      -> append_commits_at_current_head(J,e)
      -> PrefixWF(C,H ++ [e],J ++ [e])

An aborted or stale append leaves J unchanged and creates no event witness. A committed append extends the invariant once, at the linearization point.

At restart, P10 should return a proof-indexed loaded prefix, schematically:

    LoadedPrefix(C) = {
      events : Journal;
      bytes : Bytes;
      decode(bytes) = events;
      bytes are the canonical encoding of events;
      events are the latest fully committed prefix of this run;
      PrefixWF(C, append_history, events)
    }

Define the append premise and fold independently of the byte parser:

~~~text
AppendPermit(C,J,e) :=
  EventGuard(C, fold_projection(C,J), e)
  /\ EventOrigin(C, J, e)
  /\ EventUsesExactPinnedPackages(C, e)

fold_projection(C, []) := initial_state(C)
fold_projection(C, J ++ [e]) :=
  apply_event(fold_projection(C,J), e)

AuthorizedHistory(C, []) := TrustedGenesis(C)
AuthorizedHistory(C, J ++ [e]) :=
  AuthorizedHistory(C,J)
  /\ AppendPermit(C,J,e)
  /\ append_commits_at_current_head(J,e)

PrefixWF(C,H,J) :=
  J is a prefix of H
  /\ AuthorizedHistory(C,J)
  /\ StateWF(fold_projection(C,J))
~~~

The empty prefix is trusted only when it is the declared valid genesis.
AuthorizedHistory is the inductive evidence that each extension had an
AppendPermit at its exact preceding head and was committed there.
fold_projection is a total deterministic projection from typed events.
EventGuard is applied when authorizing an append; recovery receives the
derivation that it held at that historical head. This avoids defining
PrefixWF as “the checker accepted this log,” which would merely rename
revalidation.

This makes the no-revalidation boundary precise:

- The runtime still has to read bytes and obtain typed event values, unless the journaler API already returns a refined typed prefix.
- The deterministic fold still reconstructs the current projection/frontier from events. It can be a proof-directed fold that consumes `PrefixWF`; it need not rerun event guards, graph edge checks, callback execution, result provenance checks, or append authorization.
- Codec framing, complete-input parsing, and canonical encoding remain byte-boundary obligations. They are not graph type checking or semantic-origin revalidation.
- A committed graph decoder may reconstruct a typed graph after restart. Its result type and package law provide the witness; the abstract machine does not rerun a general schema checker.

P10 must state trusted genesis, exclusive authorized append capability, atomic complete-prefix visibility, monotonic persistence, no mutation/rollback/reordering, and fencing of old append requests before a recovery cut. P13 must show the concrete journaler and controller refine those conditions. If storage can be imported from an untrusted source or changed outside this boundary, validate it once at import or reject it; do not simply assume `PrefixWF`.

## 6. Theorem targets and current source obligations

P0-P16 remain names for the system theorem spine. Their meanings below are revised where the universal schema was the sole reason for the burden. **No P theorem is complete in the current source.** Source links show the closest current declarations and gaps, not proof completion.

| ID | Theorem target | Actual obligation under this design | Current source state |
|---|---|---|---|
| P0 | `pinned_package_resolution` | Canonical manifest is the exact projection of package tables; each durable identity selects one exact package version, including its codec, callback, and law fields; reload preserves that binding. Remove schema-row denotation agreement. | [ManifestCore](../current_implementation/src/WorkflowV2.ManifestCore.fst#L854-L896) currently computes schema-to-codec cross-row coherence; package-to-identity proof remains open. |
| P1 | `typed_graph_builder_sound` | Every successful typed builder result carries an exact `TypedGraphWitness`; prove its node input/output types for every environment and exact projection to durable descriptor. Do not claim completeness for all raw DAG syntax unless D3 selects that public promise. | [Graph.fst](../current_implementation/src/WorkflowV2.Graph.fst#L600-L623) already has an indexed node sequence; `dag_wf` still packages an existential witness [L763-L797](../current_implementation/src/WorkflowV2.Graph.fst#L763-L797); builder laws and `graph_complete` are admitted [L908-L950](../current_implementation/src/WorkflowV2.Graph.fst#L908-L950). |
| P2 | `typed_graph_codec_roundtrip` | A graph package decodes durable graph bytes to either failure or a typed graph; successful decode preserves exact syntax/references and package selection; every produced typed graph round-trips canonically. No schema AST or proof bytes. | [Kernel.graph_codec](../current_implementation/src/WorkflowV2.Kernel.fst#L915-L925) returns only `graph_desc`; [GraphCodec.fst](../current_implementation/src/WorkflowV2.GraphCodec.fst) proves syntax encoding, not typed reconstruction. |
| P3 | `authorized_replay_projection` | Journal codec laws establish framing/canonical bytes. Starting from an authorized prefix witness, a proof-directed fold reconstructs the same projection and preserves structural `StateWF`; semantic provenance is inherited, not recomputed. | [Journal.fst](../current_implementation/src/WorkflowV2.Journal.fst#L82-L113) declares events and a history wrapper only; transition/replay proofs are absent. |
| P4 | `generator_commit_and_global_splice` | Exact generator package law proves its graph and local plan for every legal input/allocation. The machine binds and commits exact bytes/plan before exposing children; global embedding preserves acyclicity, unique occurrences, root result, and path-lifted allocations. | `generator_admission` quantifies over input/metric/allocation and already states graph/plan validity [Graph.fst](../current_implementation/src/WorkflowV2.Graph.fst#L877-L906). Global commit/splice theorem is absent. |
| P5 | `exact_generated_graph_recovery` | A committed graph reopens through the same pinned graph package and exact bytes/plan; it is not regenerated to choose new topology or allocations. | No recovery implementation or theorem. |
| P6 | `local_result_provenance` | For a committed local event, exact indexed decode equals the pinned `run x`; event authorization binds x and bytes; committed occurrences are absorbing. | `CodeRef` and indexed codec give types/laws [Kernel.fst](../current_implementation/src/WorkflowV2.Kernel.fst#L887-L903); event provenance/absorption is absent. |
| P7 | `external_effect_and_receipt_safety` | Per-key package law binds requests, retries, effects, terminal receipts, validation, and charge; machine binds each intent/outcome to exact occurrence/input/current head. Different keys may be nondeterministic and complete out of order. | `OpRef.validate_reply` is typed at exact x [Kernel.fst](../current_implementation/src/WorkflowV2.Kernel.fst#L905-L913); retry, effect, and receipt model is absent. |
| P8 | `global_charge_and_fuel_conservation` | Prove aggregate ledgers from committed plans and events, exact occurrence projections, and one-time reserve/settle across package results. Local package bounds do not prove the global sum. | Allocation helpers exist in [Graph.fst](../current_implementation/src/WorkflowV2.Graph.fst#L799-L875); journal ledger transitions and conservation are absent. |
| P9 | `artifact_publication_and_identity` (conditional) | If persistent object identity is promised, exact artifact package proves typed reference meaning, publish-before-append, immutable version and same logical object after restart. Otherwise refs remain opaque tokens and this theorem is omitted. | [Kernel.fst](../current_implementation/src/WorkflowV2.Kernel.fst#L869-L875) has an opaque artifact token; typed store contract is absent. |
| P10 | `authorized_exact_prefix_recovery` | Every cut yields the exact latest complete prefix, canonical bytes, and inherited `PrefixWF`; old appends are fenced. This combines physical prefix guarantees with append-history authorization. | No journaler or cut theorem in source. |
| P11 | `frontier_exists_or_intent_resumes` | Every started reachable nonterminal state has a legal action or same-key resumable intent. This is action existence, not service liveness. | No frontier theorem in source. |
| P12 | `successful_append_decreases_rank` | A well-founded rank decreases on every successful post-start append under any serialization order. Rejected/stale attempts do not count. | No rank theorem in source. |
| P13 | `concrete_refinement` | A chosen controller, journaler, codec set, executor, adapter, and optional artifact store refine the abstract contracts, including same-package restart, append authorization, fencing, and `LoadedPrefix`. The abstract proof cannot certify an unverified host. | No concrete runtime refinement in source. |
| P14 | `conditional_termination` | Given P11/P12 plus stated fairness, total local code, service/adapter/journal progress, finite fuel, and finitely many crashes, the run reaches its typed root output. | No liveness theorem in source. |
| P15 | `all_interleavings_preserve_safety` | For every allowed completion/append/crash schedule, preserve `PrefixWF`, unique claims, ready-input agreement, exact-head authorization, ledger invariants, commit-before-visibility, and no post-commit redispatch. Appends remain serial. | No controller state machine or schedule theorem in source. |
| P16 | `recovered_semantic_graph_correctness` | At every cut, compose P2/P5 typed graph recovery, P6/P7 result provenance, P8 ledgers, P10 prefix inheritance, and P15 safety; committed work is not replaced or rerun, and pending intents retain exact bindings. | No recovery-composition theorem in source. |

## 7. Other likely delegation points

These are design proposals, not additional source changes:

- **Manifest cross-checking:** [ManifestCore.manifest_entries_links_coherent](../current_implementation/src/WorkflowV2.ManifestCore.fst#L854-L896) repeats facts that package constructors can make true by construction: a code package supplies its own input codec/output codec; a generator supplies its graph package. Keep generic checks for canonical identity, duplicate IDs, closed references, and exact lookup. Remove parallel schema fields and the theorem that re-proves each table's self-description.
- **Canonical journal encoding:** put event and whole-journal round-trip/canonicality on `JournalCodec`; P3 consumes those laws and focuses on transition/replay projection. Do not prove the same byte law in both codec and state machine.
- **Generator admission:** the existing `generator_admission` has the desired universal quantification over exact inputs, metric, and allocation. Keep that contract local to the exact generator package. P4 should focus on exact commit authorization and cross-graph splice.
- **Adapter validation:** the operation package owns typed validation, receipt/effect correspondence, and same-key retry/reconciliation. The controller still checks current-head authorization and settles the result once.
- **Artifact persistence:** add a typed artifact package only if callers need stable object identity across restart. Otherwise do not make the abstract machine prove storage semantics for opaque reference bytes.
- **Scheduler/accounting:** do not delegate global claim uniqueness, current-head freshness, aggregate budgets, or parent/child visibility. Those combine multiple nodes and remain machine obligations.

## 8. Trusted proof boundary

Every package law used by a generic theorem must be a checked F* proof field or an explicit, documented external premise. A package identity alone proves no behavior. Inspect the transitive proof path for each callback and theorem; `assume`, `admit`, unchecked declarations, or axioms hidden behind helper modules cannot count as proof.

The trust root for no-tampering includes valid genesis, private append capability, authorization enforcement, exact atomic commit, immutable ordered prefixes, no rollback, and restart fencing. A physical store that merely promises “append only” does not prove semantic authorization. A concrete store/runtime claim needs P13 refinement evidence.

## 9. Open design decisions

This register is the single active place for unsettled choices. Work status belongs in [work_dag.md](../../state/work_dag.md).

| ID | Question | Current proposal | Status / theorem affected |
|---|---|---|---|
| D1 | How does arbitrary journal bytes decode? | Keep `option (O x)` and reject invalid bytes; only expose a total decoder behind a proof of valid encoding. | Open; P2/P3/P6/P7 boundary. |
| D2 | Who owns typed graph reconstruction after restart? | A pinned graph/root/generator package decodes graph bytes to a typed graph, using exact pinned node packages. | Open; P0/P2/P5. |
| D3 | What completeness does the public graph API promise? | Require all graph values the API produces to be typed and round-trippable; do not require acceptance of every raw first-order DAG. Decide separately whether builder completeness for all finite typed topologies is a product requirement. | Open; P1/P2. |
| D4 | What is a statically fixed dependent index? | An F* type/index or explicit equality/refinement proof in the graph's input/port telescope; a sampled runtime value does not count. | Proposed rule; P1/P4. |
| D5 | How is the ghost prefix invariant recovered? | P10 carries it from authorized append history through an exact immutable cut; P13 proves a concrete journaler implements this contract. | Proposed rule; P3/P10/P13/P16. |
| D6 | What is in the external operation contract? | Exact request and key binding, typed validator, receipt/effect law, retry/reconciliation semantics, and charge truth. | Open details; P7/P8/P15. |
| D7 | Which global guarantees remain in scope? | Preserve safety, exact recovery, budgets, and no rerun; keep liveness conditional and artifact identity optional. | Open product scope; P8-P16. |

## 10. Explicitly retired from the active design

The following are no longer requirements of this proposal: a universal schema AST; schema denotation and legal-environment calculus; schema substitution/weakening; custom family/type equality normalization; a `SchemaSupported` language boundary; and builder completeness defined relative to that schema language. Their former discussion is historical evidence only. The native F* graph types, package contracts, exact durable references, typed graph codec, and append-history invariant replace those obligations.

The source modules `SchemaCodec`, `SchemaScope`, `SchemaSemantics`, `SchemaPackages`, and `SchemaJudgments` are still present as the old baseline. Retiring their design role here does not mean the replacement API has been implemented or that the modules can already be deleted without changing the build. The active work DAG records their eventual disposition after D1-D7 are resolved.
