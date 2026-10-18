# F* v2 implementation packet

**Status:** architecture and proof-order companion, drafted during S2-12;
subordinate to [`implementation_spec.md`](implementation_spec.md) and
organized for future execution by [`state/work_dag.md`](../../state/work_dag.md).
This packet makes source module boundaries and proof order actionable. It does
not replace normative definitions or claim any P0-P16 theorem is proved.

## 1. Aim and guardrails

Build an abstract workflow system parameterized by pinned, proof-bearing
contracts. Core nodes are total pure local work, fallible nondeterministic
external operations, and total pure generators of arbitrary finite typed
DAGs. One canonical serial journal is the only durable workflow state.
Independent ready local/generator nodes may execute concurrently; distinct
adapter intents may remain in flight concurrently; journal appends remain
serial. Every crash cut recovers exact latest committed prefix. Committed work
is reused, never dispatched again. Dynamic child nodes get same typing,
authorization, budgeting, durability, recovery, and concurrency guarantees as
root nodes.

The implementation must prove contracts, not assume them. `assume`/`admit`
cannot discharge any system theorem. Required host or remote-service laws enter
as explicit proof-bearing contracts or explicit conditional premises. Source
examples are proof witnesses for expressibility; they are not test substitutes.
No `.fst`/`.fsti` implementation or tests belong to S2-12.

Normative sources:

- [`implementation_spec.md`](implementation_spec.md): all definitions,
  contracts, P0-P16, recovery, and expressibility targets.
- [`key_correctness_theorems.md`](key_correctness_theorems.md): theorem intent,
  especially universal dependent-edge typing, P15 interleavings, and P16
  recovered semantic graph correctness.
- [`state/work_dag.md`](../../state/work_dag.md): canonical future implementation
  and proof order. Its A00–C6 nodes are planned and have not been executed;
  C0–C6 are commit checkpoints rather than human-review gates.
- [`state/research/registry.md`](../research/registry.md): provenance and
  independent audits.

## 2. Contract surface and schematic signatures

Types below summarize mandatory interfaces; exact universe encodings and
module names may differ if all laws remain provable. `A` is fixed input
carrier; `B : A -> Type0` is dependent output family.

```fstar
type Bytes
type CodecIdentity
type CodeIdentity
type OperationIdentity
type GeneratorIdentity
type GraphCodecIdentity
type RegistryIdentity
type RootEntryIdentity
type NodeKey = nat
type ChargeMetricIdentity
type JournalCodecIdentity
type RegistryManifest

type Codec (a:Type0) = {
  identity:CodecIdentity;
  encode:a -> Tot Bytes;
  decode:Bytes -> Tot (option a);
  roundtrip:...; canonical:...
}
type IndexedCodec (a:Type0) (b:a -> Type0) = {
  identity:CodecIdentity;
  encode:x:a -> b x -> Tot Bytes;
  decode:x:a -> Bytes -> Tot (option (b x));
  roundtrip:...; canonical:...
}

type CodeRef (a:Type0) (b:a -> Type0) = {
  identity:CodeIdentity;
  input_codec:Codec a;
  output_codec:IndexedCodec a b;
  run:x:a -> Tot (b x)
}
type OpRef (a:Type0) (b:a -> Type0) = {
  identity:OperationIdentity;
  request_codec:Codec a;
  output_codec:IndexedCodec a b;
  validate_reply:x:a -> Bytes -> Tot (option (b x));
  charge_metric:ChargeMetricIdentity;
  maximum_charge:nat
}
type WorkIdentity = CodeWorkIdentity CodeIdentity
  | OperationWorkIdentity OperationIdentity
  | GeneratorWorkIdentity GeneratorIdentity
type OutputIdentity = ValueOutputIdentity CodecIdentity
  | GeneratedGraphCodecIdentity GraphCodecIdentity
type DurableWorkRef = {
  kind:WorkIdentity;
  input_codec:CodecIdentity;
  output:OutputIdentity
}
type ConstantRef = { codec:CodecIdentity; encoded_value:Bytes }
type Wire (a:Type0) (x:a) = RootWire | OutputWire NodeKey
  | ConstantWire ConstantRef | PairWire (Wire a x) (Wire a x)
  | FstWire (Wire a x) | SndWire (Wire a x)
type GraphNode (a:Type0) (x:a) = {
  key:NodeKey;
  work_ref:DurableWorkRef;
  input_wire:Wire a x
}
type GraphDesc (a:Type0) (b:a -> Type0) (x:a) = {
  nodes:list (GraphNode a x); (* exact topological syntax *)
  output_wire:Wire a x
}
type GraphCodec (a:Type0) (b:a -> Type0) = {
  identity:GraphCodecIdentity;
  encode_graph:x:a -> GraphDesc a b x -> Tot Bytes;
  decode_graph:x:a -> Bytes -> Tot (option (GraphDesc a b x));
  roundtrip:...; canonical:...
}
type GenerationAllocation = { expansion_fuel:nat; charge_allocation:nat }
type GraphAllocationPlan
type GeneratedGraph (a:Type0) (b:a -> Type0) (x:a)
                    (allocation:GenerationAllocation) = {
  descriptor:GraphDesc a b x;
  child_plan:GraphAllocationPlan
}
type GeneratorRef (a:Type0) (b:a -> Type0) = {
  identity:GeneratorIdentity;
  input_codec:Codec a;
  graph_codec:GraphCodec a b;
  generate_graph:x:a -> metric:ChargeMetricIdentity ->
    allocation:GenerationAllocation -> Tot (GeneratedGraph a b x allocation)
}
type GeneratorPackage (manifest:RegistryManifest)
                      (a:Type0) (b:a -> Type0) = {
  generator:GeneratorRef a b;
  admission:forall (x:a) (metric:ChargeMetricIdentity)
    (metric_member:ChargeMetricMember manifest metric)
    (parent:GenerationAllocation).
    let result = generator.generate_graph x metric parent in
    SchemaSupported manifest x result.descriptor /\
    allocation_plan_wf manifest metric parent.expansion_fuel
      parent.charge_allocation result.descriptor result.child_plan
}
type Work (a:Type0) (b:a -> Type0) =
  | LocalWork:CodeRef a b -> Work a b
  | ExternalWork:OpRef a b -> Work a b
  | GenerateWork:GeneratorRef a b -> Work a b

type PinnedRegistryBundle = {
  identity:RegistryIdentity;
  manifest:RegistryManifest;
  package_tables:PackageTables manifest;
  manifest_projection_exact:...;
  identity_unique_and_coherent:...;
  restart_reload_exact:...
}
type WorkMember (registry:PinnedRegistryBundle) (work:Work a b) : prop
type GeneratorMember (registry:PinnedRegistryBundle)
                     (generator:GeneratorRef a b) : prop

val start_graph : ... -> GraphBuilder ...
val add_node : builder:GraphBuilder ... -> work:Work a b ->
  member:WorkMember ... work -> input:Wiring ... a ->
  Tot (option (next_builder * typed_output_port))
val finish_graph : builder:GraphBuilder ... -> output:Wiring ... (b x) ->
  Tot (option (GraphDesc a b x))
type RootStart (a:Type0) (b:a -> Type0) (x:a) = {
  graph:GraphDesc a b x;
  allocation_plan:GraphAllocationPlan
}
type RootEntry (registry:PinnedRegistryBundle) (a:Type0)
               (b:a -> Type0) = {
  identity:RootEntryIdentity;
  input_codec:Codec a;
  graph_codec:GraphCodec a b;
  start:x:a -> budget:RunBudget -> Tot (RootStart a b x);
  start_wf:...
}

type Event = RunStarted ... | GraphCommitted ... | NodeCompleted ...
           | CallIntent ... | CallOutcome ...
type Journal = list Event
type JournalCodec = { identity:JournalCodecIdentity; encode:...; decode:...;
  roundtrip:...; canonical:... }
type ReplayContext = { registry:PinnedRegistryBundle;
  journal_codec:JournalCodec }
val replay : ReplayContext -> Journal -> Tot (result State JournalError)
val apply : ReplayContext -> State -> Event -> Tot (result State JournalError)
type AuthorizedEvent (context:ReplayContext) (state:State) (event:Event) : prop
type AppendPermit (context:ReplayContext) (prefix:Journal) (event:Event) : prop

type Journaler = { load_latest:...; compare_and_append:...;
  serial_and_cut_laws:P10 }
type LocalGeneratorExecutor = { worker_bound:nat{worker_bound >= 2};
  run_claim:...; exact_result_and_service_laws:... }
type Adapter = { in_flight_bound:nat{in_flight_bound >= 2};
  submit_one:CallIntent -> ...; keyed_overlap_and_P7_laws:... }
type Controller = { journal:Journal; volatile:Volatile }
val ControllerStep : StartRequest -> Controller -> Controller -> Tot prop
val recover : ReplayContext -> Journaler -> Tot (result State JournalError)
```

For `GenerateWork`, the spec-defined `WorkMember` includes an exact
`GeneratorMember` witness derived from the pinned package lookup. The
pre-bundle `GeneratorPackage manifest` pairs one callback with its
proof-bearing universal admission law; its type depends on the manifest,
schema resolver, and allocation validity, but not on `Bundle`. P0 proves that
the exact package (callback plus law) is the package projected from the
selected identity and that abstract reload preserves the same
identity-to-package association. Consumers use that one package; no parallel
law table or equality proof between duplicate closures is needed. P2 uses its
admission law when resolving graph syntax containing a generator. P4
consumes the same law to prove exact commit authorization, typed splice, and
child visibility. The package author must provide the checked law; P0 binds
it, rather than proving arbitrary generator code correct. The contract is not
a journal field or an `assume`/`admit`.

The sketch is schematic where it shows `...` proof bodies and the dependent
port telescope; it is not a complete replacement for signatures in
`implementation_spec.md` §§2.1–2.2. Identity-bearing fields are explicit:
each codec, code, operation, generator, graph codec, root entry, and registry
bundle has a pinned identity; a generator pins input and graph codecs;
`GraphNode` stores exact key, `DurableWorkRef`, and first-order input wire.
The full bundle comprises actual package tables plus exact-projection,
coherence, and restart-reload laws. Never replace these fields or indexed
codec/graph typing contracts with uninterpreted predicates. Exact schemas,
identities, replay transitions, typed construction, and theorem statements
remain those in the normative spec. A graph stores only first-order work
references and wire syntax. It does not serialize closures, typed proof
payloads, runtime handles, or an independent `Work` value. `WorkMember` and
resolver evidence are reconstructed from the one pinned registry bundle.

External work is not pure in its request. `validate_reply` is pure validation
of one raw reply at exact input; calls with same request may return different
accepted values. Adapter safety is per `K=(OperationIdentity,CallKey)` and
exact request/resume binding `Q`, with one immutable terminal receipt under
all retries/overlaps/restarts. Local/generator functions are total and pure.
Expected domain failure is encoded in result family, often `option`; no
durable failure-node state exists.

P15's abstract model has exactly one active commit coordinator per run. This
is what makes volatile live-claim uniqueness global to that run while the
journaler remains serial. A concrete P13 instance must prove single-coordinator
ownership for each run. Multiple coordinators are outside this model unless a
shared claim/epoch-fencing contract is added and the abstract theorem is
explicitly extended; a serial journal alone cannot provide that property.

## 3. Required source-module architecture

Current seven `.fst` files are partial historical evidence only. Later source
work should split by proof boundary below. Names are proposals; dependency
direction and ownership are requirements. Keep modules cohesive and expose
caller-facing laws in `.fsti` interfaces when the later implementation phase
begins.

| Layer/module proposal | Owns | Imports / must not import | Main obligations |
|---|---|---|---|
| `WorkflowV2.Kernel` | First-order identities, codecs, `CodeRef`, `OpRef`, `Work` signatures, wire/graph syntax interfaces, schema expression types, opaque packed artifact-reference syntax | No controller, journal, concrete runner, or host code | Codec laws and identity-level data foundations; no duplicate signature source |
| `WorkflowV2.ManifestCore` | Canonical first-order manifest entries, schema rules, identity domains and exact projections | Kernel only; no resolved typed graph or executable bundle | P0 manifest projection, uniqueness, coherence, canonical identity |
| `WorkflowV2.SchemaCodec` | Canonical schema type/value/predicate codecs and complete-input parsers | Kernel only; no manifest lookup or runtime packages | AST roundtrip, injectivity, malformed/trailing rejection, accepted-byte canonicality |
| `WorkflowV2.SchemaScope` | Typed nearest-first binder scope, lifting, and substitution for schema AST | Kernel only; no denotation or runtime packages | Scope preservation and substitution identity/composition across `Sigma` and `Refine` binders |
| `WorkflowV2.SchemaSemantics` | Manifest-indexed symbols, typed relational denotation, `LegalEnv`, static schema context | Kernel + ManifestCore + SchemaCodec + SchemaScope; no executable callbacks or graph resolver | Denotation/substitution laws and universal edge-typing foundations; A06 owns equality normalization/derivation completeness |
| `WorkflowV2.GraphResolve` | One proof-producing resolver for syntax and pinned schema manifest; resolved dependent port telescope | Kernel + ManifestCore + Schema; no complete bundle that depends on resolver | P1 soundness/completeness over exactly `SchemaSupported`; no casts or edge-proof bytes |
| `WorkflowV2.GraphCodec` | Canonical first-order graph syntax encode/decode | Kernel only; no runtime package lookup | Syntax roundtrip/canonicality component of P2; does not claim typed reconstruction |
| `WorkflowV2.Allocation` | `GraphAllocationPlan`, occurrence lifting, local plan predicates, ledger projections | Kernel/graph syntax/ManifestCore; no Bundle, Builder, or Controller | Exact plan/node alignment and deterministic path-derived lifting |
| `WorkflowV2.GeneratorAdmission` | `GeneratorPackage manifest`: one `GeneratorRef` plus its universal graph/plan admission proof | Kernel + ManifestCore + GraphResolve + Allocation; must not import Bundle, GraphBuilder, or Generation | Proof-bearing contract type below Bundle; no registry membership or second identity table |
| `WorkflowV2.Bundle` | Executable package tables including `GeneratorPackage`s, manifest projection/reload, exact membership lookup; derives `GeneratorMember` and `WorkMember` from exact lookup | Kernel + ManifestCore + GraphResolve + Allocation + GeneratorAdmission; resolver does not import Bundle | P0 binds exact identity-to-package/law mapping and restart-stable lookup |
| `WorkflowV2.GraphInterpretation` | Composition that decodes graph syntax and resolves it through the one pinned resolver into the exact dependent witness | GraphCodec + GraphResolve + Bundle; none may import GraphInterpretation | Owns P2: canonical syntax roundtrip plus exact typed-witness reconstruction, uniformly for root and generated graphs |
| `WorkflowV2.GraphBuilder` | Typed port context/wiring, start/add/finish API and graph completeness | Bundle + GraphResolve | Builder accepts exactly resolver-supported language; arbitrary finite topology/fanout/joins; generated work carries the exact `GeneratorMember` derived from Bundle lookup |
| `WorkflowV2.Generation` | `GeneratedGraph`, admitted pure generation, typed splice, global DAG preservation | GraphBuilder + GraphResolve + GeneratorAdmission + Allocation + Bundle | P4 generator-result validity, exact plan alignment, typed substitution, and global DAG preservation; no Journal dependency |
| `WorkflowV2.Journal` | Five event constructors, `State`, `EventGuard`, `apply`, `replay`, `StateWF`, terminal projection | Bundle + GraphInterpretation + Allocation; no services, provenance, or live execution state | P3 deterministic canonical replay and structural WF preservation |
| `WorkflowV2.Services` | Proof-bearing serial journaler, local/generator executor, adapter, generic scheduler tokens/laws, and optional store contract records | Journal + abstract service data; no Controller action/frontier types, no Provenance | Contracts expose the P7 receipt/effect and P10 storage inputs without cycles or hidden assumptions; scheduler laws use generic claim tokens that Controller interprets |
| `WorkflowV2.Durability` | Append history, barrier/cut model, exact loaded bytes and monotone prefix theorem | Journal + Services journaler contract | P10 canonicity/every-cut durability and settle/fence boundary |
| `WorkflowV2.EventAuthority` | `AuthorizedEvent`, local/generator/adapter origin-witness data, and `SemWF` ghost history; definitions only | Journal + Bundle + Services + Generation; no P6/P7 proof dependency | Defines append provenance and event authorization shapes without owning or assuming their soundness theorems |
| `WorkflowV2.AdapterProvenanceProof` | P7 keyed effect safety, receipt correlation, validator and persisted-output theorem | EventAuthority + Services adapter contract + Journal | Proves same-key overlap/retry/restart has one immutable terminal receipt; distinct keys may be nondeterministic |
| `WorkflowV2.Artifacts` (optional theorem branch) | Resource schema projection, publication and restart-resolution laws | Kernel/Bundle + Journal + Services store contract; packed-ref syntax is defined in Kernel | P9 only when persistent backing identity is claimed; replay stays pure |
| `WorkflowV2.ControllerModel` | `Controller`, volatile attempts, `ControllerStep`, current-head authorization, action frontier | Journal + GraphInterpretation + EventAuthority + Services + Allocation + Generation; must not import theorem modules or BudgetProof | Defines abstract transitions and commit-gated visibility; one active coordinator per run. Scheduler service laws remain generic; ledger projections are data from Journal/Allocation. P4 uses only successful serial-append commit, not P10 cut/fence theorems. |
| `WorkflowV2.GraphCommitProof` | P4 composition from generator admission/splice, authorized event, journal append/apply, and commit-gated visibility | Generation + GraphInterpretation + Journal + EventAuthority + ControllerModel | Owns complete P4 without depending on P6/P7/P8/P10/P15 theorem modules; consumes the pinned `GeneratorMember` contract and successful append token |
| `WorkflowV2.LocalProvenanceProof` | P6 exact local-result provenance and no-redispatch-after-commit lemma | EventAuthority + Journal + Bundle + CodeRef contract + ControllerModel | Proves local outputs match exact reconstructed inputs and committed occurrences leave the frontier |
| `WorkflowV2.BudgetProof` | Charge/fuel transition equations and settlement invariants | Allocation + Journal + Generation + GraphCommitProof + AdapterProvenanceProof | P8 conservation and once-only settlement under every replay transition; consumes P4/P7 results after they are proved |
| `WorkflowV2.ControllerSafety` | Induction over all permitted controller schedules | ControllerModel + GraphCommitProof + LocalProvenanceProof + AdapterProvenanceProof + BudgetProof + Durability; Artifacts only for P9 extension | P15 all-schedule safety; bounded parallel workers, multi-inflight adapter, serial append slot. Multi-coordinator systems need shared fencing and an extended theorem. |
| `WorkflowV2.GraphRecovery` | Exact graph-commit reconstruction and path-lifted allocation recovery | GraphInterpretation + GraphCommitProof + Journal + Durability; no P15 dependency | P5 reuses exact committed `GraphCommitted` graph/plan and never regenerates or replaces them |
| `WorkflowV2.Recovery` | Composite recovered semantic graph theorem | GraphRecovery + Journal + Durability + ControllerSafety + EventAuthority + LocalProvenanceProof + AdapterProvenanceProof + BudgetProof; Artifacts only for P9 extension | P16 every-cut typing/provenance/reuse; P9 optional strengthening |
| `WorkflowV2.Progress` | Enabled frontier theorem, lexicographic rank, fairness predicates | ControllerModel + ControllerSafety + Journal + BudgetProof + Services | P11 no-stuck; P12 no successful append cycle (P12's proof does not depend on P15) |
| `WorkflowV2.Refinement` | `ConcreteRep`, concrete step projection, concrete restart-load simulation | ControllerSafety + Durability + Progress + Services; Artifacts only for P9 extension | P13 implementation-to-abstract simulation; explicit host/remote premises; proves concrete run has one active coordinator or a separately approved shared-fencing extension |
| `WorkflowV2.Termination` | Conditional run-completion theorem | Progress + Refinement + adapter/store/service liveness laws | P14 termination under explicit fairness, totality, finite-fuel, and finite-crash premises |
| `WorkflowV2.Examples` | Small proof-bearing constructions for expressibility targets | Public abstract API only | Demonstrate representability/proof interface; never substitute tests for theorems |

Layering must stay acyclic. Manifest core is first-order; the resolver consumes
manifest core plus syntax; GeneratorAdmission defines a manifest-indexed
package law from resolver/allocation predicates; Bundle stores that exact
package with executable tables and joins it to canonical identity. The
resolver never imports Bundle. GraphInterpretation composes decoded syntax
with the bundle's resolver afterward. `GraphDesc` contains `DurableWorkRef`, not an executable Work
closure. `GeneratorAdmission` is below GraphBuilder and Generation, so the
required universal law does not create a Builder/Generation cycle. Journal
consumes typed graph interpretation but never imports Services or semantic
origin witnesses; Services may mention journal event types, and
`EventAuthority` consumes both to define ghost witness shapes. Scheduler
contracts use lower-level claim tokens, not Controller-owned actions.
`ControllerModel` contains ledger data and transition equations but imports no
P8 theorem module. P4 is split into a generation/splice component and an
event/visibility composition theorem; P6/P7 proof modules are separate from
witness-type definitions. `BudgetProof` depends on P4 and P7 after they are
proved, avoiding a P4/P8 back-edge. P5 is separate from P16 so exact graph
recovery does not accidentally acquire a P15 prerequisite. Packed
artifact-reference syntax lives below Journal; optional P9 proof imports
Journal and store contracts without a Journal/Artifacts cycle. If one module
becomes too large, split implementation from proofs while preserving this
dependency direction and keeping theorem interfaces nearby.

Current source files are starting evidence, not a fixed module layout:

| Existing file | Later disposition |
|---|---|
| `WorkflowV2.Kernel.fst` | Preserve useful identity, codec, Work, and schema foundations; split graph syntax if needed to satisfy acyclic layering. |
| `WorkflowV2.Identity.fst` | Evolve into exact manifest/bundle composition; remove any source of truth not derived from package tables. |
| `WorkflowV2.Graph.fst` | Reuse dependent port telescope where useful; separate first-order graph syntax, universal schema resolution, builder completeness, and typed isomorphism proofs. |
| `WorkflowV2.GraphCodec.fst` | Preserve syntax codec only where laws hold; add a separate `GraphInterpretation` composition with the shared resolver for P2. Syntax roundtrip alone is not typed reconstruction. |
| `WorkflowV2.Journal.fst` | Rebuild around exact five events, guarded pure replay, `StateWF`, and canonical `JournalCodec`; current actions do not establish P3/P15. |
| `WorkflowV2.GenerationExample.fst`, `WorkflowV2.ChainProof.fst` | Keep or replace as proof-bearing examples after generic P1/P4 interfaces exist; one chain example does not discharge universal graph theorems. |

The graph API signatures in `implementation_spec.md` §2.2 are the normative
expanded shape of `start_graph`, `add_node`, `finish_graph`, `Wiring`, and
typed `PortRef`; the compact signatures above omit dependent telescope
notation and full proof bodies. Any source signature change must preserve
those laws and P1/P2 completeness.

## 4. Journal representation and commit rules

The event algebra has exactly these semantic events, with payload fields
derived from [`implementation_spec.md` §4.1](implementation_spec.md#41-canonical-state):

| Event | Durable payload | Must be derived, not duplicated |
|---|---|---|
| `RunStarted` | run identity, registry/root-entry identities, canonical root-input and root-graph bytes, initial budget, root graph-local plan | codec identities, node signatures, event sequence number |
| `GraphCommitted` | generator occurrence path/key, exact graph bytes, exact graph-local child plan | parent graph, child path, generator identity/input, occurrence plan |
| `NodeCompleted` | local occurrence path/key, canonical indexed output bytes, artifact refs | work identity, reconstructed input, sequence number |
| `CallIntent` | external occurrence path/key, canonical resume data | call key, operation, request/input, reservation, sequence number |
| `CallOutcome` | external occurrence path/key, canonical indexed output bytes, evidence, charge, artifact refs | intent binding, operation/input, sequence number |

No separate failure event, completion bit, replay-state snapshot, generated
node list, sequence field, operation/work identity, or volatile handle. Event
identity is `(RunIdentity, list index)`; occurrence identity comes from graph
path plus local key. Journal `J` is sole durable authority; logical state is
`replay_C(J)`. Ghost append witnesses establish semantic origin but never
become event bytes.

Event and journal codecs must prove roundtrip and accepted-byte canonicality.
Graph/value codecs prove indexed roundtrip/canonicality; every decoded root or
generated graph is then resolved through same pinned resolver. Only
`append_authorized` may extend history: current replay/head, structural guard,
and event-specific `AuthorizedEvent` all required. Successful append commits
one event; stale append mutates nothing and requires reload/replay/full
reauthorization. `SemWF` tracks append provenance separately from replay-only
`StateWF`.

Journaler contract is serial compare-and-append with atomic prefix visibility,
monotone commit durability, exact latest-prefix load bytes, no external
mutation, and settle/fence of all old requests before recovery load. `P10`
proves byte equality with canonical encoding and exact recovery. `P13`
proves selected physical journaler refines this contract. Journaler need not
accept parallel inputs; concurrency lives in work execution/adapter only.

## 5. Proof order and dependency spine

Follow this order; later proof tasks must not use theorem names as axioms.
Contract records are inputs carrying proven laws. Every target is a theorem
over those records. Open implementation representations can change only if
they establish the same contracts.

| Phase | Targets | Prove / unlocks |
|---|---|---|
| A. Immutable package foundations | P0 | Exact canonical manifest projection, identity uniqueness/coherence, codecs and root linkage, stable reload. Establish exact lookup before any graph/event can resolve executable work. |
| B. Graph language | P1, then P2 | Resolver and builder soundness/completeness for `SchemaSupported`; every node input type and output family valid in every legal internal port environment; graph codec roundtrip/canonicality and identical root/generated resolution. Reject unconstrained `Sigma n. vector n` to `vector 3`. |
| C. Replay foundation | P3 | Deterministic event fold, state-WF preservation, canonical event/journal encoding, malformed-prefix rejection, terminal absorption. Replay alone proves no semantic origin. |
| D. Independent semantic/store lemmas | P4, P6, P7, P10 (after P3) | In parallel: P4 combines generator universal admission/typed splice with exact `GraphCommitted` authorization and append-gated child visibility; P6 exact local result; P7 keyed effect-safe adapter outcome; P10 serial every-cut byte/prefix/fencing theorem. P10 needs P0-P3, not P4-P8. |
| E. Compositions | P5, P8, optional P9 | P5 combines P2/P4/P10 to recover exact committed graph and plan. P8 combines P3/P4/P7 for ledger conservation and once-only settlement. P9 adds publication and same logical backing version only when claimed. |
| F. Every interleaving | P15 | Define atomic controller step relation; induct on all finite legal schedules and crash steps. Unique claims, exact ready inputs, current-head reauthorization, serial append, out-of-order completions, commit-only visibility, ledgers, SemWF, and no-rerun-after-commit. P10 supplied. |
| G. Abstract recovery and progress | P11, P12, P16 (after P15 where required) | P11 frontier existence after P15; P12 well-founded rank decrease after P3-P8; P16 derives latest prefix, SemWF, universal graph typing, exact local/external/generator provenance, committed-work reuse, and same-key pending-call recovery. P9 conditionally adds resource identity. |
| H. Concrete transfer and termination | P13, then P14 | P13 proves concrete-to-abstract simulation after P0-P8, P10-P12, P15, including exact crash load and epoch/append fencing. P14 then proves conditional termination from named fairness, service progress, totality, finite fuel, and finite crashes. |

The theorem dependency DAG must match `implementation_spec.md` §6 exactly:
P1-P2 graph; P3 replay; P4 generator commit; P5 graph recovery; P6 local;
P7 adapter; P8 ledgers; optional P9 resources; P10 store; P11 frontier; P12
rank; P13 concrete refinement; P14 conditional termination; P15 all-schedule
abstract safety; P16 semantic recovery. P13 uses P0-P8, P10-P12, P15; P9 is
conditional on physical resource identity. P14 uses P11-P13. P16 uses P0-P8,
P10, P15; P9 only for resource identity. P16 is abstract and may be proved
before a concrete P13 instantiation. P5 must remain explicit: P16's graph
recovery claim depends on exact P4/P2/P10 behavior, not merely an event that
looks well typed.

## 6. Theorem acceptance checklist

Implementation is ready only when all listed cases are actual machine-checked
proofs, with no `assume`/`admit` in theorem path:

- **P0:** equal identity selects exactly one complete package and exact
  linked schemas/codecs/validator/graph resolver/root entry; manifest equals
  package projection; restart selects same bundle.
- **P1:** builder and resolver accept exactly declared schema language;
  universal all-legal-environment input equality; output boundary type;
  arbitrary finite topology/fan-out/joins; no sampled outputs, validator
  narrowing, edge evidence payload, or arbitrary `Type0` equality claim.
- **P2:** canonical graph decode/encode roundtrip, preserved indices/ports/
  edges/constants/work refs, and exact dependent witness reconstruction for
  root and generated descriptors through same resolver.
- **P3:** initial state and each valid apply preserve `StateWF`; replay
  deterministic; accepted event/journal bytes canonical; terminal absorbing;
  no provenance inferred from replay alone.
- **P4:** for all inputs/metrics/allocations, generator result schema-valid
  and plan-valid; only exact result/plan can commit; child disabled before
  commit; global splice preserves typing, DAG, uniqueness, output family.
- **P5:** after any cut with committed `GraphCommitted`, use exact graph and
  path-lifted plan; never rerun generator or replace topology/plan.
- **P6:** exact input reconstruction; committed local bytes decode to
  `CodeRef.run(input)`; committed occurrence is absent from future action
  frontier. Precommit pure work may repeat.
- **P7:** `CallIntent` precedes submit; key/request/resume binding immutable;
  same-key overlap/retry/restart yields one logical effect and immutable
  terminal receipt; exact pinned validator and `persist_x`; outcomes correlate
  evidence/charge/artifacts; changed binding rejected; distinct keys may be
  nondeterministic and complete out of order.
- **P8:** charge/fuel equations hold after every event and interleaving;
  plans are sole allocation source; no duplicate settlement; run charge metric
  consistent.
- **P9, if claimed:** typed refs match exact inventory; publish durable before
  event commit; restart handle denotes same immutable logical object/version;
  replay performs no I/O.
- **P10:** every cut loads exact latest complete prefix, bytes equal unique
  encoding, prefixes monotone, committed event never disappears; old appends
  settled/fenced before load and cannot appear afterward.
- **P11:** each started reachable nonterminal replay state has a legal action
  or same-key resume; pre-`RunStarted` bootstrap excluded.
- **P12:** every successful post-start append strictly decreases `(G,U,W)`;
  rejected stale append is not a transition; zero-fuel parent cannot emit
  child generator because nested generators get positive fuel.
- **P13:** concrete initial state, each step, and each recovery-load barrier
  refine P15/P10; current bytes/history/replay align; exactly one active
  coordinator per run; worker epochs and append requests fenced; exact
  manifest/codecs/validator/adapter contracts and optional P9 resources
  refined. Host and remote facts stay named premises.
- **P14:** termination only after committed valid `RunStarted`; all fairness,
  result return, append, adapter reconciliation, optional resource resolution,
  totality, initial finite fuel, and finite-crash premises appear explicitly.
- **P15:** arbitrary permitted finite schedule preserves live claim
  uniqueness, exact input/allocation binding, reauthorization, SemWF,
  GlobalGraphWF, ledger, commit-before-visible, recovery, and no redispatch
  after committed completion/outcome. Independent nodes/calls may finish in
  any order; journal appends stay serial.
- **P16:** every authorized history/cut recovers latest prefix with semantic
  provenance, all-environment typed root/generated DAGs, exact local/external/
  generator results, no committed rerun/replacement, and same-key pending
  intent. Add P9 only for backing-object identity.

## 7. Representation choices: owner and decision rule

These are representation choices only. Their semantic contracts are already
fixed. Later implementation agent owns each choice and records evidence
before relying on it:

| Choice | Owner | Decision rule |
|---|---|---|
| Heterogeneous dependent port context and existential node packages | Graph representation author | Choose a representation that reconstructs exact input/output indices from first-order syntax and resolver derivations; prove P1/P2. No unchecked cast or serialized per-edge proof. |
| Schema AST normalization/equality source encoding | Schema/resolver author | Implement displayed finite grammar/calculus, termination, soundness and claimed `SchemaSupported` completeness. A solver callback may only be used with a proved sound/complete boundary; no “SMT succeeded” constructor. |
| Builder storage: typed constructor term vs topological port table | Graph builder author | Pick simplest structure that accepts exactly `SchemaSupported`, supports arbitrary finite topology, and proves construction completeness and canonical encoding. If either route silently narrows builder language, reject it. |
| Work/codec membership evidence | Bundle/builder author | Evidence is derived from exact pinned package tables and erased if appropriate. Constructors cannot accept unrelated package values with same label. |
| Universal generator-admission proof | Generator package author; pinned-bundle author verifies exact association | Provide a machine-checked proof of `GeneratorMember` for every pinned generator. The proof covers every legal input, metric, and parent allocation. P0 binds it to the exact package; P2/P4 consume it. It is a caller/package proof obligation, never an assumed system theorem. |
| Root entry and `RunStarted` binding | Root-entry/bundle author | One pinned `RootEntry` binds input codec, graph codec/resolver, output family, constructor version, and `start_wf`; P0 proves exact identity/package linkage, while P2/P3 prove canonical root bytes and replay linkage. |
| Canonical manifest and registry identity | Identity author | Manifest is exact projection; duplicate IDs rejected. Prefer exact canonical byte identity. A digest is allowed only with explicit uniqueness/collision-resistance P13 premise. |
| Node keys and event path encoding | Graph/journal authors | Decidable equality, unique keys within each graph, canonical encoding; path-derived child occurrence is injective. No sequence or identity duplication. |
| Volatile maps, claims, and attempt epochs | ControllerModel author | Key claims and pending candidates by exact `NodeOccurrence`/`CallKey`; use injective fresh attempt epochs, bind every candidate to the committed input/allocation/head, clear volatile claims on crash, and prove P15 safety for every permitted schedule. |
| Event/journal codec format | Journal author | One stable pinned format; every accepted byte sequence decode/re-encodes identically; no snapshots or volatile data in journal. |
| Selecting `JournalCodecIdentity` on recovery | Replay-context/host-loader author | `ReplayContext` supplies exact codec identity and codec package for this run. Selection comes from immutable store/run/deployment metadata or fixed deployment context, never guessed from malformed journal bytes. P13 proves selected identity/package stays fixed across restart. If no stable selector exists, deployment must retain one format context per journal or add a separately specified migration theorem. |
| Concrete host, worker pool, journaler, adapter, resource store | Later runtime author | Supply P13 refinements and P10/P7/P9/P14 laws actually required by claimed guarantees. A missing host law makes that instantiation unavailable or conditional; it cannot weaken abstract theorem. |
| Bounded scheduler and fairness policy | Service/controller author | Choose any policy satisfying the abstract bounded-capacity and P14 fairness premises. P15 must hold for every permitted completion order; no fairness assumption may enter a safety theorem. |
| Library API (`then`, `fan`, `lift`, `case`) | Library author after core proofs | Must elaborate to `start_graph`/`add_node`/`finish_graph` and preserve core proof interface; never add another primitive or durable state source without revising spec. |

If a representation cannot meet its decision rule, stop for theorem/design
review. Do not shrink `SchemaSupported`, omit a theorem, or replace proof with
`assume`/`admit` silently.

Deployment resource limits are policy outside graph semantics. The API's
`SchemaSupported` language remains unbounded in finite node count, depth, and
encoded size. A deployment may reject a `StartRequest` before `RunStarted`
under an explicitly declared admission policy. Once a run starts, refusing a
valid generated graph because of an undocumented size cap cannot be represented
as a durable workflow failure and does not satisfy full progress refinement.
Safety refinement may still hold if the process makes no invalid commit;
P14 termination is conditional on sufficient memory/storage and service
capacity to return every admitted total computation/result. A deployment that
intentionally narrows graph expressibility must advertise a different API
contract and obtain human review; it cannot call that full S2 API.

## 8. Alternatives and decisive counterexamples

| Alternative | Decision |
|---|---|
| Typed graph syntax plus one pinned schema resolver | Retain. Gives runtime-generated arbitrary DAG syntax and common construction/recovery path. Completeness is relative to declared `SchemaSupported` calculus. |
| Runtime output inspection or validator postcondition to accept an edge | Reject. Makes graph validity depend on one observed execution and fails for all-environment soundness. |
| Per-edge proof bytes or endpoint-supplied equality witness | Reject. Duplicates context-specific proof, risks trusting arbitrary witness, and breaks proof-free canonical graph language. Resolver derives erased proof from syntax/schema. |
| Generator returns list of fixed plans or pre-authored workflows | Reject. Does not encode arbitrary topology/joins/fan-out. `GeneratorRef` returns `GraphDesc` and aligned plan; same graph language as root. |
| Separate canonical state snapshot plus journal | Reject. Creates two durable authorities and recovery agreement burden. Durable state is `replay(J)`; volatile controller projection discarded on crash. |
| Concurrent journal appends | Reject for core. Serial compare-and-append keeps one history order and simple ghost authorization. Parallel execution remains in workers/adapter. |
| Adapter exactly-once transport | Not required. Effect-safe retry via stable-key dedupe/status or operation-specific idempotence/reconciliation suffices; transport may repeat. |
| Force all adapters to be deterministic/pure | Reject. Distinct calls may be nondeterministic; P7 is per key/binding. |
| Require P9 for every artifact-looking value | Reject. P9 is conditional. Typed opaque values remain abstract-safe without a persistent identity claim; file/network/database handle guarantees need P9 when promised. |
| Put a fixed graph-size/depth/encoded-byte limit into `SchemaSupported` | Reject. Finite capacity is a deployment admission/progress premise, not a change to the graph language. Any supported per-run policy must be explicit before `RunStarted`; a runtime cap on a committed generator result cannot weaken graph or recovery semantics. |
| Put `fan`, `lift`, `case`, or `then` in primitive kernel | Reject. Library combinators elaborate over same graph primitives; the core stays minimal. |

Counterexamples implementation proofs must rule out: `Sigma n. vector n`
feeding `vector 3` when `n` unconstrained; a validator accepting only `n=3`
being used to narrow that graph judgment; generator checked at one sampled
input but not universally; committed `NodeCompleted` or `GraphCommitted`
rescheduled after replay; child runs before `GraphCommitted`; a lost external
reply causing second logical effect; outcome keyed to different input or
validator; old worker callback/append crossing restart epoch; two coordinators
writing without shared fencing; noncanonical/torn bytes exposed as committed;
stale permit reused after changing only head; changed code behind same ID;
P9 object missing or rebound; rank failing to decrease at zero fuel; P11
mistaken for eventual service completion.

## 9. Expressibility obligations (proof examples, not tests)

Later `WorkflowV2.Examples` should construct and prove API encodings for these
shapes. Each example must use public API or library composition and actual
proofs; it does not replace generic P0-P16 proofs.

1. **Dependent pure result:** `Work nat (fun n -> Prime n)` with proof-bearing
   local result, dependent output codec, and consumer accepting its exact
   indexed family.
2. **Recovery reuse:** local result commits `NodeCompleted`; after replay,
   consumer uses decoded committed result and scheduler cannot rerun producer.
3. **Static analysis over files:** input/output types contain typed file or
   tree refs; adapter materializes files, invokes CLI, validates/parses report,
   publishes result/artifacts before `CallOutcome`. P9 proofs included if
   promise says backing files survive restart as same logical versions.
4. **Data-dependent generated DAG:** pure generator returns different finite
   graph sizes/topologies/joins/fan-out from exact input; universal admission
   covers every legal input/allocation; recovery uses exact committed graph.
5. **Network or reusable adapter:** inline authoring and library package
   produce same `OpRef`/P7 contract; request handling, validation, key safety
   and journaling are identical.
6. **Deterministic event-queue adapter:** scripted dummy adapter refines P7
   and supports keyed out-of-order completion/retry without bypassing intent
   and outcome rules.

## 10. Later implementation acceptance and stop conditions

Later implementation task must start from this packet and normative sources,
read current F* proof-writing instructions, then create small module steps in
dependency order. First establish declarations and proof interfaces for one
layer; verify each via project full-check command before proceeding. Add no
unchecked escape hatches. Use the six example shapes as constructive proof
examples after core theorem interfaces exist. Keep source evidence separate
from theorem status; a declaration or contract field is not proof of its
implementation refinement.

The S2-12 packet was accepted as an architecture/proof-order artifact after
independent audits covered P0-P16 owners and order, dependency cycles,
representation decision rules, decisive counterexamples, and signature
alignment with the normative spec. That historical S2 review gate is not the
active execution graph. The A00–C6 implementation/proof DAG is in
[`state/work_dag.md`](../../state/work_dag.md); it remains unstarted until the user
explicitly asks to execute it. Once started, its commit checkpoints do not
pause for human review.
