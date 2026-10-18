# F* workflow v2: abstract system and proof contract

**Status:** normative abstract specification. Existing v2 `.fst` files are
partial source evidence, not an implementation or proof of this contract.
This document defines the system that a later F* implementation must refine.
It claims no source-level theorem is currently discharged.

## 1. Goal and design rule

Specify the smallest typed workflow system that supports total pure local
work, fallible nondeterministic external operations, and pure runtime
generation of arbitrary finite-topology typed DAGs in the manifest-declared
schema language.
Root and generated graphs use the same node typing, event transitions,
journal, execution services, and recovery rules. One canonical durable journal
defines all durable workflow state.

The abstract system is parameterized by pinned work and codec contracts, a
serial journaler, a local/generator execution service that may run independent
ready nodes concurrently, and an external adapter that may keep multiple
distinct calls in flight. Each adapter submission carries one intent; the
workflow may submit another distinct intent before earlier calls finish. The
system proves safety for every permitted
interleaving; it does not require concurrent journal writes. Concrete services
must later prove refinement to their supplied contracts.

Every theorem in this specification is proved from definitions and explicit
contract records. A contract record is a theorem parameter with proof fields,
not an unchecked `assume`; no `admit()` or `assume` may discharge a system
theorem. Concrete implementation obligations remain separate refinement
theorems. Proof difficulty is not grounds to weaken a required property.
The proof checker, its logical prelude, and SMT decision procedure are the
verification trusted base. Outside that base, system proofs may not rely on
unchecked application declarations or helper theorems whose implementation
uses an admission. Primitive representations used by durable codecs must be
chosen so their codec laws are proved or are explicit, audited contracts.

This specification labels claims as:

- **Definition:** the abstract API or transition semantics.
- **Contract:** a boundary law supplied with its proof as part of a journaler,
  adapter, executor, codec, registry, or artifact-store value.
- **Theorem target:** a result derived from definitions and named contracts,
  generic in those contract-bearing values and their laws.
- **Open representation:** a choice of encoding or implementation that may
  change while preserving the stated laws. It is not permission to leave a
  theorem or its completeness boundary unspecified.

## 2. Minimal typed API

The result is indexed by the exact input. Refinements and dependent results are
ordinary output families: for example, `Work nat (fun n -> Prime n)`.
Fallibility is represented in the chosen output type, commonly
`option (fun x -> A x)`. There is no durable `Failure` node state.

The core has three executable node kinds: verified local code, an adapter call,
and a graph generator. A graph contains these same nodes. Sequencing, fan,
lift, case, and other ergonomic forms are libraries over the typed graph
construction interface.

```fstar
type Bytes
type Digest
type CodecIdentity
type CodeIdentity
type OperationIdentity
type GeneratorIdentity
type GraphCodecIdentity
type SchemaIdentity
type RegistryIdentity
type JournalCodecIdentity
type ResolverIdentity
type RootEntryIdentity
type RegistryManifest
type NodeKey = nat
type RunIdentity
type GraphOccurrence =
  | RootGraph : RunIdentity -> GraphOccurrence
  | ChildGraph : parent:GraphOccurrence -> generator_key:NodeKey
      -> GraphOccurrence
type NodeOccurrence = { graph:GraphOccurrence; key:NodeKey }
type CallKey = NodeOccurrence
type WorkIdentity =
  | CodeWorkIdentity CodeIdentity
  | OperationWorkIdentity OperationIdentity
  | GeneratorWorkIdentity GeneratorIdentity
type OutputIdentity =
  | ValueOutputIdentity CodecIdentity
  | GeneratedGraphCodecIdentity GraphCodecIdentity
type DurableWorkRef = {
  kind:WorkIdentity;
  input_codec:CodecIdentity;
  output:OutputIdentity
}
type PinnedRegistryBundle
val pinned_registry_identity : PinnedRegistryBundle -> Tot RegistryIdentity
val registry_manifest : PinnedRegistryBundle -> Tot RegistryManifest
val manifest_named_by : RegistryIdentity -> Tot RegistryManifest
val canonical_manifest_encoding : RegistryManifest -> Tot Bytes
val registry_identity_of_bytes : Bytes -> Tot RegistryIdentity
val registry_identity_of_bytes_injective : b1:Bytes -> b2:Bytes -> Lemma
  (registry_identity_of_bytes b1 == registry_identity_of_bytes b2 ==> b1 == b2)
let manifest_identity (m:RegistryManifest) =
  registry_identity_of_bytes (canonical_manifest_encoding m)
val pinned_manifest_exact : b:PinnedRegistryBundle
  -> Lemma (registry_manifest b ==
            manifest_named_by (pinned_registry_identity b))
val manifest_lookup_identity_exact : id:RegistryIdentity -> Lemma
  (manifest_identity (manifest_named_by id) == id)
val bundle_identity_exact : b:PinnedRegistryBundle -> Lemma
  (manifest_identity (registry_manifest b) == pinned_registry_identity b)
val manifest_identity_injective : m1:RegistryManifest -> m2:RegistryManifest
  -> manifest_identity m1 == manifest_identity m2 -> Lemma (m1 == m2)

type Codec (a:Type0) = {
  identity:CodecIdentity;
  encode:a -> Tot Bytes;
  decode:Bytes -> Tot (option a);
  roundtrip:x:a -> Lemma (decode (encode x) == Some x);
  canonical:b:Bytes -> x:a
    -> Lemma (decode b == Some x ==> b == encode x)
}

type IndexedCodec (i:Type0) (o:i -> Type0) = {
  identity:CodecIdentity;
  encode:x:i -> o x -> Tot Bytes;
  decode:x:i -> Bytes -> Tot (option (o x));
  roundtrip:x:i -> y:o x
    -> Lemma (decode x (encode x y) == Some y);
  canonical:x:i -> b:Bytes -> y:o x
    -> Lemma (decode x b == Some y ==> b == encode x y)
}

type CodeRef (i:Type0) (o:i -> Type0) = {
  identity:CodeIdentity;
  input_codec:Codec i;
  output_codec:IndexedCodec i o;
  run:x:i -> Tot (o x)
}

```

The registry contract is more than storing `RegistryIdentity` beside resolver
tables. `registry_manifest b` is the canonical first-order projection of the
bundle's actual work, operation, generator, value-codec, indexed-codec,
artifact-type/store, charge-metric, graph-codec, schema-rule, resolver, and
root-entrypoint packages. Its identity
is injective over that canonical manifest; a digest-only identity requires an
explicit collision-resistance premise at the host boundary. The manifest
named by `RunStarted` equals this projection by `pinned_manifest_exact`.

`RegistryManifest` contains a versioned, canonically encoded list of tagged
entries. Tags distinguish code, operation, generator, codec, artifact type,
artifact store, charge metric, graph codec, schema family/rule, resolver, and
root entrypoint identities; identity domains are disjoint. Construction
proves all of the following from the actual
bundle tables:

Contract identity tokens are typed slots inside their owning rows, not a
thirteenth top-level manifest identity domain. A03 checks that every required
slot has the right contract kind and position. P0 proves that each such token
is exactly the token on the selected proof-bearing package field, and that
the package field is the one used by execution; this establishes existence
and unique association without duplicating contract records in a second
manifest table. Top-level identity references (for example codec, schema,
store, and graph-codec references) resolve through the tagged entry set.

An artifact type's logical schema and reference-codec entry must agree in the
manifest itself. Schema-expression payloads remain first-order bytes in A03;
their parseability, canonical AST encoding, and denotation are checked by the
restricted schema layer before P0 can admit them into a pinned bundle.

The current F* representation uses opaque `identity_token = bytes` values for
identity names and labels. The Kernel models `bytes` as `list nat`, a proof-
level wire alphabet rather than a promise that each element is an 8-bit
octet. Human-readable names and the concrete octet encoding belong to a later
library or concrete-refinement boundary; the abstract system makes no UTF-8
or host-text promise.

The canonical projection includes, per entry, exactly the metadata needed to
select its one package and check its links: a `CodeIdentity` with its exact
input/output codec IDs and implementation version; an `OperationIdentity`
with request/result codec IDs, validator identity, adapter/configuration
identity, charge metric identity, and maximum charge; a `GeneratorIdentity` with input codec, graph
codec, result-family schema and allocation-contract identity; a value or
indexed codec identity with its schema and codec-version identity; an
artifact-type entry with its logical schema, reference-codec, store and
interpretation identities, and exact resource-projection law; a graph codec
identity with input/output schema and canonicalization version; schema
family/rule identities with canonical expressions/equations and denotation-law
identities; the resolver identity with its accepted schema-language version;
and a root-entry identity with input codec, graph codec, result family and
root-constructor version. The projection contains no closures or proof terms.
Its canonical encoding sorts entries by disjoint tag then canonical identity
representation, and preserves all semantically relevant versions and links.
Those tokens name abstract packages; they are not evidence that a concrete
host binary matches them. P13 establishes that refinement.
Manifest construction rejects duplicate IDs before canonical sorting; it may
not silently deduplicate entries or let table order choose a winner. A valid
manifest has exactly one entry per ID in its tagged identity domain and every
cross-reference resolves to that entry.

The manifest is a projection of the package tables, not a second registry
supplied beside them. `manifest_projection_exact b` means both directions:
every row is the canonical projection of exactly one package in `b`, and
every package in `b` contributes exactly one row with its complete linked
metadata. A constructor for `PinnedRegistryBundle` must carry this relation;
callers cannot provide independently editable tables and assert they match.
`manifest_identity` is the injective identity embedding of the exact canonical
manifest bytes. If a host substitutes a digest representation, collision
resistance is a separate P13 premise.
Together the identity laws mean the bundle key selects its own exact
projection, and the selected projection has that key:

~~~text
manifest_named_by (pinned_registry_identity b) = registry_manifest b
manifest_identity (manifest_named_by id) = id
manifest_identity (registry_manifest b) = pinned_registry_identity b
~~~

`manifest_named_by` is defined over valid registry identities; an API over all
bit strings instead returns `option RegistryManifest` and states the same
equalities under successful lookup.

- **Identity uniqueness and coherence:** each executable identity resolves
  to exactly one package and one complete signature/schema/configuration/
  implementation version. In particular, equal `CodeIdentity`s imply equal
  code package and input/output codecs/schemas; equal operation identities
  imply equal operation, request/result codecs, validator and adapter
  configuration and charge metric; equal generator identities resolve to
  the same `GeneratorPackage` entry, containing one callback token, input
  codec, graph codec, schema, allocation contract, and admission law. This is
  package lookup uniqueness, not extensional equality between separately
  loaded function closures. Full `DurableWorkRef` uniqueness is also proved,
  but does not replace this stronger condition.
- **Codec and schema coherence:** each codec identity denotes one exact
  carrier/indexed family, canonical encode/decode pair, schema expression and
  denotation proof. Work signatures derive from the exact codecs in their
  package; no second editable signature is consulted during resolution.
- **Charge/resource coherence:** each `RunBudget` pins one charge metric
  present in the manifest. Every admitted operation metric also resolves in
  the manifest and equals that run metric; every operation maximum and
  adapter receipt uses it.
  every artifact type identity resolves to one exact typed reference codec,
  artifact-store identity, and interpretation contract. Resource-reference
  codecs obey the same canonical codec laws and restart-stable manifest
  resolution as other codecs. A charge metric names one additive nonnegative
  unit; ledger addition never mixes metric identities. Any adapter
  normalization must prove its reported naturals are in the selected run unit.
- **Cross-table closure:** every `DurableWorkRef` is derived from and resolves
  to one exact Work package; every graph-codec, schema-rule and resolver ID
  resolves uniquely; every operation validator is the one pinned by its
  operation; every generator graph codec is the one pinned by its generator.
- **Root linkage:** each root-entrypoint identity names one input codec,
  graph codec, result family and total constructor
  `start : input -> RunBudget -> RootStart`. Its law proves that for every
  input and budget the graph has the declared boundary and is
  `SchemaSupported` under this same manifest and resolver, and the allocation
  plan is valid for that budget.
  `RunStarted` authorization later proves the persisted graph bytes and plan
  are the canonical encoding and exact plan of that constructor result.
- **Restart stability:** loading the identity named by a journal after any
  restart returns a bundle with the same canonical manifest and the same
  identity-to-package association, including each generator's callback token
  and attached admission law. The abstract model preserves package selection;
  it does not require extensional equality proofs between separately loaded
  function closures. Binding a package token to concrete host binaries,
  process extraction, and loader behavior is a separate P13 refinement.

Every manifest field is projected from an actual package or proved law, never
an independently editable claim. The declared F* record carries the proof
fields; constructing the record is how an instance supplies its contracts.

The interfaces must admit an acyclic F* module dependency: the kernel owns
first-order identities, Work/codec signatures, `Wire`, `GraphDesc`, and schema
ASTs; a first-order manifest-core module owns canonical entries and schema
rules; the resolver consumes only that manifest core plus graph syntax and
returns a derivation/typed graph; a bundle-composition module then joins the
resolver to executable Work/codec tables and proves exact lookup coherence;
the runner consumes that complete bundle. In particular, the resolver does
not import a bundle type that itself is defined using the resolver's result.
S2-02 defines the common manifest-core contract; S2-03 consumes that exact
contract. The implementation packet proposes concrete module names and
ownership; this dependency order is normative.

`LocalWork` refers to pinned, total, pure F* code. Its exact definition and
input/output schemas are fixed by `CodeIdentity`. There is no separate capture
channel: per-run configuration is part of the typed input; fixed
implementation configuration is part of the pinned code identity. If a local
node stops before its output is committed, it may be recomputed after recovery.
Once its `NodeCompleted` event is committed, it must be reused. Correctness
compares full pinned identities and canonical bytes. A `Digest` may index those
bytes, but equality inferred from digest equality requires an explicit
collision-resistance premise.

The API does not require an output to be `option`; it requires authors to put
expected domain failure in the output type where needed. For example,
`option (Report x)` distinguishes a valid absent/failed analysis result from a
successful report. A corrupt journal or a violated host contract is not a
workflow result and must not be forged into `None`.

### 2.1 External operation and adapter contract

An external node uses a typed request and a validated, input-indexed result.
Raw process, network, model, or database output is not an F* value until a
pinned validator constructs the declared result.

The declared result family `o x` is the operation's typed postcondition: the
validator must construct a value inhabiting that exact family for the exact
request `x`, including any evidence needed by downstream proofs. Any stronger
claim about the physical external effect must be stated and proved as an
operation-specific adapter theorem or named premise. Untyped reply bytes alone
establish no workflow fact.

`OperationIdentity` binds the exact operation and adapter definitions,
versions, validator, fixed configuration, input/output schemas, and charge
metric identity. Per-call
configuration is part of the typed request. The canonical
resume descriptor in `CallIntent` is prepared before the first external
effect; it is adapter-defined data, not a process/socket handle. It may be
empty when the adapter can recover by operation identity, call key, and
request alone.

```fstar
type ChargeMetricIdentity
type ArtifactTypeIdentity
type ArtifactStoreIdentity
type ArtifactRef (a:Type0)
type PackedArtifactRef = exists a:Type0. ArtifactRef a

type OpRef (i:Type0) (o:i -> Type0) = {
  identity:OperationIdentity;
  request_codec:Codec i;
  output_codec:IndexedCodec i o;
  validate_reply:x:i -> Bytes -> Tot (option (o x));
  charge_metric:ChargeMetricIdentity;
  maximum_charge:nat
}

type CallIntent = {
  call_key:CallKey;
  adapter_resume_data:Bytes
}

type CallOutcome (i:Type0) (o:i -> Type0) (x:i) = {
  call_key:CallKey;
  output_bytes:Bytes; (* canonical IndexedCodec i o encoding at x *)
  evidence:Bytes;
  charge:nat;
  artifact_refs:list PackedArtifactRef
}
```

`maximum_charge`, adapter receipt charges, and generator charge pools are
measured in the one `ChargeMetricIdentity` selected by `RunBudget` for this
run. `OperationIdentity` pins the operation's metric. A run can use an
operation only when that identity equals the run metric; an adapter may
normalize its native measurements only if its pinned contract proves that
normalization. `maximum_charge` and a receipt's `charge` are therefore
comparable naturals. Expansion fuel is a separate dimension.

The adapter's `reply_bytes` are raw external bytes. If
`validate_reply x reply_bytes = Some y`, the workflow encodes `y` with the
pinned `IndexedCodec i o` at exact input `x` and journals those canonical
typed `output_bytes`; evidence, charge, and artifact references are copied
from the same receipt. Replay decodes `output_bytes` with that indexed codec;
it does not rerun the adapter validator or external effect. The P7 append
witness proves that these event fields are exactly the projection of one
accepted adapter receipt. An external operation is not modeled as a pure
function of its request. Separate calls with the same request may yield
different accepted outputs; after recovery, the journaled outcome is reused,
or a still-pending call is resumed under its existing key.

Before invoking an adapter, the runner durably commits a `CallIntent`. After a
restart it gives that same intent to the same pinned adapter to continue or
resolve the same logical call. The adapter owns whatever process, connection,
remote idempotency key, or durable continuation it needs; none of those live
handles is stored as an F* value or journal payload.

The adapter contract is semantic, not a prescribed retry algorithm. A
committed intent has the stable key defined below and one canonical request,
input, and resume descriptor. Recovery may dispatch or query that same key
more than once. Therefore the adapter contract must prove
**effect-safe resumption**: repeated delivery joins or queries the same
logical operation through stable-key deduplication/status lookup, or the
operation-specific effect is idempotent/reconciled so retries cannot create
an unaccounted second effect. A non-idempotent operation with no such method
is not admitted. “Same intent” by itself is insufficient: if a remote effect
occurs and its reply is lost, blind redispatch could perform the effect twice.

For one key the adapter must preserve one logical operation and one terminal
outcome, correlate reply/evidence/charge to that key and exact request, and
eventually make that outcome available under explicit liveness conditions.
Distinct keys may have nondeterministic outcomes, including different
outcomes for identical requests. `CallOutcome` is the sole durable settlement;
after it commits, that key cannot be dispatched again. The outer `option` of
`validate_reply` means “these bytes were accepted as a typed result”; the
result itself may independently be `None` for domain failure. Irreconcilable
remote effects are outside the contract; there is no durable “outcome
unknown” state. Charge evidence must be truthful and at most
`maximum_charge`; the journal reserves before invocation and settles once.

#### P7 keyed history and receipt law

The adapter contract is over a **logical call**, not over one transport
attempt. For an adapter key define

```text
K = (operation_identity, CallKey)
Q = (canonical_request_bytes, committed_resume_data)
T = (reply_bytes, evidence, charge, artifact_refs:list PackedArtifactRef)
```

`CallKey` is a full `NodeOccurrence`, so its graph path contains the run
identity; the operation identity pins the adapter, configuration, codecs, and
validator. Thus `K` cannot alias another run, occurrence, or pinned operation.
`Q` is recomputed from the committed intent and the exact replay-reconstructed
input using the pinned request codec. These exact identities and bytes are
the binding; a hash may replace bytes only with a separate collision-free
contract. The intent stores resume data once, while the request remains
derived from committed input, avoiding a second durable request source.

The abstract adapter history for each `K` has one immutable binding and at
most one terminal tuple:

```text
Bind(K,Q) : absent | fixed(Q)
Terminal(K,Q) : absent | fixed(T)

request(K,Q) -> Pending | Terminal(T) | KeyConflict
```

The first authorized request fixes `Q`. Every later overlapping or recovered
submission/query for that key must carry the same `Q`; a different request or
resume descriptor yields `KeyConflict` and cannot start another logical call.
Any terminal response for a fixed `(K,Q)` has the same exact `T`,
including evidence, charge, and artifact references. Retries may observe
`Pending` or that same `T`; they cannot produce a second terminal tuple.
Distinct keys may choose different terminal tuples even when their inputs and
request bytes are equal. This is per-call stability, not purity of the
external operation as a function of its request.

Define the deterministic persistence projection for the exact reconstructed
input `x`:

```text
persist_x(T) =
  let Some(y) = validate_reply x T.reply_bytes in
  (IndexedCodec.encode(x,y), T.evidence, T.charge, T.artifact_refs)
```

The first component is the event's canonical `output_bytes`. The projection
is undefined if validation rejects the raw reply. Equal terminal tuples for
the same key therefore project to equal journal fields. `CallOutcome` does
not store raw `reply_bytes`; its authorization witness retains the proof
connecting that receipt to the canonical typed bytes.

`P7ReceiptWitness(op,K,Q,T,x)` is the operation-specific adapter contract
evidence required by `AuthorizedEvent(CallOutcome)`. It establishes that the
receipt belongs to this one logical call and exact reconstructed input `x`,
that the adapter's effect law holds, that `evidence` justifies the reported
charge and effect status, and that `charge <= maximum_charge` in the pinned
run metric. It also proves
`persist_x(T)` is defined and equals the `CallOutcome` event's output bytes,
evidence, charge, and artifact references. The indexed output codec then
decodes those bytes to `y : o x`. Output validation alone does not prove a
physical effect or truthful charge. P8 proves the reserved amount settles
once; P9 proves typed artifact references have durable backing and restore to
the same logical resource version when that stronger claim is made.

For every `(K,Q)`, the adapter supplies an operation-specific `EffectSafe`
law over **all** submit/query interleavings, including overlapping retries and
adapter restart. Let `LogicalCall(op,K,Q,T)` be the operation-specific
abstract relation between this binding, its one terminal receipt, and its
observable effect. The physical trace must refine at most one such logical
call; repeated physical steps are admitted only when the
idempotence/reconciliation law proves they add no unaccounted effect and
determine whether and what effect occurred. Deduplication/status state must
survive adapter restart, or an equivalent durable remote status source must
do so. A non-idempotent
operation with a lost-reply ambiguity and no reconciliation is inadmissible.
The workflow journal alone cannot resolve whether such an external effect
occurred.

P7's safety result is conditional on this adapter contract. P15 proves the
workflow submits only after the matching `CallIntent` commit, binds each
submission to the replayed `K,Q`, and accepts a result only for a still-pending
intent. P3 permits at most one `CallOutcome`; its commit absorbs the key and
P15 prevents a new dispatch afterward. A late or duplicate callback after
outcome commit is discarded. A callback from an earlier attempt while the
intent is still pending may be accepted only because same-key terminal tuple
stability makes it equivalent to a retry result.

Each adapter submission carries one distinct committed intent. The workflow
may submit several such requests while earlier calls remain outstanding. The
adapter may complete them in any order. Outcomes are keyed,
validated, and journaled individually; one slow request must not block
acceptance of an unrelated completed outcome. Adapter delivery may be
at-least-once. Exactly-once physical transport or service execution is not
claimed; effect safety is supplied by the stable-key or operation-specific
contract above.

For the multi-inflight contract, the configured adapter capacity `B` is finite
and at least two. It may accept any distinct key while fewer than `B` calls
are outstanding, without waiting for earlier keys to finish. A terminal
response for any key can be validated and queued for its own serial outcome
append regardless of other pending keys. If all capacity is occupied by
nonterminating calls, no further dispatch progress is promised. P7 liveness
is separate from safety: under adapter availability, fair retry/query and
response service, eventual completion or definitive reconciliation for each
admitted key, and finite relevant crashes, every committed pending intent
eventually yields one accepted terminal tuple (including a typed domain
failure when represented by the result family). P14 additionally requires
serial journal progress and fair workflow scheduling. At-least-once delivery
alone proves no progress.

Inline and reusable-library authoring are two ways to construct the same
`OpRef`; both have identical call-intent, validation, journaling, effect, and
proof obligations. The adapter is not an unchecked escape hatch.

### 2.2 Dynamic graph description and construction API

`GraphDesc` is the uniform first-order description of a finite typed DAG. Its
vertices are occurrences of `Work` nodes, and its edges connect typed output
ports to typed input ports. It records the root input and a typed output
mapping. It is not a list of pre-authored child workflows, nor a special
execution mechanism for a future workflow API.

The minimal graph construction interface has three operations:

1. Start with the graph's typed root input port.
2. Add a `Work` node, supplying a typed wiring from existing ports to that
   node's input. The operation returns one typed reference to the new output,
   which becomes a port available to later nodes. A port may feed any number
   of nodes, so fan-out is ordinary wiring.
3. Finish with typed wiring from available ports to the graph output.

Wiring is first-order port selection, codec-backed constants, and product
construction, not a captured closure. Constants are data in the graph, never
computed closures. Any computation needed to transform values is another
`LocalWork` or `ExternalWork` node. Convenience builders are libraries and must
elaborate to this interface. A concrete representation may differ if it
proves the same laws.

```fstar
type ConstantRef = { codec:CodecIdentity; encoded_value:Bytes }
type Wire (i:Type0) (x:i) = RootWire | OutputWire NodeKey
  | ConstantWire ConstantRef
  | PairWire (Wire i x) (Wire i x)
  | FstWire (Wire i x) | SndWire (Wire i x)
type PortContext (i:Type0) (x:i)
type PortEnv (i:Type0) (x:i) (ports:PortContext i x)
type GraphBuilder (registry:PinnedRegistryBundle)
  (i:Type0) (x:i) (ports:PortContext i x)
type Wiring (i:Type0) (x:i) (ports:PortContext i x)
  (a:PortEnv i x ports -> Type0)
type PortRef (i:Type0) (x:i) (ports:PortContext i x)
  (a:PortEnv i x ports -> Type0)
type GraphNode (i:Type0) (x:i) = {
  key:NodeKey;
  work_ref:DurableWorkRef;
  input_wire:Wire i x
}
type GraphDesc (i:Type0) (o:i -> Type0) (x:i) = {
  (* nodes are stored in a topological sequence; keys need not be numeric *)
  nodes:list (GraphNode i x);
  output_wire:Wire i x
}
type FiniteTypedDAG (i:Type0) (o:i -> Type0) (x:i) = GraphDesc i o x
val dag_wf : registry:PinnedRegistryBundle -> x:i ->
  FiniteTypedDAG i o x -> Tot prop
type GenerationAllocation = {
  expansion_fuel:nat;
  charge_allocation:nat
}
type RunBudget = {
  total_expansion_fuel:nat;
  charge_metric:ChargeMetricIdentity;
  total_charge:nat
}
type ChargeMetricMember (manifest:RegistryManifest)
  (metric:ChargeMetricIdentity) : prop
type OccurrenceAllocation = {
  node:NodeOccurrence;
  allocation:GenerationAllocation
}
type OccurrencePlan = list OccurrenceAllocation
type CodecMember (registry:PinnedRegistryBundle) (#a:Type0)
  (codec:Codec a) : prop
type IndexedCodecMember (registry:PinnedRegistryBundle) (#i:Type0)
  (#family:i -> Type0) (codec:IndexedCodec i family) : prop

val root_port : i:Type0 -> x:i -> PortContext i x
val extend : ports:PortContext i x -> key:NodeKey ->
  (PortEnv i x ports -> Type0) -> PortContext i x
val prior_env : ports:PortContext i x -> key:NodeKey ->
  family:(PortEnv i x ports -> Type0) ->
  PortEnv i x (extend ports key family) -> Tot (PortEnv i x ports)
val builder_nodes : GraphBuilder registry i x ports
  -> Tot (list (GraphNode i x))
let next_key builder = length (builder_nodes builder)

let interpret_graph (g:GraphDesc i o x) : FiniteTypedDAG i o x = g
val graph_isomorphic : registry:PinnedRegistryBundle ->
  FiniteTypedDAG i o x -> FiniteTypedDAG i o x -> Tot prop
val eval_wiring : Wiring i x ports a -> env:PortEnv i x ports -> Tot (a env)
val root_wiring : x:i -> Wiring i x (root_port i x) (fun _ -> x)
val constant_wiring : registry:PinnedRegistryBundle ->
  codec:Codec a -> member:CodecMember registry codec -> value:a ->
  Wiring i x ports (fun _ -> a)
val indexed_constant_wiring : registry:PinnedRegistryBundle -> x:i ->
  codec:IndexedCodec i family ->
  member:IndexedCodecMember registry codec -> value:family x ->
  Wiring i x ports (fun _ -> family x)
val port_ref_key : PortRef i x ports a -> NodeKey
val port_wiring : PortRef i x ports a -> Wiring i x ports a
val pair_wiring :
  w1:Wiring i x ports a ->
  b:(env:PortEnv i x ports -> a env -> Type0) ->
  w2:Wiring i x ports (fun env -> b env (eval_wiring w1 env)) ->
  Wiring i x ports (fun env -> p:(a env) & b env p)
val fst_wiring :
  w:Wiring i x ports (fun env -> p:(a env) & b env p) ->
  Wiring i x ports (fun env -> a env)
val snd_wiring :
  w:Wiring i x ports (fun env -> p:(a env) & b env p) ->
  Wiring i x ports (fun env -> b env (fst (eval_wiring w env)))

val start_graph : registry:PinnedRegistryBundle -> x:i
  -> GraphBuilder registry i x (root_port i x)
val finish_graph : GraphBuilder registry i x ports ->
  Wiring i x ports (fun _ -> o x)
  -> Tot (option (GraphDesc i o x))

val graph_wf : registry:PinnedRegistryBundle -> x:i ->
  GraphDesc i o x -> Tot prop
val graph_complete : registry:PinnedRegistryBundle ->
  x:i -> dag:FiniteTypedDAG i o x -> Lemma
  (dag_wf registry x dag ==>
    (exists g:GraphDesc i o x.
      graph_wf registry x g /\ graph_isomorphic registry
        (interpret_graph g) dag))
type GraphCodec (i:Type0) (o:i -> Type0) = {
  identity:GraphCodecIdentity;
  encode_graph:x:i -> g:GraphDesc i o x -> Tot Bytes;
  decode_graph:x:i -> Bytes
    -> Tot (option (GraphDesc i o x));
  roundtrip:x:i -> g:GraphDesc i o x -> Lemma
    (decode_graph x (encode_graph x g) == Some g);
  canonical:x:i -> bytes:Bytes -> g:GraphDesc i o x
    -> Lemma (decode_graph x bytes == Some g
              ==> bytes == encode_graph x g)
}

type NodeAllocation = {
  key:NodeKey;
  allowance:GenerationAllocation
}
type GraphAllocationPlan = list NodeAllocation
type RootStart (i:Type0) (o:i -> Type0) (x:i) = {
  graph:GraphDesc i o x;
  allocation_plan:GraphAllocationPlan
}
type RootEntry (registry:PinnedRegistryBundle) (i:Type0) (o:i -> Type0) = {
  identity:RootEntryIdentity;
  input_codec:Codec i;
  graph_codec:GraphCodec i o;
  start:x:i -> budget:RunBudget -> Tot (RootStart i o x);
  start_wf:x:i -> budget:RunBudget -> Lemma
    (graph_wf registry x (start x budget).graph /\
     root_allocation_plan_wf (registry_manifest registry) budget
       (start x budget).graph (start x budget).allocation_plan)
}
type GeneratedGraph (i:Type0) (o:i -> Type0) (x:i)
  (parent:GenerationAllocation) = {
  descriptor:GraphDesc i o x;
  child_plan:GraphAllocationPlan
}

type GeneratorRef (i:Type0) (o:i -> Type0) = {
  identity:GeneratorIdentity;
  input_codec:Codec i;
  graph_codec:GraphCodec i o;
  generate_graph:x:i -> charge_metric:ChargeMetricIdentity ->
    allocation:GenerationAllocation
    -> Tot (GeneratedGraph i o x allocation)
}

type Work (i:Type0) (o:i -> Type0) =
  | LocalWork : CodeRef i o -> Work i o
  | ExternalWork : OpRef i o -> Work i o
  | GenerateWork : GeneratorRef i o -> Work i o
type WorkMember (registry:PinnedRegistryBundle) (#i:Type0)
  (#o:i -> Type0) (work:Work i o) : prop
val allocation_plan_wf : manifest:RegistryManifest ->
  charge_metric:ChargeMetricIdentity -> parent_fuel:nat ->
  parent_charge:nat -> graph:GraphDesc i o x ->
  plan:GraphAllocationPlan -> Tot prop
val root_allocation_plan_wf : manifest:RegistryManifest ->
  budget:RunBudget -> graph:GraphDesc i o x ->
  plan:GraphAllocationPlan -> Tot prop
type GeneratorMember (registry:PinnedRegistryBundle)
  (generator:GeneratorRef i o) : prop =
  forall (x:i) (metric:ChargeMetricIdentity)
    (parent:GenerationAllocation).
    let result = generator.generate_graph x metric parent in
    ChargeMetricMember (registry_manifest registry) metric ==>
      graph_wf registry x result.descriptor /\
      allocation_plan_wf (registry_manifest registry) metric parent.expansion_fuel
        parent.charge_allocation result.descriptor result.child_plan

The displayed `GeneratorMember` proposition states the universal law. Its
implementation witness also carries exact membership in the pinned generator
package table; public lookup returns that package and witness together, so a
caller cannot supply a different callback and prove a law about it.

val child_occurrence : generator_occurrence:NodeOccurrence -> Tot GraphOccurrence
let child_occurrence occurrence =
  ChildGraph occurrence.graph occurrence.key
val lift_graph_plan : generator_occurrence:NodeOccurrence ->
  plan:GraphAllocationPlan -> Tot OccurrencePlan
val lift_root_plan : run:RunIdentity ->
  plan:GraphAllocationPlan -> Tot OccurrencePlan

val add_node : builder:GraphBuilder registry i x ports ->
  work:Work a b -> member:WorkMember registry work ->
  wiring:Wiring i x ports (fun _ -> a)
  -> Tot (option (next:GraphBuilder registry i x
       (extend ports (next_key builder)
       (fun prior -> b (eval_wiring wiring prior))) &
       ref:PortRef i x (extend ports (next_key builder)
         (fun prior -> b (eval_wiring wiring prior)))
         (fun env -> b (eval_wiring wiring
           (prior_env ports (next_key builder)
             (fun prior -> b (eval_wiring wiring prior)) env)))
         {port_ref_key ref == next_key builder}))
```

For `GenerateWork generator`, `WorkMember registry` includes exact membership
in the pinned work registry and a `GeneratorMember registry generator`
proof. This binds the callback, its graph codec, and its output/allocation
contract to the same pinned entry.

`generate_graph` is total and pure: each exact `(x, charge_metric,
allocation)` determines one descriptor and one graph-local allocation plan.
The plan is keyed by the descriptor's node keys. A pinned `GeneratorMember`
proof establishes for every input, run metric, and parent allocation,
including zero fuel or zero charge, that the descriptor resolves to a
`graph_wf` graph and its plan satisfies the rules
below. Child generators always receive positive fuel. If parent fuel is zero,
the plan therefore contains no child generator. A zero-charge result cannot
allocate a positive external maximum. This is a proof obligation on each
admitted generator, not an unchecked runtime assertion or an `assume` in the
kernel.
`GenerateWork` remains indexed by the workflow's
result family `o`. Committing the generated descriptor introduces its nodes,
and its typed output wire supplies the generator occurrence's eventual `o x`
result. The descriptor is not recorded as a `NodeCompleted` output. This
keeps graph generation as a control transition while preserving the ordinary
workflow input/output type.

Every `Work` admitted by the builder has one derived first-order durable
reference. It records the node kind, pinned code/operation/generator identity,
and input/output codec identities. Schema tokens are pinned metadata of the
resolved work and codec entries, not another independently supplied node
field. The immutable registry resolves the reference to one exact semantic
`Work` and rejects unknown or mismatched identities. The typed in-memory
`Work` itself is the builder input; the durable reference is derived from it,
so there is no independently supplied typed reference/package pair to keep
synchronized. There is no per-node typed registry wrapper; the one pinned
registry bundle remains necessary to resolve heterogeneous durable references
after decoding. Exact membership and type transport are P0/P2 proof
obligations, not established by this declaration skeleton.

The builder contract is stricter than the current declaration: an inserted
`Work` must be the exact executable entry selected from the builder's pinned
registry bundle. The proof interface must express this as erased lookup
evidence or make insertion obtain the value from the resolver itself. This is
not another durable reference or runtime wrapper; it prevents running one
definition and recovering another under the same label. The current
`add_node` and `typed_graph_witness` declarations do not yet enforce this, so
P0/P1 cannot rely on them until the membership link is added.
Plain and indexed constant wiring need the analogous erased proof that the
supplied codec is the exact entry in the same bundle; indexed codecs must be
resolved and decoded at the exact graph root input. The current wiring
constructors and `wire_typing_witness` also omit this link.

#### 2.2.1 Typed schema evidence for graph resolution

First-order identity equality does not establish equality of hidden F* types.
The pinned bundle therefore has one canonical schema manifest containing
first-order type/value expressions and their proved interpretations. A
schema token names both the canonical expression and its exact carrier:

```fstar
type TypeExpr
type ValueExpr
type SchemaToken (a:Type0) = {
  identity:SchemaIdentity;
  expression:TypeExpr;
  quote_value:a -> Tot ValueExpr;
  quote_denotes:x:a -> Lemma
    (schema_value_denotes expression (quote_value x) x)
}
type SchemaMember (m:SchemaManifest) (token:SchemaToken a) : prop =
  manifest_entry_exactly_denotes(m, token.identity,
                                 token.expression, a)
val schema_identity_coherent : m:SchemaManifest ->
  left:SchemaToken a -> right:SchemaToken b ->
  SchemaMember m left -> SchemaMember m right ->
  left.identity == right.identity -> Lemma (a == b)

type IndexedSchemaFamily (i:Type0) (o:i -> Type0) = {
  identity:SchemaIdentity;
  input_expression:TypeExpr;
  output_expression:ValueExpr -> TypeExpr;
  quote_input:i -> Tot ValueExpr;
  quote_input_denotes:x:i -> Lemma
    (schema_value_denotes input_expression (quote_input x) x);
  family_denotation:forall x:i.
    schema_denotes (output_expression (quote_input x)) (o x)
}

type PlainCodecSchema (a:Type0) = SchemaToken a
type IndexedCodecSchema (i:Type0) (o:i -> Type0) = {
  input_schema:SchemaToken i;
  output_schema:x:i -> SchemaToken (o x)
}
```

The declarative core grammar is fixed, not supplied by an arbitrary resolver
callback. `SchemaBound` is a typed, locally nameless value variable. Its
nearest-first binder context records each variable's schema type. `Sigma(A,B)`
checks `A` in the current context and `B` under one added value of type `A`;
`Refine(T,P)` checks `T` in the current context and `P` under one added
candidate value of type `T`. There is no added binder in a `Sigma` domain or a
`Refine` base. Thus `SchemaBound 0` denotes the nearest value binder in either
the `Sigma` codomain or the `Refine` predicate. A bound index outside its
declared binder is ill-scoped and rejected. Lifting and substitution are
capture-avoiding across both binder forms.

~~~text
Ty ::= Atom(SchemaIdentity) | Unit | Bool | Nat | Int
     | Product(Ty,Ty) | Sum(Ty,Ty) | List(Ty) | Option(Ty)
     | Sigma(Ty,Ty)                 -- second argument under one binder
     | Family(SchemaIdentity,list Value)
     | Refine(Ty,Pred)

Value ::= Bound(nat) | Root | Port(NodeKey)
       | Constant(CodecIdentity,CanonicalBytes)
       | UnitVal | BoolLit(bool) | NatLit(nat) | IntLit(int)
       | Pair(Value,Value) | Fst(Value) | Snd(Value)
       | Constructor(SchemaIdentity,list Value)
       | IndexCall(SchemaIdentity,list Value)

Pred ::= True | False | Equal(Value,Value) | And(Pred,Pred)
~~~

`Atom` is opaque: equality follows only from identical pinned identities or a
manifest-pinned alias equation with a denotation proof. Every `Family`,
`Constructor`, and `IndexCall` entry names an exact manifest package and has
one fixed F* denotation. `IndexCall` packages a total function and terminating
normalizer; each normalization/equation law has a proof of denotational
soundness. No callback may add an unverified reduction rule. The base
normalizer is structural and terminates on finite syntax. Equality derivations
use reflexivity, symmetry/transitivity, structural congruence, literal
normalization, substitution of declared assumptions, and the finite equations
from the exact selected schema packages. There is no general SMT-success rule. The derivation system
is sound for every valuation; completeness is claimed only for equations
derivable in this declared calculus. A future extension enlarges both the
manifest language and theorem boundary and requires its own termination,
soundness, completeness, and identity-binding proofs.

These are schematic F* declarations; S2-03 specifies the universe-safe AST
and its interpretation as a mathematical model. These declarations state
contracts and theorem targets; they are not an executed F* module or a claim
that those theorems are already discharged. The schema objects are proof
metadata, not per-node journal fields. Quotation is total and
 denotation-preserving. Opaque carriers may quote only their exact codec
identity and canonical bytes, which equality rules may compare only by exact
identity/bytes or a proved alias. The manifest
constructor proves that each schema identity has one canonical expression and
one denotation, bound to the exact pinned registry manifest. Work input/output
schemas are derived from the codecs already stored in that Work; quotation
does not introduce another value source. No cast, runtime type check, or
unchecked assumption is valid.

#### Normative edge rule

The current Work signature has one fixed input carrier and an input-indexed
output family. For each node k, resolution yields exact registered signature
`Work A_k B_k`, an input expression `e_k`, and an inferred input-wire type
`T_k`. The required node judgment is `T_k ≡ A_k`; its output port then has
type `B_k(e_k)`. For each legal environment `rho`, the denotation theorem
must establish `eval(input_wire(k),rho) : A_k` and the output type
`B_k(eval(input_wire(k),rho))`.

`LegalEnv(m,x,prefix)` is defined inductively over the topological prefix,
independently of resolver success. This adopts the strict static policy for
S2-03: a validator postcondition cannot narrow graph-typing environments; a
restriction must be part of the declared output family. It fixes the root port to the exact
boundary value `x` and each constant port to the value decoded from its exact
pinned codec and canonical bytes. For each earlier node `j`, it evaluates
that node's input wire from the already assigned referenced ports, obtaining
`x_j`, then extends the environment with any value inhabiting the exact
declared family `B_j(x_j)`. This step executes no Work and assumes no
particular result. An external validator may accept only a subset of that
family, but every accepted value is included in the quantified set. Graph
typing does not use validator behavior or a validator postcondition to narrow
the set. A desired restriction must be represented in the declared output
family itself, with the validator constructing any required evidence. A
generated graph is checked at its exact recovered root input `x`; all its
internal earlier outputs remain universally quantified.

Every node input wire must have exactly its Work's fixed input carrier in
every legal environment. For a direct edge from producer p to consumer k,
the wire rule gives producer output type `B_p(e_p)`; the consumer rule accepts
that edge only when its denotation equals `A_k` for every legal environment:

~~~text
  forall rho : LegalEnv(m,x,prefix(k)).
    TypeDenote(m,rho,B_p(e_p)) = A_k
~~~

Here `e_p` is the producer's input expression in `rho`, so any dependent index
is evaluated from the exact root, constants, and earlier typed ports. Equality
must follow from exact resolved signatures and static graph constraints. It
may not depend on an observed Work result, external reply, adapter behavior,
or proof payload supplied by either endpoint. Pair, projection, and composite
wires use the same recursive judgment, with their inferred product types.
A resolver may construct erased proof terms while checking the rule, but
derives them from declared graph syntax and pinned signatures; it accepts no
independent edge evidence and serializes no per-edge proof. Failure to prove
the universal node-input judgment rejects the descriptor before execution.

An external producer returning Sigma n. vector n cannot feed a consumer
fixed at vector 3 when n is unconstrained, even if one observed reply has
n = 3. It is accepted only when signatures and static constraints establish
the consumer carrier for every legal environment. Work nat (fun n -> Prime n)
remains expressible; its own output is indexed by exact input, but this does
not prove an unrelated edge about an unknown runtime index.

The abstract boundary is one registry-pinned, proof-producing
`GraphResolver`, part of the immutable bundle named by `RegistryIdentity`.
The selected implementation route is a canonical first-order type/value
schema language for manifest expressions, interpreted by proof-bearing
packages in the pinned bundle. Schema entries are linked by proofs
to exact registered F* carriers, indexed families, Work signatures, codecs,
and supported constructors. A schema entry is not a second per-node
signature. Opaque atoms compare only by exact pinned identity or a proved
alias law. Indexed families expose canonical schema applications; finite
normalization/equality rules come from the exact law-bearing packages selected
by the manifest. The resolver reconstructs
transient typed wiring and proof terms from graph syntax and these schemas;
no proof term or per-edge certificate is serialized.

The exact package selected by a schema-family/rule owner row is the source of
its typed argument telescope and any finite normalization/equation declarations.
These declarations are first-order package data paired with proof fields, not unchecked
callbacks. The owner row's denotation-law contract token must project from
that exact package, and P0 proves the package is unique and restart-stable.
This keeps signatures and equations attached to the one pinned package rather
than duplicating them in a second manifest table. A rule package is a typed
sum (constructor or index function); a `SchemaConstructor` or `SchemaIndexCall`
AST node is accepted only by the matching variant. Constructor results are
indexed by the declared parent family and computed indices, with the parent
obtained through that exact package-map lookup. The package's dependent
carrier telescope has the arity of its first-order argument telescope;
`SchemaAtom` selects the nullary case, and `SchemaFamily` applies the same
package at a matching arity (including zero indices). Each package uses its
codec object as the single codec source and carries membership for that exact
object in the shared codec registry. P0 proves that registry identities
project from the canonical manifest codec rows. Index-call packages are total
and each declared equation has a denotational-soundness proof. A future
representation may serialize these package declarations in
the schema payload, but it must prove equivalent exact projection and must not
create a second source of truth.

The law token and base package interface are not themselves semantic evidence.
The schema interface is staged: A05b defines the exact manifest-indexed base
package map; A05c defines the canonical interpretation and typed judgments
over that map; A05d defines an `AdequateSchemaPackages` wrapper indexed by the
exact base map and supplies checked law fields. Those fields establish, for
each selected package, binder-by-binder AST/carrier alignment, family/result
denotation, constructor result-index and inhabitance agreement, index-call
result typing, equation soundness, and codec/index coherence. A05d proves the
generic consequences of those fields; they are explicit proof-bearing package
inputs, not assumptions hidden behind `DenotationLawContract` tokens. A04/P0
stores and reloads that same base map together with its adequacy witness, and
proves the canonical owner-row token selects the exact law field. Schema
interpretation, graph resolution, and equality may consume only the adequate
wrapper, never a raw package map. Thus a token-only, empty-carrier, or
unrelated-callback package is not executable merely because its syntax and
identities match.

The checker is total and proof-producing. It accepts an equality only by a
derivation in the declared schema calculus (canonical normal forms,
structural congruence, and registered proved equations). Any extension such
as arithmetic or refinement reasoning must be a pinned terminating
procedure with proved soundness and completeness for its stated fragment.
Unknown means reject. Arbitrary F* `Type0` equality, opaque closure equality,
or a successful unchecked SMT query is not a resolver rule. S2-03 fixes this
specification-level AST, binder representation, and equality calculus; later
source proofs must establish the stated soundness and completeness results.

`SchemaSupported(m,x,g)` is a declarative derivability predicate, not an alias
for resolver success. `StructuralDAG(g)` means the node list is finite and has
unique keys, each node reference names an exact manifest member, every
`OutputWire` in a node's input names a strictly earlier node in that list, and
every output-wire reference names an existing node. The graph's serialized
node list is therefore itself a topological order; no second topological-order
field exists. Its exact list order is preserved by the graph codec. Different
valid topological enumerations denote isomorphic DAGs, not identical canonical
descriptor bytes.

The schema language has a fixed interpretation. `ValueDenote(m,rho,e)`
evaluates a well-scoped, well-typed value expression in the graph environment
and the typed local value-binder environment; `TypeDenote(m,rho,T)` returns
its denoted F* type; and `PredDenote(m,rho,P)` returns its proposition.
`Unit`, products, sums, lists, options, and sigma types use their ordinary F*
meanings; `Family`, `Constructor`, and `IndexCall` use the unique exact
manifest package. Refinement has the explicit dependent meaning
`TypeDenote(Refine(T,P)) = { z:TypeDenote(T) | PredDenote(P,rho extended by z) }`.
The `Refine` predicate is evaluated at the candidate value being classified.
Locally nameless lifting, substitution, and denotation-commutation laws cover
both the `Sigma` codomain and the `Refine` predicate, as well as every
`IndexCall` application.

The syntax-directed judgments are:

~~~text
m; Δ; Γ; Ξ ⊢wire w ⇓ (e : T)
m; Δ; Γ; Ξ ⊢type T ≡ U
m; Δ; Γ; Ξ ⊢pred P
~~~

Here `Γ` is the graph's root/port telescope and `Ξ` is the nearest-first
typed local value-binder context. The `Sigma` codomain and `Refine` predicate
rules extend `Ξ` with their declared domain type. All judgments require
well-scoped and well-typed bound variables; denotation theorems are stated
only for such derivations.

The context is itself generated, never caller-authored:

~~~text
Delta(m,x,[]) = [RootIs(quote_input(x))]
Delta(m,x,nodes ++ [k]) = Delta(m,x,nodes)
  ++ [ConstantIs(c,decode_canonical(c)) for constants c in node k's input]
  ++ [PortRefinement(k,instantiate_output_predicate(P,e_k,Port(k)))
      when B_k(e_k) is Refine(T,P)]
~~~

`RootIs` and `ConstantIs` record denotation facts, not arbitrary equalities.
When the instantiated output family `B_k(e_k)` is itself `Refine(T,P)`,
`instantiate_output_predicate` substitutes
the exact input expression `e_k` for the family's input index and substitutes
`Port(k)` for the refinement candidate bound at index 0, using capture-avoiding
substitution while preserving outer graph references. `PortRefinement` is
justified by the typed value assigned to that output: it is extracted from the
proof that this value inhabits the declared refined output type. This fact is
entailed by the full declared family; it does not narrow `LegalEnv` by an
external validator postcondition.
The exact context therefore contains only facts entailed by the root value,
canonical graph constants, and the declared output families. The complete
output-wire context is `Delta(m,x,g.nodes)` extended with `ConstantIs` facts
for constants appearing in `g.output_wire`. `WireDerives`
and `TypeEqualityDerives` below mean existence of finite derivation trees in
the displayed judgments. The semantics of `LegalEnv` is the dependent
interpretation of `PortCtx`: root and constants are fixed as above, and each
prior node output is any inhabitant of its declared output family at the input
wire value reconstructed from that environment. `LegalEnv` includes every
validator-accepted external output because the validator result is typed in
that full family; it does not use a validator postcondition to exclude other
inhabitants.

The wire rules are syntax-directed: root, canonical constant, prior port,
dependent pair, first projection, and second projection. The root rule uses
the exact root-schema quotation. A constant rule requires an exact pinned
codec identity and successful decode of canonical bytes; an indexed constant
is decoded at the exact graph input. A `Port(k)` rule requires that `k`
precede the current node and uses its exact output schema family. The type
rules are reflexivity, symmetry, transitivity, constructor congruence, dependent substitution,
canonical normalization, and exact manifest equations. The predicate rules
are truth, exact well-scoped assumptions from `Δ`, conjunction
introduction/elimination, and equality substitution; they are intuitionistic.
Refinement types compare only when their base types are equal and their
predicates are equivalent under the same added candidate-value binder and its
domain, by two derivations in this predicate calculus (or by one exact
manifest-pinned equivalence law with its two implication proofs). There is no
rule that adds a fact to `Δ`, invokes an unchecked solver, or learns from a
runtime value. The
schema soundness theorem proves each wire's denotation, each predicate fact,
and each type equality for every legal environment satisfying `Δ`.

`Γ(m,x,prefix)` is the dependent telescope of root and earlier node ports.
Each judgment is instantiated with the exact `Δ(m,x,prefix)`,
`Γ(m,x,prefix)`, and its local binder context `Ξ`. `Root` denotes the exact
quote of `x`; `Port(k)` denotes the expression assigned to that earlier
output; `Family` and `IndexCall` arguments are substituted capture-avoidably
under locally nameless `Sigma` and `Refine` binders. For example,
`Refine(Nat, Equal(Bound(0), NatLit(3)))` denotes the singleton type containing
3. `Bound(0)` in that predicate without the `Refine` binder is ill-scoped.

Each judgment has a finite derivation tree. Its denotation theorem states
that for every `rho : LegalEnv(m,x,prefix)`, wire expressions and types are
correctly interpreted, predicates follow from `Δ`, and type equality yields
equal F* types. These are not host identity comparisons, runtime type tests,
unchecked SMT results, or equalities inferred from sampled outputs. The type
calculus uses reflexivity, symmetry, transitivity, structural congruence,
dependent substitution, canonical normalization, exact manifest equations,
and exactly the `Δ` assumptions above. `Refine` types compare only through the
specified predicate-equivalence rules under the candidate binder and their
denotation proofs. No rule
may introduce a fact merely because it would make one graph edge typecheck.

`SchemaDerivation` provides these finite wire/type derivations for every node
input and graph output. In particular, for an external node it covers every
`y` accepted by `validate_reply(x_j,reply)` at that environment's exact
reconstructed input `x_j`; the legal set is still the full declared result
family. Resolver success and builder acceptance are theorems about this
independent derivability relation, not its definition.

The manifest lists the admitted constructors and each extension equation with
its exact F* denotation theorem. An arbitrary procedure or opaque callback
cannot add an equality rule. S2-03 specifies the concrete AST, judgments,
semantic interpretation, exact theorem statements, and proof dependencies;
it does not implement F* declarations or discharge source-level VCs. A later
implementation DAG must prove substitution, checker soundness/completeness,
resolver, builder, and codec theorems from these definitions.

`RootSchemaAvailable(m,x)` means the exact root input codec/schema is a pinned
manifest member and its total quotation denotes `x`. The public graph builder
carries a private prefix witness. `start_graph` returns exactly the empty
root-only prefix. A successful `add_node` preserves
all prior syntax and adds exactly the supplied fresh node and input wire; its
new `PortRef` denotes that node's output family at the exact input expression.
It returns `None` iff the proposed extension is not `PrefixSupported`. A
successful `finish_graph` preserves the node prefix and adds exactly the
supplied output wire; its type check uses the output wire's exact constant
facts and it returns `None` iff the complete descriptor is not
`SchemaSupported`. These are characterization laws, not runtime checks that
replace the resolver proof. No caller supplies per-edge proofs or bypasses the
resolver with an arbitrary F* witness. The `Wiring` helpers expose only terms
in the pinned type/value language. Write `WorkSig(m,k) = (A_k,B_k)` for the
unique pinned package selected by node `k`, and `PortCtx(m,x,nodes)` for its
exact dependent telescope. Prefix support has a separate inductive definition
so the public builder does not depend on a finished graph or on resolver
success:

~~~text
PrefixSupported(m,x,[]) := RootSchemaAvailable(m,x)
PrefixSupported(m,x,nodes ++ [k]) :=
  PrefixSupported(m,x,nodes) /\
  FreshKey(k,nodes) /\
  AllWireReferencesAreRootOrPrior(input_wire(k),nodes) /\
  exists (A_k,B_k,e_k,T_k,D_wire,D_eq).
    ExactManifestMember(m,work_ref(k),A_k,B_k) /\
    WireDerives(m,Delta(m,x,nodes),PortCtx(m,x,nodes),input_wire(k),
                e_k,T_k,D_wire) /\
    TypeEqualityDerives(m,Delta(m,x,nodes),PortCtx(m,x,nodes),
                        T_k,A_k,D_eq) /\
    (forall rho:LegalEnv(m,x,nodes).
       Denote(D_wire,rho) = (eval(input_wire(k),rho) : T_k) /\
       Denote(D_eq,rho) : T_k = A_k) /\
    PortCtx(m,x,nodes ++ [k]) =
      PortCtx(m,x,nodes) ++ [k : B_k(e_k)]

SchemaSupported(m,x,g) :=
  StructuralDAG(g) /\
  PrefixSupported(m,x,g.nodes) /\
  AllWireReferencesAreRootOrIn(g.output_wire,g.nodes) /\
  exists (e_o,T_o,D_wire,D_eq).
    WireDerives(m,Delta(m,x,g.nodes) ++
                  ConstantFacts(m,g.output_wire),PortCtx(m,x,g.nodes),
                g.output_wire,e_o,T_o,D_wire) /\
    TypeEqualityDerives(m,Delta(m,x,g.nodes) ++
                           ConstantFacts(m,g.output_wire),
                        PortCtx(m,x,g.nodes),T_o,o(x),D_eq) /\
    forall rho:LegalEnv(m,x,g.nodes).
      Denote(D_wire,rho) = (eval(g.output_wire,rho) : T_o) /\
      Denote(D_eq,rho) : T_o = o(x)
~~~

In the node-input clause, `D_wire` derives expression `e_k` and schema type
`T_k` for the actual input wire; `D_eq` derives `T_k ≡ A_k`. The universal
clauses state the denotation theorems for those derivations at every legal
environment. They do not compare or infer the type of a runtime value.

The definition above is independent from runtime success. For each node,
prior outputs remain symbolic variables ranging over all values in their
registered output schemas/refinements; an external node is checked over its
entire declared result family, which contains every validator-accepted value.
A validator-side restriction is deliberately insufficient to make an edge
well typed. If only a subset is semantically possible and that subset matters
for wiring, represent it in the declared result family, so the validator must
construct the required evidence. The proof is universal over every legal
internal port environment. The graph's exact root
parameter `x` may instantiate its declared boundary schema, and codec-backed
constants may be substituted. No sampled output of a node inside this graph
can discharge an edge equality.

For a root graph, `x` is the committed `RunStarted` input. For a generated
graph, `x` is the exact reconstructed input to its generator and can itself
come from a committed external outcome. The run charge metric comes exactly
from `RunStarted`. This is a boundary parameter, not an internal edge witness:
P4 requires the pure generator's admission law to prove
`SchemaSupported(m,x,generate_graph(x,run_metric,allocation).descriptor)` for
every legal `x`, run metric, and allocation. Thus every possible external
value is covered by the generator theorem. At execution time `GraphCommitted`
provenance binds the bytes to that exact input and metric; recovery re-resolves the committed graph and
does not rerun the generator. A static edge from an unconstrained external
`Sigma n. vector n` to `vector 3` still rejects; one observed reply with
`n=3` cannot make it valid. An explicit generator may construct a different
well-typed child graph for each sigma input only if its universal admission
proof covers all such inputs.

The proof-bearing package is indexed by the canonical manifest and carries
the exact callback to which its law applies:

```fstar
type GeneratorPackage (m:RegistryManifest) (i:Type0) (o:i -> Type0) = {
  ref:GeneratorRef i o;
  admission:x:i -> metric:ChargeMetricIdentity ->
    metric_member:ChargeMetricMember m metric ->
    parent:GenerationAllocation -> Lemma (
      let r = ref.generate_graph x metric parent in
      SchemaSupported(m,x,r.descriptor) /\
      allocation_plan_wf m metric parent.expansion_fuel
        parent.charge_allocation r.descriptor r.child_plan)
}
```

This contract type depends on schema support and graph-local allocation
validity, but not on the completed bundle. The bundle stores one such package
per generator identity; P0 proves exact manifest projection and
restart-stable identity-to-package lookup. Lookup returns the package and its
membership witness together. Builder and execution use that returned package
value, avoiding a second callback value and any need to prove function
extensional equality. Package authors provide the admission proof; a sample
generator result is not evidence for this universal law.

`dag_wf registry x d` is defined to be
`SchemaSupported(registry_manifest(registry),x,d)` for the descriptor syntax
interpreted by `d`; it has no second, weaker definition. Resolver soundness
states that successful resolution
implies the universal node-input and output-boundary judgments and exact
typed witness reconstruction. Resolver completeness states that every
`SchemaSupported` descriptor resolves. Builder soundness/completeness state
that the public builder accepts exactly this language and can construct
every member up to typed graph isomorphism; all builder paths call the same
resolver. P2 states that canonical decode followed by that resolver accepts
exactly the same graph and reconstructs the same typed graph. This is the
declared expressibility boundary: it does not claim completeness for every
arbitrary F* `Type0` family. Graph topology is unrestricted: node count,
dependency shape, fan-out, joins, and occurrence order are not bounded by
the schema calculus.

Typed-constructor syntax may be a builder frontend, and per-Work proof
methods may be registered as schema extensions, but neither creates a second
acceptance path. Meta-F* may help generate or verify static schema packages;
it is not the extracted runtime resolver. The full route comparison,
`SchemaSupported` definition, and arbitrary-`Type0` limitation are recorded
in [the S2-01 decision](../research/S2-execution-2026-10-13/S2-01-graph-resolution.md).

The resolver returns the typing proof with its result, and completeness is a
separate theorem:

```fstar
type ResolvedGraph (bundle:PinnedRegistryBundle)
  (i:Type0) (o:i -> Type0) (x:i) = {
  syntax:GraphDesc i o x;
  model:FiniteTypedDAG i o x;
  syntax_exact:interpret_graph syntax == model;
  typed_witness:dag_wf bundle x model;
  exact_work_resolution:each_node_resolves_to_unique_pinned_work bundle model;
  typed_wiring:wire_derivations_match_exact_work_signatures bundle x model
}
val resolve_graph : bundle:PinnedRegistryBundle -> x:i ->
  g:GraphDesc i o x -> Tot (option
    (resolved:ResolvedGraph bundle i o x{
      resolved.syntax == g}))

val resolve_graph_deterministic : bundle:PinnedRegistryBundle -> x:i ->
  g:GraphDesc i o x -> r1:ResolvedGraph bundle i o x ->
  r2:ResolvedGraph bundle i o x ->
  resolve_graph bundle x g == Some r1 ->
  resolve_graph bundle x g == Some r2 -> Lemma
    (same_erased_typed_graph r1 r2)

val resolve_graph_complete : bundle:PinnedRegistryBundle -> x:i ->
  g:GraphDesc i o x -> graph_wf bundle x g -> Lemma
    (match resolve_graph bundle x g with
     | None -> False
     | Some resolved -> resolved.syntax == g)
```

Soundness is enforced by the result type. `resolve_graph_complete` says every
descriptor in `SchemaSupported` resolves. The resolver is total and
deterministic; uniqueness is of the proof-erased typed graph, since derivation
proof terms themselves need not be compared. The public builder returns
`Some` exactly for extensions whose complete descriptor is in that language.
P1 proves builder soundness and completeness (up to `graph_isomorphic`); P2
proves canonical syntax decode followed by the same resolver reconstructs the
same proof-erased typed graph. The canonical graph codec preserves exact node
list order; topologically reordered descriptors are related only by typed
isomorphism.

`FiniteTypedDAG` is an alias for the first-order `GraphDesc` syntax and is the
mathematical graph model; it is not a second representation. Its `nodes` field
is a finite sequence of first-order node records in topological order, and its
`output_wire` is the sole output mapping. It has no separate
`topological_order` or label/input maps that could disagree with the node
records. The graph codec persists only `DurableWorkRef`, node keys, wire syntax, and canonical
constant bytes. It never persists executable `Work` functions, proof terms,
runtime handles, or duplicate schema references. `interpret_graph` preserves
the exact descriptor sequence and syntax; graph resolution separately obtains
the unique exact semantic `Work` package for each reference from the pinned
manifest.

`dag_wf registry x d` is exactly `SchemaSupported` at the bundle's pinned
manifest and root input `x`; therefore it means: `d.nodes` is finite and
has unique keys; every
reference resolves to exactly one pinned `Work`; each input wire has a
`WireTyping` derivation at the exact graph boundary and schema environment;
each node's input type equals that Work's fixed input carrier for all legal
prior-port environments; all `OutputWire` references name earlier entries in
the node sequence; every constant decodes canonically with its exact pinned
codec; and `output_wire` has type `o x` for all legal internal environments.
The edge relation is exactly prior-output references in input wires. The list
order supplies a strict rank, so acyclicity is immediate from the definition.
`RootWire` has type `x`; `OutputWire k` has the dependent output family of
node `k` at its typed input; `ConstantWire` has its exact codec-decoded type;
`PairWire` forms the corresponding dependent pair; and `FstWire`/`SndWire`
have its first/second projection types. Any nontrivial value transform is a
`Work` node. Multiple inputs use product wiring.

`graph_isomorphic registry g h` is defined by a bijection between vertex keys
that preserves occurrence multiplicity, exact resolved `Work` packages and
their input/output schemas, each typed input wire (including exact constant
codec identities and bytes), induced edges, root input, and typed output
wire. It may rename keys and reorder independent vertices; it cannot drop,
duplicate, merge, or relabel occurrences. Formally, for bijection `f`, each
node in `h` is the `f`-renaming of the corresponding node in `g`; output wires
agree under the same renaming; and transporting any `dag_wf registry x g`
witness along `f` yields `dag_wf registry h`. `RootWire` is fixed by the
renaming. Canonical graph encoding is exact syntax equality, not quotienting
by this isomorphism relation.

`PortContext` is a dependent telescope of the root and prior node outputs;
`Wiring` is a first-order typed term over that telescope. `add_node` creates
exactly one fresh occurrence, preserves every previous vertex and wire, and
returns a typed `PortRef` for its new output. Its dependency edges are exactly
the ports referenced by its input wiring. `finish_graph` preserves the node
table and records exactly its supplied output wiring. `start_graph` denotes
the empty vertex set with the root input port. The telescope's order is a
topological construction order, not a sequential execution order; the
evaluator may schedule any independent ready nodes concurrently.

The F* signatures above are schematic: the concrete encoding of dependent
contexts and the universe levels of heterogeneous node signatures remain
open. Their meaning is fixed by the graph model and construction laws above,
and by these additional contracts:

- `graph_wf registry x g` means `dag_wf registry x (interpret_graph g)`.
  Graphs are finite by
  construction. The graph API has no node-count, depth, or encoded
  size bounds; those are deployment resource policies, not extra graph
  semantics or premises for DAG expressibility.
- `GenerationAllocation` is the per-occurrence value for the two execution
  ledgers: `expansion_fuel` comes from the fuel ledger, `charge_allocation`
  from the charge ledger. The one charge metric is supplied separately from
  the committed `RunBudget`, so it is not duplicated in every plan entry. A
  `GraphAllocationPlan` has one entry per graph
  node, in the same order as `GraphDesc.nodes`; its key list is exactly the
  node-key list. Thus there are no duplicate, omitted, or extra entries.
  `lift_graph_plan(p, plan)` replaces each local key `k` by
  `NodeOccurrence(child_occurrence(p), k)` and preserves order and allocation
  values. `lift_root_plan(run, plan)` analogously uses `RootGraph(run)`.
  Both lifts are deterministic and injective because graph-local keys are
  unique. An occurrence plan is derived state, never a separately supplied
  plan representation. A local node receives `(expansion_fuel=0,
  charge_allocation=0)`; an external node receives
  `(0,maximum_charge)` from its exact resolved `OpRef`; each nested generator
  receives positive expansion fuel. These charge amounts all use the one
  metric supplied by the run.
  For parent allowance `(b,c)`, if nested generators are present, their fuel
  sum is strictly less than `b`; if none is present, their fuel sum is zero.
  Direct external maxima plus nested-generator charge pools sum to at most
  `c`.
  `allocation_plan_wf` states exact key/order alignment, node-kind
  allocations, operation-metric agreement with the run, and these per-graph
  bounds. This is local plan validity;
  global ledger conservation and settlement are P8. In the root plan, root
  generators may receive zero fuel; all assigned root fuel and charge fit
  `RunBudget`, and unused amounts remain free. `root_allocation_plan_wf`
  states these root-specific bounds. `RunStarted` and `GraphCommitted` persist
  the graph-local plan returned by the corresponding constructor/generator.
  Replay derives occurrence-keyed ledgers by the deterministic lifts above.
  No occurrence IDs are duplicated in the event. Recovery reconstructs the
  same allocation. A generator receives exactly its ledger allocation, never
  a larger caller-selected bound.
  Formally, `allocation_plan_wf(m,metric,b,c,g,p)` includes
  `ChargeMetricMember(m,metric)` and
  `map(key,p) = map(key,g.nodes)` and pointwise the node-kind rules above;
  every resolved external operation in `g` has `charge_metric = metric`;
  with `F = sum { p[k].expansion_fuel | g[k] is GenerateWork }` and
  `C = sum { maximum_charge(k) | g[k] is ExternalWork } +
       sum { p[k].charge_allocation | g[k] is GenerateWork }`, it requires
  `F = 0` or `F < b`, and `C <= c`. Every term is keyed by the unique aligned
  local `NodeKey`. `root_allocation_plan_wf(m,budget,g,p)` requires
  `ChargeMetricMember(m,budget.charge_metric)`, uses the same key alignment,
  and requires every resolved operation to use `budget.charge_metric`,
  and applies the local/external node-kind rules; root generators may have zero
  fuel, and their total fuel plus external maxima and generator charge pools
  satisfy `sum(root_fuel) <= budget.total_expansion_fuel` and
  `sum(root_external_maxima) + sum(root_generator_charges) <=
  budget.total_charge`.
- The graph codec is indexed by the exact input and output family. Its
  syntactic decoder reconstructs the same descriptor on round trip, and every
  accepted byte string re-encodes byte-for-byte identically. A pinned
  `resolve_graph` operation then constructs the `graph_wf` witness before the
  descriptor can be used. This operation resolves every work and constant
  against the exact manifest and rebuilds the dependent port telescope,
  preserving input/output indices, edges, and typing evidence; a key match or
  caller-supplied witness is insufficient. Root graphs and generated graphs
  use this same decode-and-resolve path. An unchecked cast from bytes is
  forbidden. `PairWire` is a structural constructor and stores only its child
  syntax. The resolver derives its dependent pair type from the exact typed
  children; no pair-family codec lookup or closure serialization is needed.
  The consuming Work's input codec interprets/materializes a pair input. A
  graph output pair is reassembled from its durable sources. Plain constants resolve a `Codec a`;
  input-indexed constants
  resolve an `IndexedCodec i A` and decode at this exact root input `x`,
  yielding `A x`. Both forms use the same `ConstantWire` syntax and are
  distinguished by the pinned codec entry. `GraphCodecIdentity` binds
  implementation, schema, and canonicalization version. `GeneratorIdentity`
  binds the generator implementation, input codec, output family, and exact
  graph codec identity.
- Generation is pure, total, pinned F* code of the exact committed input,
  run charge metric, and immutable `GenerationAllocation`. Any value that can affect graph
  choice must be in those committed arguments. It cannot read a volatile
  runner cursor, process handle, or changing journal projection.

The construction API itself has three laws: `start_graph` denotes exactly the
root-only prefix; successful `add_node` extends the interpretation by exactly
one fresh vertex with the supplied `Work` and input wiring while preserving
all earlier vertices and wires; successful `finish_graph` changes only the
output wiring. `add_node` and `finish_graph` return `None` exactly when the
proposed extension lacks a derivation in the shared schema calculus; they
never accept caller-supplied edge proofs as a bypass. The **builder
completeness theorem** states that every `SchemaSupported` `FiniteTypedDAG`
can be enumerated in its vertex sequence by these operations, constructing
constant leaves with the codec wiring forms and then finishing with its output
wire. The builder assigns fresh keys; a key bijection transports the input DAG
to the builder's keys. The result is isomorphic to the input DAG. This makes
completeness a theorem of the offered primitive API, not an existence claim
about a hidden constructor. Support is exactly the manifest calculus, not
arbitrary F* `Type0` equality.

The decisive **graph expressibility theorem** is required:

> For every finite acyclic graph whose vertices are pinned `Work` references
> with manifest schema entries, whose node inputs and output boundary have
> derivations in `SchemaSupported` from root/prior-output or codec-backed
> constant wires, and whose root/output interface is `(x, o x)`, there exists
> a `GraphDesc i o x` whose interpretation is isomorphic to that graph,
> preserving every vertex, edge, occurrence, input/output mapping, and
> dependency. The only allowed difference is ordering of independent nodes.
> Expressibility is independent of a run's resource allocation; allocation
> admission is a separate execution theorem.

The definition of `graph_wf` makes descriptor soundness a direct projection to
the independent `FiniteTypedDAG` semantics. The substantive P1 obligations are
`finish_graph_sound` and `graph_complete`; completeness is proved through the
builder completeness theorem. Together these make the descriptor a general
typed DAG language, not a workflow-specific expansion convention. The current
F* `wire_label_isomorphic` helper in `WorkflowV2.Graph` compares wire syntax
and durable labels only; it
does not yet establish the typed isomorphism specified here, which remains an
explicit P1 hole.

“Arbitrary graph” therefore means arbitrary finite topology and fan-out over
the pinned node registry for signatures and dependent families represented by
the manifest schema calculus. It does not mean arbitrary F* `Type0` equality,
serializing closures, inventing executable code at runtime, or creating
values without codecs. Those additions require a pinned schema, `CodeRef`, or
adapter. Builder and decoder support the same schema language; unsupported
type expressions are explicitly rejected.

Every graph, whether authored initially or returned by `generate`, is run by
the same evaluator. Committing a generated graph substitutes its vertices
behind the generator occurrence's typed input/output boundary; its output
wire supplies that occurrence's eventual result. This substitution preserves
the surrounding DAG and its topological dependencies. The new vertices become
ordinary occurrences with ordinary `NodeCompleted`, `CallIntent`, and
`CallOutcome` transitions; the exact subgraph is fixed by `GraphCommitted`.
Every completion and graph commit goes to the same journal. Generated nodes
receive no weaker storage, scheduling, adapter, or recovery guarantee. A
`graph_expansion_preserves_dag` theorem must prove this typed substitution for
each committed finite child DAG, including nested generation under the fuel
bound.

## 3. Artifacts and host resource interpretation

The kernel does not make `Blob`, `BlobTree`, paths, sockets, process handles,
database cursors, or model contexts primitive workflow values. These are
domain types whose pinned codec/schema and adapter or resource-store package
give them an interpretation. A typed `ArtifactRef a` denotes a logical
resource of type `a`; its representation stays opaque. An existential
`PackedArtifactRef` lets an event inventory refs of heterogeneous resource
types, while its manifest entry resolves the exact type, schema, canonical
reference codec, store identity, and interpretation. This is not a new Work
primitive: values containing such refs pass through the ordinary typed graph,
codecs, and node inputs/outputs.

Every resource-bearing value schema has a total projection
`refs_of : a -> list PackedArtifactRef`. Its exactness law states that each
resource reference contained in the typed value occurs exactly once in
`refs_of`, and no unrelated reference occurs there. Structured schema
constructors compose this projection; atomic schemas with no resource
references return the empty list. P0 pins the projection and its laws with the
relevant codec/schema identity. `NodeCompleted.artifacts` and
`CallOutcome.artifacts` must equal `refs_of` of their decoded output; the event
list is a canonical index, not a second authority. Root inputs and graph
constants use the same projection through their pinned codecs and graph
resolver. Uninterpreted evidence and resume bytes cannot introduce
workflow-visible resource references.

`PackedArtifactRef` has one canonical tagged encoding: the pinned artifact
type identity selects its reference codec, and that codec encodes the typed
reference. Decode resolves the same existential package and reference;
unknown type IDs, codec mismatches, and noncanonical bytes are rejected. No
cast from an untyped reference label to `ArtifactRef a` is permitted.

The projection contract is stated independently of its representation:

~~~text
RefOccurs(value, ref) : prop
ResourceProjection(a) = {
  refs_of : a -> Tot (list PackedArtifactRef);
  exact : value:a ->
    NoDup(refs_of(value)) /\
    (forall ref. Mem(ref, refs_of(value)) <==> RefOccurs(value, ref))
}
~~~

For an indexed output family, `refs_of` and `exact` are quantified at every
index `x` and value `y:o x`.

The abstract resource package supplies a contract of this form; this is a
proof interface, not a selected representation:

~~~text
type ResourceHandle(a)
ArtifactPackage(a) = {
  artifact_type_identity; store_identity;
  reference_codec : Codec (ArtifactRef a);
  publish_or_validate : ResourceHandle a -> ArtifactRef a -> prop;
  resolve_after_restart : ArtifactRef a -> ResourceHandle a -> prop;
  denotes : ArtifactRef a -> ResourceHandle a -> prop;
  same_logical_resource : ResourceHandle a -> ResourceHandle a -> prop
}
~~~

`ResourceHandle(a)` is an abstract host interpretation selected by the
package. Its `denotes(ref,handle)` and `same_logical_resource` laws state that
all handles recovered for one immutable ref/version denote the same logical
typed object, even if the host creates a fresh process-local handle.
Formally, `resolve_after_restart(ref,handle)` implies `denotes(ref,handle)`,
and any two handles denoting the same `ref` satisfy
`same_logical_resource`. That relation must preserve every observation and
operation admitted by the pinned resource semantics; P13 proves the concrete
host object really refines that relation. It cannot be chosen as an
unconstrained relation that makes distinct contents equivalent.
If a workflow action
must resolve a resource, P14 additionally assumes that this store service is
available and fairly completes the requested resolution; the safety theorem
does not assume service progress.

The package laws require canonical reference round-trip; a stable object and
version identity; no overwrite, deletion, or identity reuse while a reference
is reachable; and idempotent publication or rejection of conflicting reuse.
Before the journal append linearization point, every newly referenced backing
object is complete and durable, and an existing reference is validated under
its pinned package. After any supported restart, resolving that ref returns a
handle denoting the same typed logical object and immutable version. “Same”
means the package's `same_logical_resource` relation, not pointer equality or
the same process-local handle. Concurrent resolution after commit sees the
complete object, never a partial file or tree. A crash after publication but
before the event commit may leave an unreachable orphan; it cannot make that
object visible in replay.

For a typed event `e`, let `ResourceRefs(C,e)` be the exact references
enumerated by its typed codecs/schema projections. A `P9PublicationWitness`
for `(C,e,r)` proves that `r` is typed by its pinned package, its complete
backing version was durable before the event's append commit, and every later
supported resolution denotes the same logical resource version. A reference
already present in the root input must have a valid availability witness
before `RunStarted`; repeated references inherit the same immutable-object
witness. These witnesses are ghost facts in the authorized append history,
not journal payload.

Replay checks canonical reference syntax/type resolution and exact event
inventory only; it never calls the external store. P15 exposes a resource to
dependent work only after the event commits. P10 continues to prove
journal-prefix durability independently of resource-store availability. P9
extends P16 only when a workflow claims backing-object identity in addition
to logical typed graph recovery.

Files, BlobTrees, and object-store snapshots fit as immutable versioned
resources. Mutable database or network state must name a version/snapshot or
provide a durable reopen/continuation relation with the same logical-state
law. A socket, process handle, or cursor is not itself promised to survive a
restart as the same host handle. A file-analysis adapter can materialize a
typed source tree, invoke a CLI, and return typed report data plus BlobTree
references; network and database adapters can use the same reference contract
for their domain-specific requests and state.

## 4. Canonical journal and abstract execution

### 4.1 Canonical state

Let `J` be the ordered journal and fix an immutable replay context `C` containing
the pinned registry resolver and journal codec. Write `replay_C(J)` for
`replay(J)` under this fixed context; this shorthand preserves the usual
statement `S = replay(J)`. The only durable workflow state is the event list
`J`. Replay context and service objects are fixed contract inputs, not mutable
workflow state. A checkpoint may cache a projection only if it is checked
against `J` and gives exactly `replay_C(J)`.

```fstar
type EventNodeRef = {
  graph_path:list NodeKey; (* [] is root; each key names a parent generator *)
  node_key:NodeKey
}
type Event =
  | RunStarted : {
      run_identity:RunIdentity;
      registry_identity:RegistryIdentity;
      root_entrypoint:RootEntryIdentity;
      root_input:Bytes;
      root_graph:Bytes;
      initial_budget:RunBudget;
      root_plan:GraphAllocationPlan
    } -> Event
  | GraphCommitted : {
      generator:EventNodeRef;
      graph_bytes:Bytes;
      child_plan:GraphAllocationPlan
    } -> Event
  | NodeCompleted : {
      node:EventNodeRef;
      output_bytes:Bytes;
      artifacts:list PackedArtifactRef
    } -> Event
  | CallIntent : {
      node:EventNodeRef;
      adapter_resume_data:Bytes
    } -> Event
  | CallOutcome : {
      node:EventNodeRef;
      output_bytes:Bytes;
      evidence:Bytes;
      charge:nat;
      artifacts:list PackedArtifactRef
    } -> Event
type JournalError
type WorkAction
type Terminal
type Journal = list Event
type State
type ReplayContext
type JournalCodec = {
  identity:JournalCodecIdentity;
  encode_event:Event -> Tot Bytes;
  decode_event:Bytes -> Tot (result Event JournalError);
  encode_journal:Journal -> Tot Bytes;
  decode_journal:Bytes -> Tot (result Journal JournalError);
  event_roundtrip:e:Event -> Lemma
    (decode_event (encode_event e) == Ok e);
  event_canonical:b:Bytes -> e:Event -> Lemma
    (decode_event b == Ok e ==> encode_event e == b);
  journal_roundtrip:j:Journal -> Lemma
    (decode_journal (encode_journal j) == Ok j);
  journal_canonical:b:Bytes -> j:Journal -> Lemma
    (decode_journal b == Ok j ==> encode_journal j == b)
}
val journal_codec : ReplayContext -> Tot JournalCodec
type BudgetLedger = {
  metric_identity:ChargeMetricIdentity;
  total:nat;
  free:nat;
  allocated:nat;
  reserved:nat;
  spent:nat
}
type FuelLedger = {
  total:nat;
  free:nat;
  allocated:nat;
  consumed:nat
}
type ChargeAllocations = {
  allocated_by_node:NodeOccurrence -> option nat;
  reserved_by_node:NodeOccurrence -> option nat
}
type FuelAllocations = NodeOccurrence -> option nat
val replay : ReplayContext -> Journal -> Tot (result State JournalError)
val initial_state : ReplayContext -> Tot State
val enabled_frontier : State -> Tot (list WorkAction)
val terminal_output : State -> Tot (option Terminal)
val action_enabled : State -> WorkAction -> Tot prop
val apply : ReplayContext -> State -> Event -> Tot (result State JournalError)
val budget_ledger : State -> Tot BudgetLedger
val fuel_ledger : State -> Tot FuelLedger
val charge_allocations : State -> Tot ChargeAllocations
val fuel_allocations : State -> Tot FuelAllocations
val state_wf : State -> Tot prop
val event_guard : ReplayContext -> State -> Event -> Tot prop

type StoreModel
type AppendResult = Appended | Stale
type AuthorizedEvent (context:ReplayContext) (state:State) (event:Event) : prop
type AppendPermit (context:ReplayContext) (prefix:Journal) (event:Event) : prop =
  exists state:State.
    replay context prefix == Ok state /\ state_wf state /\
    event_guard context state event /\
    AuthorizedEvent context state event
val load_bytes : StoreModel -> Tot Bytes
val load_store : context:ReplayContext -> StoreModel -> Tot Journal
val load_bytes_decode : context:ReplayContext -> store:StoreModel -> Lemma
  ((journal_codec context).decode_journal (load_bytes store)
    == Ok (load_store context store))
val append_authorized : context:ReplayContext -> store:StoreModel ->
  prefix:Journal -> event:Event -> AppendPermit context prefix event ->
  Tot (StoreModel & AppendResult)
val recover : ReplayContext -> StoreModel -> Tot (result State JournalError)
```

`initial_state` is the unique unstarted state with no graphs, outputs, calls,
or allocations. `replay` is a left fold beginning there and applying each
event in order; it stops at the first rejection. `recover` is its pure wrapper
around the abstract store load.

`load_bytes` is the physical journal value exposed by a recovery load.
`load_store` is only its decoded projection, constrained by
`load_bytes_decode`; it is not another source of truth. By
`JournalCodec.journal_canonical`, every modeled loaded snapshot also satisfies
`encode_journal(load_store(context,store)) = load_bytes(store)`.

`append_authorized` is the only abstract write operation. Its postcondition is
the following exact transition relation for returned `(store',result)`:

```text
AppendTransition(context,store,prefix,event,store',result) :=
  (result = Appended /\ load_store(context,store) = prefix
      /\ load_bytes(store') = encode_journal(prefix ++ [event]))
  \/ (result = Stale /\ load_bytes(store') = load_bytes(store)
      /\ load_store(context,store) != prefix)
```

Thus a matching expected prefix commits exactly one event, while a stale
prefix changes nothing. There is no “invalid event” result: the
`AppendPermit` supplies current replay, `StateWF`, `EventGuard`, and semantic
authorization before the serial journaler is called. The expected head is
derived as `length(prefix)`; no separate mutable head is authoritative. The
raw storage write primitive is private to this operation, and a concrete
refinement proves there is no other write path. A process cut during an append
is covered by §4.4. Liveness of an append that owns the current head is a
journaler service obligation discharged with P10/P11, not a property of pure
`append_authorized`.

On `Appended`, the logical journal is exactly `J ++ [e]`; on `Stale`, it is
exactly the pre-call journal. A stale request's authorization is indexed by
the old replayed state and cannot be retargeted by changing its head number.
Reload, replay, input reconstruction, and event authorization must all be
repeated.

The event list position is its sequence number, starting at zero; no event
stores a separate sequence field. `RunStarted` stores the `RunIdentity` once.
Later event occurrence references are relative to that run: a graph path is
the sequence of parent generator keys from the root, followed by the local
node key. Replay resolves that reference to a full `NodeOccurrence` using the
run identity. Thus `(run_identity, sequence_number)` is derived event
identity, not a second event field. A `JournalCodecIdentity` selects one
immutable event/journal format as a system input and must remain stable across
restart; schema and format version are not repeated in each event. Run
identity is unique among live and recoverable runs sharing an adapter key
namespace. This is a premise supplied by the run-identity allocator/caller:
per-journal compare-and-append cannot establish uniqueness across separate
journals. P13 must show that concrete run creation enforces this premise for
the adapter key namespace. “Canonical journal” means one byte encoding for
each logical event list and one deterministic replay under the fixed replay
context; distinct completion orders may produce distinct valid prefixes.

The `EventNodeRef` representation in the type sketch is `(graph_path,node_key)`.
The minimal event families are:

- `RunStarted`: run identity, pinned registry identity, root-entrypoint identity, canonical
  root input bytes, exact canonical root graph bytes, initial generation/
  charge budget, and the root graph's allocation plan. The entrypoint selects
  the exact input codec, graph codec, result family, and constructor; those
  codec identities are not duplicated in the event. Authorization proves the
  bytes and plan are the entrypoint's exact `start(input,budget)` result.
  Node and codec identities are otherwise derived from the graph references
  and pinned registry.
- `GraphCommitted`: run-relative generator occurrence key, exact canonical child graph
  bytes, and the exact graph-local child plan returned with that graph. The
  containing parent graph is derived from the generator occurrence. Replay
  derives child `NodeOccurrence`s using `lift_graph_plan`; the event carries
  no duplicate occurrence IDs.
  Append authorization resolves the
  `GeneratorRef` and graph codec from the committed parent graph, reconstructs
  the typed generator input from predecessor outputs, and proves that the
  bytes encode the exact well-formed graph returned for that input and the
  ledger-derived allocation. Replay does not rerun the generator: it checks
  append provenance, allocation validity against the replayed ledger, then
  canonically decodes and resolves the graph bytes through the pinned
  manifest. The event does not repeat generator identity, graph codec
  identity, or input bytes; replay derives each from the parent graph and
  current committed state.
- `NodeCompleted`: run-relative local-node occurrence, validated typed output bytes, and
  published artifact references. Replay reconstructs the exact `Work` and its
  typed input from the committed graph and predecessor outputs, then decodes
  the output with that work's indexed codec at that input. Work identity and
  input are not repeated in the event. `GenerateWork` has no `NodeCompleted`
  event; its result is obtained from the committed child graph's output wire.
- `CallIntent`: run-relative adapter-node occurrence (the stable call key is
  derived with the run identity) and
  adapter resume data. Replay derives the operation and typed input from the
  committed graph and predecessor outputs; the canonical request is derived
  using that operation's request codec. The charge reservation is derived
  from the pinned `OpRef.maximum_charge` and the allocation assigned to that
  occurrence, so it is not stored a second time. It is accepted only once for
  a ready adapter occurrence, and the same intent, request, and reconstructed
  input are used on every recovery.
- `CallOutcome`: run-relative adapter-node occurrence, canonical typed output bytes, correlated evidence, charge
  settlement, and artifact references. Replay selects the indexed output
  codec from the operation resolved at the intent's occurrence and input.
  This event completes the adapter node; no second completion event is needed.

A root `GraphOccurrence` is `RootGraph(run_identity)`. The child graph
introduced by a `GraphCommitted` event for generator occurrence `p` is
`ChildGraph(p.graph,p.key)`. It becomes present only after that event is
committed; its identity is derived from the unique parent generator occurrence,
not from a second event field or a commit sequence that would make plan
construction circular. A `NodeOccurrence` is `(GraphOccurrence, NodeKey)`.
Unique keys within each graph and one absorbing graph commit per generator
make these paths injective. Resolving an `EventNodeRef` yields this exact
occurrence. `CallKey` is the full adapter `NodeOccurrence`, so it remains
stable across every resume without repeating the run identity in event bodies.

`JournalCodec` proves two independent canonicality layers. For every event
`e` and bytes `b`, `decode_event(encode_event(e)) = Ok(e)` and
`decode_event(b) = Ok(e) ==> encode_event(e) = b`. For every event list `J`
and bytes `b`, `decode_journal(encode_journal(J)) = Ok(J)` and
`decode_journal(b) = Ok(J) ==> encode_journal(J) = b`. Journal framing must
preserve event order and constructor tags without alternate lengths, trailing
bytes, or ambiguous field encodings. Nested graph/value bytes are checked using
the exact indexed codec selected from replay state; packed artifact refs use
their tagged artifact identity and exact pinned reference codec. Canonical event bytes and
canonical journal framing are separate obligations; neither implies event
authorization. `decode_journal` is a syntax codec; `replay` separately rejects
structurally illegal event sequences. P10 later proves stored bytes decode to
exactly the loaded prefix and remain canonical at every crash cut.

The replay machine has the following exhaustive guard/update rules. A guard
is defined from the state projections and pinned contracts below, not by the
conclusion that it preserves `state_wf`; this makes the P3 preservation proof
non-circular. `apply` is a pure deterministic function: its result is the
listed update when the guard holds, and `Error` with no partial update when it
does not. Every projection not named by an update remains unchanged.

| Event | Structural guard checked by replay | Exact state update | Semantic origin checked before append |
|---|---|---|---|
| `RunStarted` | State is unstarted; run and registry identities resolve; root input and graph decode canonically at entrypoint-selected codecs; graph resolves to `SchemaSupported`; all embedded resource refs resolve to pinned ref types; root plan aligns, uses `initial_budget.charge_metric`, and fits `RunBudget`. | Set run/root context and root graph; derive `RootGraph(run)` allocations via `lift_root_plan`; initialize charge and fuel totals, free remainder, and zero reserved/spent/consumed amounts. | Input, graph bytes, and plan equal the exact pinned `RootEntry.start(input,budget)` result; each referenced resource has a P9 availability witness before commit. |
| `GraphCommitted` | Named occurrence resolves to a ready unexpanded `GenerateWork`; graph bytes resolve canonically and satisfy `graph_wf` at its reconstructed input; graph resources resolve to pinned ref types; local plan aligns and satisfies `allocation_plan_wf` for the run metric and replayed allocation; child path is fresh. | Record the one absorbing expansion; splice in the child graph; derive child occurrence allocations by `lift_graph_plan`; remove parent's charge/fuel allocations, assign child pools, return unused charge to free, and consume fuel not reallocated. | Graph bytes and local plan equal the exact `GeneratorRef.generate_graph(input,run_metric,allocation)` result, including operation-metric agreement; each newly referenced resource has a P9 publication witness before commit. |
| `NodeCompleted` | Named occurrence is a ready incomplete `LocalWork`; output bytes decode canonically with its indexed output codec at the reconstructed input; artifact references are well-formed and exactly the codec/schema projection of that output. | Record one typed local output and its artifact-reference inventory. | Output bytes encode exactly `CodeRef.run(input)`; P9 publication evidence is required for every newly published resource. |
| `CallIntent` | Named occurrence is a ready external work with neither intent nor outcome; resume bytes have canonical event encoding; operation metric equals the run metric; reserved maximum is available in the allocation ledger. | Record the sole intent; move exactly the operation maximum from that occurrence's allocated charge to reserved charge. | Intent names the derived request/key and is authorized before any external effect; P7 pins resume-token interpretation and safe resumption. |
| `CallOutcome` | Named occurrence has exactly one pending intent and no outcome; output bytes decode canonically with the exact-input indexed output codec; charge is within its reserved maximum in the run metric; evidence and artifact fields are well-formed, and artifact references equal the output codec/schema projection. | Record the one typed outcome as the node output; remove its reservation, add actual charge to spent, and return the unused maximum to free. | Exact event fields equal `persist_x(T)` for the bound P7 receipt; evidence, charge, and effect correspond to that logical call; every new resource reference has P9 publication evidence. |

For root plan charge allocations `A_c` and root generator fuels `A_f`,
`RunStarted` first checks `A_c <= total_charge` and
`A_f <= total_expansion_fuel`, then sets
`allocated=A_c`, `free=total_charge-A_c`,
`reserved=spent=0`, `fuel_allocated=A_f`, `fuel_free=total_expansion_fuel-A_f`,
and `fuel_consumed=0`. For a graph commit with parent pools `(b,c)`, let `F`
be the child-generator fuel sum and `C` the direct external maxima plus child
generator charge pools. Before subtraction, guards establish `C <= c`,
`F <= b`, and `q <= maximum_charge`. `GraphCommitted` replaces the parent's
map entries by the lifted child plan, returns `c-C` to charge `free`, and adds
`b-F` to fuel `consumed`. `CallIntent` transfers exactly `maximum_charge`
from allocated to reserved. `CallOutcome` transfers the reserved maximum into
actual `charge` spent plus the unused difference returned to `free`. All
charge values have the one metric pinned by `RunStarted` and resolved
operation identities; fuel is not a charge unit.

The scalar ledger is a static-allocation policy. Root allocations are fixed
by `RunStarted`; a generator may subdivide only its own committed pool.
Unused charge returned to `free` and root fuel left unassigned are not
reallocated later. Every action in a valid admitted plan therefore fits its
precommitted allowance; `free` is accounting remainder, not a dynamic grant
pool. This P8 contract meters external charge and graph-expansion fuel only;
it makes no claim about CPU time, memory, retries, or other unmodeled costs.

Ledger fields are projections, not independent sources of truth. `allocated`
and `reserved` are sums of their canonical occurrence maps; `spent` and
`consumed` are derived from committed settlements/expansions; `free` is the
unique remainder from the pinned total and those projections. The fuel map
and total obey the analogous rule. Replayed state or any cached ledger must
equal these projections exactly. P8 proves the aggregate equations, local
transition equations, plan-fit and one-time settlement from the deterministic
updates; P3/P4 establish the replay/allocation induction, P7 establishes that
an authorized receipt's charge is truthful and belongs to its key, and P15
establishes the once-only serialized transition under concurrent completion.
Replay does not use P8 as a precondition. An invalid constructor, duplicate
completion, intent, outcome, or expansion, unknown occurrence, premature
dependent event, or any event after terminality is rejected.

Replay validates the canonical syntax and pinned type of every packed
reference but does not call the artifact store. The P9 publication witness is
part of semantic append authorization and `SemWF`; it proves resource-store
facts that the deterministic replay machine cannot observe.

There is no `GenerationPrepared`: unlike an adapter effect, graph generation
is a pure total function of its committed input, pinned generator identity,
and ledger-derived allocation, so it can be recomputed before
`GraphCommitted`. Any other choice-relevant value must be part of the
committed input.
There is no `Failure` event or node state;
expected domain failure is an output value. A completed root output is the
terminal run state, so a separate `RunTerminal` event is unnecessary.

`EventGuard(C,S,e)` is the structural transition relation specified by the
table above. It is defined from event constructors, graph/node status,
readiness, pinned codecs, and ledgers; it is not defined as “the transition
that preserves WF.” `apply(C,S,e)` is deterministic, returns exactly the
listed state update when `EventGuard` holds, and otherwise returns an error
without changing any state. `replay_C([]) = Ok(initial_state(C))`; for each
next event it applies this rule to the prior replay result and stops at the
first error. Thus replay is a deterministic fold, not a source of semantic
proofs. `decode_journal` proves only syntax/canonical bytes. Replay separately
checks ordered structural legality and typed payload resolution.

`StateWF(S)` abbreviates the declared `state_wf(S)` predicate. It is
independently stated: either `S` is the unique
unstarted state, or it has exactly one root run and a finite, uniquely keyed
set of graph occurrences; each child graph has exactly one preceding parent
commit; every node has one legal status; each visible value decodes at its
exact reconstructed input; every intent/outcome is keyed to the exact
external occurrence; and allocation maps are finite, nonnegative, and aligned
with the committed plans. It does not assert that a value equals a computation
that replay does not execute. P3 proves `state_wf(initial_state(C))` and, for
every constructor, `state_wf(S) /\ event_guard(C,S,e) /\
apply(C,S,e) = Ok(S') ==> state_wf(S')`. It then proves replay induction,
determinism, rejection of malformed prefixes, and terminal absorption.
P8 proves the aggregate charge/fuel conservation equations and one-time
settlement from these deterministic local ledger updates.

Define `AuthorizedEvent(C,S,e)` separately from `EventGuard`. For `RunStarted`
it proves that canonical input, graph, and plan are exactly the pinned root
entrypoint result. For `GraphCommitted` it proves exact equality to the pinned
generator result at the reconstructed input, run metric, and allocation. For `NodeCompleted`
it proves the encoded value is exactly the pinned local function result. For
`CallIntent` it proves the ready occurrence, derived request/key, and pinned
resume-data contract before dispatch. For `CallOutcome` it includes
`P7ReceiptWitness` for the exact key, request binding, terminal tuple, and
reconstructed input, and proves that the pinned validator accepts the reply
at that input. Physical artifact publication is additionally covered by P9
when claimed: each reference in `ResourceRefs(C,e)` has an availability or
publication witness for the exact typed version, and its inventory equals
the codec/schema projection. For `RunStarted` these resources are available
before workflow commit; for later events any newly published backing object
is durable before append linearization.
`apply` and `StateWF` do not pretend to establish these provenance facts.

`append_authorized(C,J,e)` requires `replay_C(J) = Ok(S)`, `state_wf(S)`,
`event_guard(C,S,e)`, and `AuthorizedEvent(C,S,e)`. It submits exactly `e` at
head `length(J)` to the serial journaler. Success extends the journal to
`J ++ [e]`; rejection leaves `J` unchanged. If the expected head is stale,
the proof is indexed by the old `S` and cannot be reused: reload, replay,
reconstruct inputs, and reauthorize. The concrete refinement proves the raw
store write path is private to this coordinator. Replay-valid but unauthorized
events (for example, canonical bytes for a wrong local result) are rejected by
the coordinator even though structural `apply` alone could decode them.

Let `T` be the linearized event history and `AuthorizedTrace(C,T)` assert that
it begins with a `RunStarted` event authorized at the unstarted state, and
that each later event was appended at its exact current head with a matching
`AuthorizedEvent` proof. A failed/stale append adds no history element. For
each prefix `J` of `T`, define
`SemWF(C,T,J,S) := J is a prefix of T /\ S = replay_C(J) /\ StateWF(S) /\
every event in J retains its append authorization witness`. `SemWF` is ghost
history; its witnesses are not journal bytes. When P9 is supplied, extend it
with `ArtifactSemWF(C,T,J,S)`, retaining the typed publication/availability
witness for every resource reference reachable from `S`. P15 proves each authorized
append extends this invariant. P10's cut theorem selects a prefix of the same
authorized history, so P16 transports the corresponding provenance witnesses
without rerunning code or effects. Arbitrary valid-looking bytes written
outside the protocol are outside the store contract. `StateWF` alone never
implies `SemWF`.

`Terminal(S)` holds exactly when the run has started, every generator
occurrence has committed its child graph, every local occurrence has one
`NodeCompleted`, every external occurrence has one `CallOutcome`, and the
root output wire evaluates to `t` from committed typed values. This includes
empty or constant-output graphs when their root wire is defined. The result
is derived, so no `RunTerminal` event is needed. `terminal_output(S) = Some t`
iff this condition holds; it implies `enabled_frontier(S) = []`, and `apply`
rejects every event. There is no `Failure` event or node state; expected
domain failure is an output value. State contains only projections of
committed inputs, identities, graph expansions, outputs, calls, artifact
references, and ledgers; it contains no stack, closure, queue, socket,
process, or other volatile handle.

### 4.2 Abstract executor and service contracts

The abstract workflow receives three service values with proofs of their
contracts. They are inputs to the system, not trusted implementation details:

1. **Serial journaler.** It loads the latest committed canonical prefix and
   accepts at most one append at a time. Each append is linearizable against
   an expected sequence head; it either commits one authorized event at that
   head or rejects without changing the journal. It never accepts concurrent
   writes. If multiple controllers are ever allowed for one run, their writes
   must share the same linearizable fencing mechanism; a process-local mutex
   alone is insufficient.
2. **Local/generator executor.** It evaluates pinned total pure `LocalWork`
   and `GenerateWork`. It may run several distinct ready occurrences
   concurrently, using each occurrence's exact reconstructed input and
   committed allocation. A return satisfies the selected `CodeRef.run` or
   `GeneratorRef.generate_graph` contract. It cannot commit state or expose a
   result to dependents.
3. **External adapter.** Each submission accepts one committed `CallIntent`.
   The workflow may submit several distinct intents while earlier calls
   remain in flight. The adapter returns outcomes correlated by `CallKey`
   and may complete them in any order. It satisfies the
   effect-safe resumption contract in §2.1. The workflow consumes and
   journals each accepted result separately; one slow call does not hold the
   journaler or block an unrelated completed outcome.

The abstract controller owns volatile runtime state: unique live claims for
local/generator occurrences, adapter in-flight keys, and at most one current
journal append. This state is discarded on process exit and is never a second
durable authority. A claim binds one occurrence to its exact pinned identity,
typed input, and committed allocation. A live occurrence has at most one
claim. A result is rechecked against replayed state before commit: the
occurrence must still be pending, and its identity, reconstructed input, and
allocation must still match. A stale claim cannot be made valid by changing
only its expected journal head; discard it or reauthorize it from the current
state.

`ReadyInputAgreement` connects readiness to graph typing. A node is ready
when every output referenced by its input wire is committed. The controller
reconstructs its input from the root input, constants, and only those
referenced committed outputs. For every full typed port environment agreeing
on those references, this value equals the graph's full `input_wire`
evaluation and has the exact fixed input type of the pinned Work. Therefore
independent nodes need not wait for unrelated earlier nodes.

For the abstract frontier, interpret `WorkAction` as exactly one of
`RunLocal(p)`, `GenerateGraph(p)`, `BeginExternal(p)`, or
`ResumeCall(CallKey(p))`. The first three require a ready occurrence with no
committed result/expansion and, for external work, no prior intent. `ResumeCall`
requires the one committed `CallIntent` and no committed `CallOutcome`.
`enabled_frontier(S)` is duplicate-free under action equality and contains
exactly these actions. Local/generator actions use volatile claims;
`BeginExternal` is realized by serially committing the one intent before any
adapter submit; `ResumeCall` reuses that intent. A candidate or a worker return
is never an action in the durable frontier. This is the logical durable
frontier: the adapter's volatile capacity bound gates immediate submission,
not membership. If all slots are occupied, the controller may consume any
completed response to free capacity and then resume another key. P11/P14's
progress claim requires fair response consumption and capacity release; a
permanently nonterminating call may occupy a slot without violating safety.

`RunStarted` is a bootstrap transition, not a `WorkAction`. The controller is
initially given one `StartRequest` (run identity, pinned root entrypoint,
typed root input, and budget); it constructs and authorizes exactly
the matching `RunStarted` event. This request is not durable before that
event's commit. A crash before commit leaves the unstarted empty journal and
the caller may resubmit only the identical request for that run identity. A
different root entrypoint, input, or budget requires a fresh run identity and
journal. A crash after commit recovers the persisted input and never consults
the request again; later requests for that identity cannot replace it. The
unstarted state has an empty work frontier and is excluded from P11's no-stuck
claim, which starts at the successful `RunStarted` transition.

The small-step relation is parameterized by this request while the journal is
empty; call it `ControllerStep_R`. After the bootstrap commit, `R` is no
longer read by any step. A process cut before commit has no started run to
resume; the caller supplies the same request again. A cut after commit is
governed only by the persisted `RunStarted` event and P10.

Precisely, write `refs(p)` for output ports read by occurrence `p`'s input
wire, `CommittedValues(S)` for replayed root/constants/output values, and
`FullEnv(g)` for every legal typed port environment of `p`'s committed graph.
Then

```text
ReadyInputAgreement(S,p,x) :=
  action_enabled(S,p)
  /\ x = sparse_eval(input_wire(p), CommittedValues(S))
  /\ x : input_carrier(work_at(S,p))
  /\ forall eta:FullEnv(graph_of(S,p)).
       agrees_on(eta, refs(p), CommittedValues(S))
       ==> eval(input_wire(p),eta) = x
```

The root input and graph constants are fixed components of the sparse
evaluation. For a generated graph, its root wire is interpreted at the exact
committed generator input. The quantifier ranges over every legal value of
each external output family; a validator or an observed reply cannot narrow
the internal graph's edge proof. P1/P2 establish the graph interpretation
used by this equation.

#### Abstract controller state and steps

The initial executor model has one active commit coordinator per run. It may
own a bounded worker pool and multiple adapter requests, but claim ownership
is local to that coordinator. A deployment with multiple coordinators needs
an additional shared fencing/claim-epoch contract; serial journal appends
alone do not imply global claim uniqueness.

```text
AttemptId = (controller_epoch, fresh_local_nonce)
Claim = {
  occurrence; attempt_id; base_head;
  pinned_work_identity; exact_input; run_charge_metric; exact_allocation
}
Candidate = LocalCandidate(AttemptId, typed_output,
                           artifacts:list PackedArtifactRef,
                           ghost LocalOriginWitness)
          | GraphCandidate(AttemptId, descriptor, graph_local_plan,
                          ghost GeneratorOriginWitness)
          | AdapterCandidate(CallKey, reply_bytes, validated_output,
                            evidence, charge,
                            artifacts:list PackedArtifactRef,
                            ghost AdapterOriginWitness)
Volatile = {
  controller_epoch;
  claims: finite_map NodeOccurrence Claim;
  candidates: finite_map AttemptId Candidate;
  adapter_in_flight: finite_set CallKey;
  append_slot: option (prefix:Journal, event:Event, AppendPermit,
                       status:Prepared | InFlight | CommittedUnacked)
}
Controller = (latest_committed_prefix:Journal, Volatile)
```

`latest_committed_prefix` denotes the journaler's current prefix; it is not a
second state store. The logical state is always `replay_C(J)`. Claims,
candidates, in-flight keys, and append requests are volatile and never affect
readiness or output-wire evaluation. `base_head` is only a freshness hint;
neither it nor an `AttemptId` authorizes an append. Attempt IDs are unique
within an epoch, and every restart obtains a fresh, non-reused epoch. A return
from a revoked epoch is rejected even if its worker finishes after restart.
P13 must realize epoch freshness by preventing such callbacks from crossing
the restart boundary, or by fencing and rejecting them when they arrive.

The transition relation `ControllerStep_R(C,C')` consists only of these
atomic steps:

1. **Bootstrap:** from the unstarted replay state, use `R` to construct the
   exact pinned `RootEntry.start(input,budget)` result and append its one
   authorized `RunStarted` event. No node claim is allowed before this commit.
2. **Claim local/generator:** choose a fresh attempt ID and an enabled,
   unclaimed local or generator occurrence. Construct its claim from
   `ReadyInputAgreement` and its exact replayed allocation. A claim attempt
   for an already claimed or nonready occurrence is rejected without change.
3. **Return/cancel:** a worker may create at most one candidate only for its
   currently live attempt ID from the current epoch; a late callback for a
   revoked epoch is discarded. The return carries the proof-bearing executor
   contract witness that its value is exactly the pinned local/generator
   result at the claim's exact arguments. `LocalOriginWitness` states
   `y = CodeRef.run(x)`; `GeneratorOriginWitness` states
   `(d,plan) = GeneratorRef.generate_graph(x,run_charge_metric,a)`. An adapter witness is the
   exact `P7ReceiptWitness` for its key, request binding, reply/evidence/
   charge/artifact tuple, and reconstructed input; it also proves the
   `persist_x` projection equals the candidate event fields.
   A worker or adapter assertion without the applicable proof-bearing
   contract is not accepted. P9 supplies any physical artifact witness when
   claimed. A cancellation removes that claim and invalidates its attempt ID.
   Candidates remain invisible to graph evaluation and dependent scheduling.
4. **Prepare append:** construct the event from a live candidate, reload and
   replay the latest prefix, and check that the occurrence remains pending
   with the same pinned identity, exact input, and allocation. Reconstruct
   the event-specific `AuthorizedEvent` proof at this current state. Any
   changed field or completed occurrence discards the candidate; if fields
   still agree, the pure deterministic candidate may be reused. The resulting
   `AppendPermit` is indexed by this exact current prefix, state, and event.
5. **Append commit/ack/stale:** at most one append slot is active. At its
   linearization point, successful append changes the durable prefix to
   `J ++ [e]`; that commit point makes the event visible to replay and
   dependent scheduling. The slot becomes `CommittedUnacked` until the
   coordinator observes success, reloads the same committed prefix, and
   clears the associated candidate/claim. The slot's presence suppresses any
   further worker-return or action step from that attempt. While
   unacknowledged, it cannot prepare another append from the stale view. A
   process cut in this window
   clears the slot; recovery decides from P10 whether the event committed.
   A stale response changes no durable state, invalidates its permit, reloads
   and replays the current prefix, then repeats full input/allocation and
   provenance checks. Replacing only the expected head is forbidden.
6. **External intent/dispatch/return:** a ready external node first commits
   its one `CallIntent`. Submission is permitted only from replay state with
   that pending intent, its exact `CallKey` is not already in flight, and the
   configured adapter bound has capacity. Different keys may be in flight
   together. A response is attached only to its matching key and
   only while replay still has that intent pending without an outcome; a late
   response after outcome commit is discarded. The response
   carries P7's proof that the pinned validator accepts it at the exact
   reconstructed input. It stays a candidate until an authorized
   `CallOutcome` append commits. P7 supplies safe same-key resumption and
   effect semantics.
7. **Crash/restart:** at any step boundary, including during computation,
   authorization, append, or after commit but before acknowledgement, discard
   all claims, candidates, in-flight markers, and append slots; advance the
   controller epoch to a fresh non-reused value; settle or fence every
   old-epoch append before loading; load the exact latest prefix under P10;
   and set the new state to its replay. The recovery load is a barrier: every
   earlier append has a final committed/aborted disposition before the load,
   and no old append may linearize afterward. An old append either linearized
   before this load and appears in that prefix, or was aborted and cannot
   linearize later. Old worker callbacks are likewise rejected by epoch.
   P13 supplies the concrete fencing/quiescence mechanism. A pending
   local/generator occurrence may be claimed
   again. A committed one is absent from the frontier. A pending intent is
   resumed under its same key by P7; a committed outcome is never dispatched.

An old worker response after cancellation or restart has a revoked attempt
ID and is discarded. A stale candidate can never use its old proof at a new
head. When a candidate is reconsidered after another append, it is admissible
only if current replay still shows the same occurrence pending and rederives
the same identity, input, and allocation; otherwise it is discarded. The
current-head `AuthorizedEvent` proof is always rebuilt. For already-ready
occurrences, an unrelated successful append either preserves these exact
bindings or makes the candidate fail this check. A newly ready occurrence is
claimed only after the predecessor's output is committed.

The scheduler may claim any finite bounded subset of the duplicate-free
`enabled_frontier`, provided claims are distinct and every dependency is
committed. It submits each external request separately, only after its
`CallIntent` is committed, and need not wait for earlier submissions to finish
before submitting another. Local/generator results, adapter replies, and their artifacts
remain volatile or unreferenced until the corresponding authorized event is
committed. The controller replays the latest head, validates the event and
its semantic provenance against that state, then submits one append. If the
append is stale, it reloads and reauthorizes. Any completed independent
action may be appended next: order follows successful serial commit, not
launch order, node-key order, or external request order. No dependent action
becomes enabled before its producer event commits.

The abstract executor correctness theorem quantifies over every finite
`ControllerStep` schedule and every crash cut, including arbitrary completion
order and crashes that discard volatile claims. Its induction invariant
contains: replay and `StateWF` agreement; authorized `SemWF` history;
`GlobalGraphWF`; unique live attempt IDs and at most one live claim per
occurrence; exact claim-to-input/allocation/identity bindings at claim time;
current-head reauthorization for every append; keyed adapter candidates;
committed-only visibility; and the P8 ledger equations. Between append
linearization and acknowledgement, the durable prefix already includes the
event and the append slot blocks a second append; after a cut, P10 decides
whether the old or new prefix is loaded. `base_head` equality alone never
satisfies reauthorization. P15 is stated conditionally on the P10 store-cut
contract in §4.4. P9 is added only
when physical artifact identity is claimed.

Write `T_i` for successful event linearizations through step `i`, and
`S_i = replay_C(J_i)`. The target is the following inductive safety claim,
conditional on P0-P10 and the service contracts named above:

```text
P15:
  forall request R, initial C0, finite trace tau, final Cn,
    InitialAuthorized(C0,R) /\ ControllerSteps_R(C0,tau,Cn)
      /\ P10CutLaw(tau)
    ==> forall reachable prefix i of tau,
          ExecutorSafetyInvariant(T_i, C_i)
```

`ExecutorSafetyInvariant(T,C)` expands to `J = latest committed prefix`,
`S = replay_C(J)`, `StateWF(S)`, `SemWF(C,T,J,S)`, and `GlobalGraphWF(S)`;
all live claims and candidates satisfy the token/argument rules above;
adapter in-flight keys name pending durable intents; at most one append slot
exists; and only a linearized authorized event changes `J`, the action
frontier derived from durable state, or visible outputs. Volatile claims may
remove a currently running action from the controller's schedulable subset,
but cannot change `enabled_frontier(S)`. For every crash step, P10 gives the
next `J` and the restart transition sets volatile state empty before deriving
new actions. `InitialAuthorized` includes the root entrypoint witness when the
initial prefix contains `RunStarted`; formally, it holds either for the
unstarted empty prefix with a valid typed `StartRequest R`, or for a prefix
already carrying its `SemWF` authorization witnesses (in which case `R` is
unused). `P10CutLaw(tau)` is the conjunction, for every restart load cut `c`,
that (a) all earlier append requests have a final committed/aborted
disposition before the load and none can commit after it; (b) if `J_c` is the
append-commit history through that barrier and `B_c` the exact loaded bytes,
`decode_journal(B_c) = Ok(J_c)` and `B_c = encode_journal(J_c)`; and (c) for
ordered cuts `c <= d`, `J_c` is a prefix of `J_d`. Thus a cut cannot omit an
event committed by its barrier, include an event not committed by it, or
admit a late append from an old controller. `SemWF` witnesses correspond to
precisely those linearized events. Fairness and eventual completion are not
assumed or concluded here.

> **ExecutorInterleavingPreserves.** From an authorized semantically
> well-formed committed prefix, every permitted schedule preserves unique live claims,
> action readiness, exact input/allocation bindings, serial append legality,
> typed graph well-formedness, event provenance, and ledger invariants. Only
> committed results enable dependents. `NodeCompleted` and `GraphCommitted`
> occurrences already committed are never executed again; an uncommitted
> local/generator calculation may be recomputed after a crash. A pending
> `CallIntent` is resumed under the same key and effect-safe logical
> operation; a committed `CallOutcome` is reused without dispatch. After
> every crash, volatile controller state is discarded and the durable state
> is exactly replay of the latest journal prefix.

This theorem does not claim exactly-once physical local computation before
commit, exactly-once network delivery, or concurrent journal writes. It
proves that such retries cannot change committed workflow meaning. The
abstract safety theorem is separate from P13: a later concrete worker pool,
controller, journaler, and adapter must each prove refinement to these
contracts. Scheduler fairness, append progress, adapter eventual outcomes,
total local/generator computations, and finitely many crashes are liveness
premises, not safety premises.

### 4.3 Graph commit and node execution

For a dynamic graph occurrence, the transition is:

1. From its committed input, pinned `GeneratorRef`, RunStarted charge metric,
   and ledger-derived `GenerationAllocation`, compute the unique
   `GeneratedGraph`; its universal admission proof gives `graph_wf` and
   `allocation_plan_wf` for these exact arguments.
2. Authorize one `GraphCommitted` event whose bytes are the canonical encoding
   of exactly that descriptor and whose graph-local plan equals exactly that
   result's `child_plan`. Append is fenced by the current journal head.
3. Replay derives the child graph path as `ChildGraph(parent_graph,key)` and
   lifts each local plan entry to its exact child `NodeOccurrence`. Derive
   enabled child actions only from this committed graph.

Before the graph commit, a crash may recompute the pure generator from the
same arguments. After the commit, recovery decodes and uses those exact graph
bytes; it never asks the generator to choose replacement topology. A child
node cannot be authorized before the graph commit.

For a local node, compute its total result, publish any output artifacts, and
commit `NodeCompleted` before exposing that result to consumers. For an
adapter node, commit `CallIntent`, let the adapter start/resume the logical
operation, validate its terminal output, make backing artifacts durable, then
commit `CallOutcome`. No result or artifact reference becomes visible earlier.
The authorized action proves that a local output was produced by its pinned
`CodeRef`, or that a graph was produced by its pinned `GeneratorRef`, before
the corresponding event can be appended. Replay validates canonical identity,
input, and output typing but does not rerun completed local code or a committed
generator. P15 proves this authorization for the abstract schedule; P13
proves concrete refinement; the journaler contract and P10 preserve the
authorized prefix across recovery.

A committed completion is absorbing. On replay the runner reuses its stored
typed output and cannot authorize the same occurrence again. Before a local
completion commit, recomputation is allowed. For an adapter, every recovery
uses the same committed intent; the adapter's contract governs continuation
and eventual outcome. `CallIntent` is the durable handoff: a multi-step
external procedure is one adapter operation when its progress can be resumed
under that intent, or several ordinary `Work` nodes when those steps should
have separate durable outputs. No additional recovery primitive is required.

`GlobalGraph(S)` is the finite graph obtained from the root graph and all
committed graph occurrences by replacing each committed generator occurrence
with its child graph at that occurrence's typed input/output boundary. An
unexpanded generator remains a pending vertex; it does not expose child nodes.
Every local key is namespaced by its path-derived `GraphOccurrence`. The state
invariant `global_dag_wf(S)` requires unique global occurrences, typed
cross-boundary wiring, and a strict topological rank across the expanded graph.
The fuel rule bounds nesting depth; every graph is finite, every graph has
finitely many child generators, and each child generator has smaller fuel than
its parent. Thus the committed expansion tree is finite. `GraphCommitted`
substitution must preserve `global_dag_wf`, so nodes introduced dynamically
inherit the same global acyclicity and occurrence uniqueness guarantees as
root nodes.

#### P4/P5 graph-transition obligations

For a committed state `S` and generator occurrence `p`, let `g` be the exact
pinned `GeneratorRef`, `x` the input reconstructed from `p`'s committed
predecessors, and `a` the allocation read from the replayed ledgers. Write
`m_c` is the metric in the committed `RunBudget`, and
`r = g.generate_graph x m_c a`. Generator admission is the universal law: for
every `x':i`, metric `m_c`, fuel `b`, and charge `c`, let
`a' = { expansion_fuel=b; charge_allocation=c }` and
`r' = g.generate_graph x' m_c a'`. If
`ChargeMetricMember(m,m_c)`, then
`SchemaSupported(m,x',r'.descriptor) /\
allocation_plan_wf(m,m_c,b,c,r'.descriptor,r'.child_plan)`; it does not depend on
which input or budget happens to occur in one run.

`authorize_graph_commit(S,p,e)` succeeds only if `p` is an uncommitted,
ready `GenerateWork g`, its input/allocation are exactly `x/a`,
`e.generator_occurrence = p`, `e.graph_bytes` is the canonical graph encoding
of `r.descriptor` at `x`, and `e.child_plan = r.child_plan` by exact graph-local
syntax and allocation equality. The append also uses the current replay head.
P4 proves the generator-admission theorem, authorization soundness, plan-lift
laws, and transition closure together: after successful apply, the committed
descriptor re-resolves to `r.descriptor`, and the replayed allocations for
child nodes equal `lift_graph_plan(p,r.child_plan)`. Rejected or stale appends
change neither graph nor ledger.

Define `splice(S,p,d)` by removing generator vertex `p`, namespacing every
vertex of `d` under `child_occurrence(p)`, substituting `p`'s input wire for
`d`'s `RootWire`, and substituting `d.output_wire` for every use of `p`'s
output. The child descriptor is indexed by the exact input `x` and its output
wire has type `o x`, exactly the removed generator's declared output family.
The `typed_graph_splice_preserves` theorem states that if
`global_dag_wf(S)`, `p` is a pending generator, and `graph_wf(m,x,d)` with
those exact boundary indices, then `global_dag_wf(splice(S,p,d))`; all
unaffected node types and the root output family are preserved. Acyclicity
follows because child input dependencies originate only at ancestors of `p`,
child output dependencies lead only to descendants of `p`, and `d` is itself
a DAG. Unique child paths preserve occurrence uniqueness. The state transition
does not expose child actions until the corresponding `GraphCommitted` append
is durable.

P5 composes that append theorem with P2 and P10. For every recovered prefix,
decoding at the generator's exact committed input and resolving through the
shared pinned resolver yields the committed child descriptor; replay lifts the
stored local plan through the same path function. `SemWF` carries the exact
generator-result provenance from append authorization. Recovery never invokes
the generator, manufactures replacement topology, or selects a new plan.
`apply` rejects any second graph commit for `p`; a committed graph and its
allocation are absorbing.

### 4.4 Canonicity and durability theorem

The exact guarantee is stated for a journaler value carrying proofs of the
following laws. The crash model is abrupt process exit and restart while the
same store remains available. A crash/recovery cut is the linearization point
of the restart load, after the store has settled or fenced all append requests
from the exited controller. No workflow action runs between process exit and
this barrier. Thus a request already in flight may commit before the barrier
and appear in the loaded prefix, or be aborted; it cannot commit afterward.
The journal is never modified outside the
protocol. This excludes disk or device loss, external edits, corruption, and
rollback by the storage system; the theorem does not claim recovery from
those events.

1. **Atomic prefix:** each append is linearized at one commit point. At any
   interruption, loading exposes the complete journal prefix through the
   latest committed append. An in-flight event is either wholly absent or
   wholly present; an incomplete physical tail, if one exists, is never
   exposed as a journal event. Forks are impossible.
2. **Recovery barrier:** before a restarted controller loads and schedules
   from a prefix, every append request issued by its prior epoch has a final
   committed/aborted disposition. No prior-epoch request may commit after
   that load. The implementation may drain, cancel, or fence old requests;
   P13 proves its chosen mechanism refines this law. This rules out loading an
   old prefix and then having an earlier append appear behind the new
   controller's view.
3. **Monotone durability:** once an event is committed, every later restart
   returns a prefix containing that event in the same position. An acknowledged
   append is necessarily committed. A process exit between commit and
   acknowledgement may still recover the newly committed event. In this
   specification, “journaled” means the append's commit point has passed;
   buffered or merely attempted bytes are not yet journaled.
4. **Protocol integrity:** only the serial commit coordinator's
   current-head-authorized append can extend the journal; old bytes are
   immutable and sequence numbers are contiguous. External mutation is
   excluded by the contract.
5. **Canonical encoding:** every accepted event/journal byte string decodes
   uniquely and re-encodes byte-for-byte. Graph and value codecs satisfy the
   same indexed round-trip and canonicality laws.

Let `H` be the linearized append history and `cut(H,c)` any crash/recovery
cut as defined above. Let `J(H,c)` be the longest prefix whose append commit
points occur no later than `c`. Let `B(H,c)` be the exact bytes returned by
the journaler's load at that cut. The journaler contract requires
`decode_journal(B(H,c)) = Ok(J(H,c))`; journal canonicality then proves
`encode_journal(J(H,c)) = B(H,c)`. The decoded journal is a projection of the
physical bytes, never a separate authority. For cuts `c <= d`, `J(H,c)` is a
prefix of `J(H,d)`. These are journaler refinement obligations, not
conclusions inferred from `replay`. For a restart load at `c`, all earlier
append requests have already committed or aborted, and none can commit after
`c`; thus `J(H,c)` is stable while the recovered controller derives actions
from it.

Write `store(H,c)` for the persistent store at that cut. Define
`load_bytes(H,c) = load_bytes(store(H,c))`,
`load(H,c) = decode_journal(load_bytes(H,c))`, and
`recover(H,c) = replay(J(H,c))` after the required successful decode. The
concrete implementation refines these functions by reading stored bytes,
decoding the canonical journal, then replaying it; successful refinement
yields exactly `J(H,c)` and its replayed state.

From those contract fields, the abstract theorem is:

> **Canonicity and every-cut durability.** For every valid append history
> `H` and every crash/recovery cut `c`,
> `decode_journal(load_bytes(H,c)) = Ok(J(H,c))`,
> `load_bytes(H,c) = encode_journal(J(H,c))`,
> `decode_journal(encode_journal(J(H,c))) = Ok(J(H,c))`, and
> `recover(H,c) = replay(J(H,c))`. For every `c <= d`,
> `J(H,c)` is a prefix of `J(H,d)`. Therefore every event committed by `c`
> is present at every later cut in the same position. If exit races an append,
> the recovery barrier includes the new event exactly when its commit point
> passed before the barrier; otherwise the request is aborted and the old
> prefix is loaded. The controller derives new actions only after the barrier.
> Recovery includes all committed work and makes
> no claim about volatile work before commit.

The associated **canonical-state theorem** is:

> **Canonical state.** For every accepted journal `J`, `replay(J)` is defined
> and deterministic. If `decode_journal(b) = Ok(J)`, then
> `encode_journal(J) = b`; if `J1 = J2`, then `replay(J1) = replay(J2)`.
> Every cached or reconstructed state equals `replay(J)`. Replay consults only
> the event sequence and pinned immutable identities, never volatile runner
> memory or mutable external state.

The abstract recovery proof is by induction over the journaler's linearized
append trace: the append law preserves a legal prefix, the load-bytes law
decodes to exactly that prefix, canonicality proves the bytes equal its unique
encoding, and deterministic replay maps that prefix to its unique state. A
concrete journaler must prove the byte-level contract for its actual write,
flush, and restart behavior; it cannot assume `recover` itself. A crash-only
theorem does not claim survival of disk destruction or a violation of the
store contract.

## 5. Well-formedness, progress, and no loops

Define `WF(J,S)` as `replay_C(J) = Ok(S) /\ state_wf(S)`. It includes at
least:

1. Events form one ordered legal journal prefix; identities and occurrences
   are unique; every event is the legal next transition. Canonical byte
   representation is supplied separately by `JournalCodec` and proved at
   the durable-store boundary by P10.
2. The root graph is the canonical descriptor recorded by `RunStarted`. Every
   committed dynamic graph is canonical, locally well typed under the
   universal edge rule, finite, and a DAG; its input/output indices are the
   exact generator boundary and its allocation plan fits the parent
   allowance. The graph is structurally checked locally; equality to the
   pinned generator result is an authorization-provenance fact.
3. Every generated node is justified by a prior `GraphCommitted`; node keys
   identify their graph occurrence, work reference, and exact input.
4. Every visible output is backed by one immutable completion/outcome and its
   artifact references. Completions and outcomes are absorbing. Backing-store
   durability and resolution are included only when P9's artifact contract
   is included.
5. Every call outcome matches one intent/key/request and decodes at the
   exact reconstructed input. Each adapter occurrence has at most one intent
   and one outcome; a pending intent remains resumable under its same key and
   cannot be replaced by an unrelated fresh call. Validator acceptance,
   reply provenance, and effect-safe retry are `SemWF` facts supplied by P7.
6. Charge/fuel maps have finite support, refer only to live occurrences, and
   are derived from root and graph-local plans. A pending intent retains its
   reservation. P8 proves aggregate conservation and settlement equations;
   replay does not infer them from event bytes alone. If the intended external
   path is unaffordable, any application fallback (for example `None`) must
   be represented in the declared output family and by a valid allocation
   plan.
7. Every dependency endpoint resolves to an occurrence in a committed graph;
   node readiness is determined only by committed predecessor outputs; every
   pending adapter intent resolves to its pinned resumable adapter. There are
   no dangling dependencies or unrepresented waits.
8. Every terminal state is absorbing: it has no enabled work action and no
   event can extend its journal.

The graph-DAG and state-progress requirements are distinct. `WF` is the
replay-checkable local state invariant. Separately, `GlobalGraphWF(S)` states
that the root and all committed generated graphs, after typed boundary
substitution, form one finite typed DAG. P4 proves that each authorized
`GraphCommitted` transition preserves `GlobalGraphWF`; P16 requires it after
recovery. `SemWF(T,J,S)` carries the ghost append-provenance facts for
authorized history T. A cut recovers its exact prefix and state; the proof
transfers `SemWF` from the corresponding history prefix rather than rerunning
completed work. An unavailable or corrupt host store violates the journaler
contract; it is not a durable workflow failure state.

`ChargeAllocations` is a canonical finite-support map keyed by
`NodeOccurrence`. For every reachable state, `allocated` is the sum of its
`allocated_by_node` entries,
`reserved` is the sum of `reserved_by_node`, and
`total = free + allocated + reserved + spent`. At `RunStarted`, direct
external-node maximum charges and child-generator charge allowances are
assigned to their exact root occurrences. A `GraphCommitted` event removes
only the named generator occurrence's allocation `b` and assigns charges to
new child occurrences; direct external maximum reservations plus nested
generator allocations must sum to at most `b`, with the difference returned
to `free`. `CallIntent` moves exactly that adapter occurrence's assigned
`maximum_charge` from `allocated_by_node` to `reserved_by_node`. Its matching
`CallOutcome` removes that reservation, adds actual charge `q` to `spent`,
and returns `maximum_charge - q` to `free`. Unique occurrence and call keys
prevent duplicate allocation or settlement.

Generation fuel has a separate `FuelAllocations` map keyed by generator
`NodeOccurrence`; it is not denominated in external charge. Both allocation
maps have finite support consisting only of live occurrences. Its ledger
satisfies `FuelLedger.total = fuel_free + fuel_allocated + fuel_consumed`,
where `fuel_allocated` is the sum of that map. `RunStarted` allocates finite
fuel to root graph generators, with the remainder free. If `GraphCommitted`
expands an occurrence with fuel `b`, it removes that entry and assigns
child-generator fuels `b_j`; if there are child generators,
`sum(b_j) < b`, otherwise the sum is zero. It adds `b - sum(b_j)` to
`fuel_consumed`. A zero-fuel generator therefore commits no child generators
and leaves total pending fuel unchanged. Recovery reconstructs both allocation
maps exactly from the journal. P8 proves both ledgers and the occurrence-local
transition equations; strict progress is P12's separate obligation.

For each pending generator occurrence `k`, the metric argument to
`generate_graph` is exactly the metric in the committed `RunBudget`; its
`GenerationAllocation.expansion_fuel` is exactly `fuel_allocations(S)[k]`,
and `charge_allocation` is exactly the charge ledger allocation for `k`. The
generator cannot receive a second, caller-selected metric or budget value.

- **No graph cycles:** every `GraphDesc` is finite and has a strict
  topological rank on every edge. Therefore a node cannot depend on itself,
  directly or indirectly, and a finite committed graph has a ready node
  whenever unfinished nodes remain.
- **No stuck journal state:** for every reachable journal `J` after its
  authorized `RunStarted` event and `S = replay(J)`, `WF(J,S)` implies either
  `terminal_output(S) = Some t`
  for the derived root result, or `enabled_frontier(S)` contains an action
  with a legal abstract continuation. A ready local node has a total
  computation action; a ready generator has a total allocation-respecting
  generation action; a pending call intent has a resume action bound to that
  same key. Separately, every well-formed finite graph with unfinished
  vertices has a ready vertex by its strict topological rank. Together these
  facts mean no valid graph or reachable nonterminal journal state is a dead
  end in the logical transition system. This is `frontier_total` (P11): it
  proves existence of a legal continuation, not that a concrete scheduler or
  service eventually performs it. Eventual progress belongs to P14 and needs
  its fairness and service-progress premises. An adapter with an irresolvable
  outcome is outside the resumable-call contract.
- **No infinite workflow loop:** a successor existing at every state alone
  does not rule out cycles. Define `G(S)` as the sum of assigned expansion
  fuel on all unexpanded generator occurrences, `U(S)` as their count, and
  `W(S)` as the sum of phase ranks for all uncompleted local and external
  occurrences (local pending `1`; external pending `2`, intent committed `1`,
  completed `0`). Use lexicographic rank `(G(S), U(S), W(S))` in `nat^3`.
  A `GraphCommitted` event with parent fuel `b > 0` assigns child-generator
  fuels whose sum is strictly less than `b`, so `G` strictly decreases even
  if the committed graph adds arbitrarily many finite ordinary nodes. If
  `b = 0`, P4's positive-fuel rule for nested generators implies there are no
  child generators: `G` stays equal and `U` decreases by one, even when the
  graph adds ordinary nodes. Root generators may have zero fuel; every
  nested generator must have positive fuel. `NodeCompleted`, `CallIntent`,
  and `CallOutcome` leave `G` and `U` unchanged and each strictly decreases
  `W`. Thus every successful
  post-start event strictly decreases a well-founded lexicographic rank.
  `RunStarted` is the one-time initialization transition and is outside this
  theorem. Retries do not create new logical calls. Concrete encoding may use
  another well-founded measure, but must prove the same strict-decrease and
  finite-initial-rank laws.

The resulting `NoInfiniteProgressCycle` theorem states that every infinite
sequence of successful legal journal appends after `RunStarted` is impossible
by well-founded induction on `(G,U,W)`.
Stale append attempts do not change state and are not progress transitions;
the store refinement and runner must retry them against the latest head. This
theorem does not rule out an adapter looping internally or a runner stuttering
without appending. Every accepted event strictly decreases the rank.
Execution termination additionally applies only after a valid `RunStarted`
has committed. It requires weak fairness with these meanings: every
continuously enabled ready claim is eventually launched; every launched
local/generator computation makes progress until it returns its result to the
controller; every completed local/generator result and every completed
adapter response is eventually considered for its authorized serial append;
every authorized append or stale-head retry eventually commits or is
definitively rejected and reauthorized; and any occupied adapter capacity is
eventually released by a consumed response.
  It also requires progress by the durable store, termination of total
  local/generator/validator code, P7's fair retry/query and eventual terminal
  outcome or reconciliation for every admitted call, progress for any
  required artifact-store resolution, and only finitely many process exits.
  Under these premises each started run eventually reaches its typed root
  terminal output. An infinite stream of process crashes can delay completion,
  but every restart still recovers the latest committed prefix.

### 5.1 Recovered semantic graph correctness

Let `tau` be a finite controller trace containing crash/recovery cut `c`,
`H = appended_events(tau)` its serial append history, `J_c` the exact prefix
whose append commit points have passed at the recovery-load barrier, and
`S_c = replay(J_c)`. Under P0-P8, P10, and P15, the required composite
theorem is:

~~~text
RecoveredSemanticGraphCorrectness:
  ControllerSteps_R(C0, tau, Cn)
  and AuthorizedHistory(appended_events(tau))
  and StoreCut(appended_events(tau), c, J_c)
  and P10CutLaw(tau)
  ==> recover(H,c) = Ok(S_c)
      and SemWF(appended_events(tau),J_c,S_c)
      and TypedGlobalDAG(S_c)
      and ReadyInputAgreement(S_c)
      and ExactCommittedProvenance(appended_events(tau),J_c)
      and NoPostCommitExecution(tau)
      and CommittedOccurrencesAbsentFromFrontier(S_c)
      and PendingIntentRetryBoundAtCut(tau,c,J_c)
~~~

Here `tau` is the controller's full finite execution trace containing the
recovery cut `c`, and `H = appended_events(tau)` is its serially committed
event projection. `NoPostCommitExecution(tau)` is trace-indexed and means:

```text
for every local/generator claim of occurrence p:
  no NodeCompleted(p)/GraphCommitted(p) occurs earlier in tau
for every adapter submission (p,K,Q):
  a CallIntent(p) occurs earlier with exactly binding (K,Q)
  and no CallOutcome(p) occurs earlier in tau
```

`PendingIntentRetryBoundAtCut(tau,c,J_c)` quantifies only over calls whose
`CallIntent` is in `J_c` and whose `CallOutcome` is absent from `J_c`: every
post-cut retry of that call uses the exact operation, key, request, and resume
binding fixed by that intent, and P7 proves the retries reconcile one logical
effect and terminal receipt. Calls first begun after `c` are covered by
`NoPostCommitExecution(tau)` against their own earlier committed intents.
Thus a `NodeCompleted` or `GraphCommitted` occurrence is never claimed again,
a completed external call is never submitted again, and a pending external
intent resumes only under its effect-safe binding. `CommittedOccurrencesAbsentFromFrontier(S_c)` is the separate
state-local fact: replay does not enable committed work. P15 proves the trace
property; P16 combines it with the recovered state. Pending-call retry safety
does not assert eventual completion; P14 owns liveness premises.

`TypedGlobalDAG` says the root graph and every committed generated graph
resolve through the same pinned manifest, every graph is finite and acyclic,
every node input has its fixed declared carrier, and every producer/consumer
edge satisfies the universal all-legal-environment equality in §2.2.1.
`ExactCommittedProvenance` says each local completion equals its pinned
function result at the reconstructed input; each external outcome is accepted
by the pinned validator for the exact input and same durable intent key; each
graph commitment is the exact pinned generator result for its input and
allocation. It preserves arbitrary nondeterministic outcomes across recovery
without claiming distinct calls are deterministic. A committed completion,
graph, or outcome is reused and cannot be computed or dispatched again.
Before commit, pure local/generator work may be recomputed. A pending external
intent resumes the same logical operation under its stable key and effect-safe
adapter contract.

This theorem is stronger than canonical journal replay. Replay establishes
the exact durable state and graph typing; the authorized append history
establishes semantic origin; P10 carries both across every process-exit cut.
No proof witness is stored as journal payload. The base theorem treats
artifact references as typed opaque values in workflow outputs. To assert that
those references resolve to persistent backing objects, strengthen P15/P16
with P9's artifact-store contract explicitly; the extended conclusion is
`ArtifactSemWF` and that every reference in `ResourceRefs(S_c)` resolves to a
handle denoting its exact pinned logical type and immutable version.

## 6. Required proofs

The F* system must define these predicates and prove these results from the
contracts passed to it. Contract laws are proof-bearing fields of explicit
input records. They are theorem parameters, never `assume`/`admit` holes.
Rows distinguish abstract-system theorems from later concrete refinement.

The theorem spine is summarized below. The table is authoritative for the
complete dependency lists; the diagram emphasizes the dependency structure
from graph typing through abstract scheduling, recovery, and concrete
refinement.

~~~mermaid
flowchart TD
  P0["P0 pinned identities and codecs"] --> P1["P1 typed graph construction"]
  P1 --> P2["P2 canonical graph decode and resolution"]
  P2 --> P3["P3 replay WF and canonicality"]
  P2 --> P4["P4 generated graph commit"]
  P3 --> P4
  P4 --> P5["P5 exact graph recovery"]
  P0 --> P6["P6 local result provenance"]
  P3 --> P6
  P0 --> P7["P7 effect-safe external intent"]
  P3 --> P7
  P4 --> P8["P8 charge and fuel safety"]
  P3 --> P8
  P7 --> P8
  CORE["P0-P8, P10 contracts and proofs"] --> P15["P15 all-interleaving abstract safety"]
  P5 --> P16["P16 recovered semantic graph correctness"]
  P6 --> P16
  P7 --> P16
  P9["P9 artifact durability, when claimed"] -. "optional resource identity" .-> P15
  P9 -. "optional resource identity" .-> P16
  P10["P10 every-cut durable prefix"] --> P16
  P15 --> P16
  P15 --> P13["P13 concrete refinement"]
  P11["P11 enabled frontier"] --> P13
  P12["P12 no infinite progress cycle"] --> P13
  P13 --> CONCRETE["Concrete runtime inherits abstract guarantees"]
  P16 --> CONCRETE
  P11 --> P14["P14 conditional termination"]
  P12 --> P14
  P13 --> P14
~~~

| Order | Theorem target | Depends on | Required result |
|---|---|---|---|
| P0 | `pinned_identity_and_codec_resolution` | contracts | The manifest is the canonical projection of the exact bundle; every executable identity uniquely names one coherent complete package (not merely a unique full reference); codec/schema/type denotations and cross-table links agree; the run-wide charge metric and artifact type/reference codecs/resource projections resolve exactly; root entry is exact; indexed decoding uses its exact index; accepted encodings are canonical; abstract reload preserves the manifest and exact identity-to-package association, including generator callback tokens and their admission laws. |
| P1 | `typed_graph_builder_sound_complete` | P0 | `dag_wf` defines finite unique DAGs in `SchemaSupported`; each input wire has its Work's fixed carrier; each direct edge satisfies universal all-legal-environment equality in §2.2.1. Builder soundness and completeness hold exactly for the schema language declared by the pinned manifest. |
| P2 | `graph_codec_and_resolution_roundtrip` | P0, P1 | Decode/encode preserves canonical graph syntax and exact input/output indices, resolved work, constants, ports, edges, and derived typing proof. Root and generated graphs use same resolver. No closure or edge-proof payload is serialized. |
| P3 | `replay_wf_canonical_terminal_absorbing` | P0, P2, fixed `JournalCodec` laws | Empty journal is well formed; legal events preserve replay-checkable `WF`; event and journal bytes round-trip canonically; replay is deterministic; durable logical state is exactly `replay(J)`; terminal states reject all events. It does not pretend to re-execute code to re-prove provenance. `SemWF` remains a separate append-history invariant. |
| P4 | `graph_commit_before_use_and_global_dag_preservation` | P1-P3 | For every exact input/allocation, the pinned generator returns a `SchemaSupported` graph and valid graph-local plan. Authorization commits exactly its canonical graph bytes and local plan. Deterministic occurrence lifting preserves exact allocations. Typed boundary substitution preserves all edge types, global DAG acyclicity, root result family, and occurrence uniqueness; child actions are disabled before commit. Aggregate ledger conservation is proved separately by P8. |
| P5 | `graph_recovery_exact` | P2, P4, P10 | Every recovered prefix containing `GraphCommitted` decodes/resolves its exact committed graph, derives the same occurrence path and lifted plan, and reuses both; generator is never rerun to replace committed topology or allocations. |
| P6 | `local_completion_sound_and_absorbing` | P0, P3 | A committed local output decodes at exact input and equals pinned `CodeRef.run`; a committed local occurrence cannot be scheduled again. Precommit pure calculation may be repeated after crash. |
| P7 | `adapter_intent_effect_safety_and_progress` | P0, P3 | For each committed key and exact request binding, every retry/overlap joins one logical effect and one byte-identical terminal receipt; changed binding is rejected; receipt/evidence/charge/artifacts correlate to the exact input; effect safety holds across adapter restart; distinct keys may be nondeterministic and complete out of order; liveness is conditional. P15 owns controller dispatch/no-redispatch; P8 owns one-time ledger settlement; P9 owns backing-object identity. |
| P8 | `charge_and_fuel_ledgers_safe` | P3, P4, P7 | In one pinned run charge metric, replay proves `total_charge = free + sum(allocated) + sum(reserved) + spent` and `total_fuel = fuel_free + sum(fuel_allocated) + fuel_consumed`; each occurrence map is the exact projection of committed plans; graph commits, intents, and outcomes preserve the equations and settle once. P7 proves receipt charge truth/binding. Static plans fit every action; unused root remainder is not dynamically reallocated. |
| P9 | `artifact_publication_safe` | P0-P3, artifact-store contract | Every resource reference in a committed typed payload has a pinned type/schema/reference codec and exact inventory projection. Its backing version is complete and durable before append; every supported restart resolves it to a handle denoting the same logical typed object/version; reachable versions cannot be overwritten or deleted. Replay performs no store I/O. Add `ArtifactSemWF` to P15/P16 only when persistent-resource identity is claimed. |
| P10 | `canonicity_and_every_cut_durability` | P0-P3, journaler contract | Every crash cut's exact loaded bytes decode to the latest complete committed prefix and, by canonicality, equal its unique encoding; old append requests are settled or fenced before restart derives actions and cannot commit after the load; committed events persist monotonically; replay returns exactly that prefix's state. Concrete persistence and fencing refine the journaler contract separately. |
| P11 | `frontier_total_and_no_stuck` | P1-P8, P15 | Every started reachable nonterminal state has a legal enabled action or same-key resumable intent. The pre-`RunStarted` empty journal is bootstrap, not a stuck run. Frontier existence is safety; eventual service completion requires stated liveness contracts. |
| P12 | `no_infinite_progress_cycle` | P3-P8 | Every successful post-start append strictly decreases a well-founded rank, including in any permitted serialization order; rejected stale appends do not count as transitions. |
| P13 | `concrete_runtime_refines_abstract_system` | P0-P8, P10-P12, P15; P9 only when persistent resource identity is claimed | Concrete controller, worker pool, serial journaler, adapter, extraction, and host identities refine their abstract contracts and perform only authorized transitions; restart fences prior append requests and revokes old attempt callbacks; run-identity allocation prevents collisions in the adapter-key namespace. This is an implementation obligation, not an abstract-system premise hidden as a theorem. |
| P14 | `conditional_termination` | P11-P13 | After a valid `RunStarted` commits, weak fairness for continuously enabled claims, claimed local/generator result return, append retries, and completed-response consumption, total local/generator/validator code, P7 adapter outcome/reconciliation progress, journal progress, any required artifact-store resolution progress, finite initial fuel, and finitely many crashes imply the started run reaches its typed root output. |
| P15 | `executor_interleaving_preserves` | P0-P8, P10 | For every permitted bounded schedule, unique live claims, ready-input agreement, event authorization, typed graph `WF`, ledger invariants, commit-before-visibility, recovery, and no-rerun-after-commit hold under arbitrary local/generator and keyed adapter completion order. Journal appends remain serial. Artifact references are typed opaque values by default; P9 adds safe publication and concurrent post-commit resolution when included. |
| P16 | `recovered_semantic_graph_correctness` | P0-P8, P10, P15 | For every authorized controller trace and every crash cut, recovery yields the latest committed prefix and `SemWF`; every root/committed generated graph is a typed DAG; every committed local/external result and generator graph has exact contract provenance; trace safety forbids redispatch after completion, while the recovered frontier excludes committed work; pending intents at the cut retry only under their exact committed binding. Add P9 only when claiming persistent backing-object identity. |

### P13: concrete-to-abstract refinement obligation

P13 is proved for a chosen implementation. It connects that implementation's
observable transitions and state to the abstract controller, journaler,
executor, adapter, codecs, manifest, and—when claimed—artifact store. The
implementation may choose its internal data structures and host mechanisms;
it must provide a concrete state relation and prove that they implement these
abstract contracts. Saying that a component “implements” an interface is not
the refinement proof.

Write `c0 ->*_conc cn` for any finite concrete runtime trace, including worker
callbacks, adapter requests/responses, journal commits, and process exits.
Let `H(c)` be the ghost sequence of successful append linearization points
through concrete state `c`; `J(c)` is its committed prefix visible at `c`.
`store_bytes(c)` is the current complete journal image exposed by an atomic
store read at `c`. At a recovery cut, `load_bytes_at(c,b)` is the exact byte
string returned by the load at barrier `b`. `effects(c)` is the adapter's
operation history. For fixed abstract `ReplayContext ctx`, define the
representation relation schematically as:

`Controller` has no independent durable `State` field. Define its logical
state by `logical_state(ctx,A) = replay(ctx,A.latest_committed_prefix)`; the
state clause below asserts this replay is defined and well formed.

~~~text
ConcreteRep(c, A) :=
  (journal_codec(ctx)).decode_journal(store_bytes(c)) = Ok(J(c))
  /\ A.latest_committed_prefix = J(c)
  /\ A.volatile = abstract_volatile_projection(c)
  /\ context_matches_pinned_bundle(ctx,c)
  /\ adapter_trace_refines_P7(effects(c))
  /\ (exists S. replay(ctx,A.latest_committed_prefix) = Ok(S)
        /\ StateWF(S))
  /\ (P9 supplied ==> resource_projection_refines_P9(c))
~~~

`A` is a P15 abstract controller state, not another durable store. Its journal
and replayed state are derived from the concrete journal image. The volatile
projection relates live worker claims, candidates, adapter in-flight keys,
and append status to the abstract controller fields; it never contributes to
the replayed durable state. `context_matches_pinned_bundle` says that every
loaded identity resolves to the same complete canonical manifest and exact
identity-to-package association named by the run, including implementation,
validator, codec, schema, resolver, generator-admission, and root-entrypoint
entries.

The P13 simulation theorem has these clauses:

~~~text
ConcreteInitial(c0) ==> exists A0.
  J(c0) = []
  /\ A0.latest_committed_prefix = []
  /\ A0.volatile = abstract_volatile_projection(c0)
  /\ ConcreteRep(c0,A0)

ConcreteRep(c,a) /\ ConcreteStep(c,c') ==>
  (exists a'. ControllerStep_R(a,a') /\ ConcreteRep(c',a'))
  \\/ (ConcreteStutter(c,c') /\ ConcreteRep(c',a))

ConcreteRep(c,a) /\ ConcreteCrashLoad(c,c',b) ==>
  let H = concrete_history(c') in
  let Jb = prefix_through_load_barrier(H,b) in
  exists a'. ControllerStep_R(a,a')
  /\ a'.latest_committed_prefix = Jb
  /\ EmptyVolatileWithFreshEpoch(a'.volatile,a.volatile)
  /\ load_bytes_at(c',b) = store_bytes(c')
  /\ (journal_codec(ctx)).decode_journal(load_bytes_at(c',b)) = Ok(Jb)
  /\ J(c') = Jb
  /\ (exists S'. replay(ctx,a'.latest_committed_prefix) = Ok(S')
        /\ StateWF(S'))
  /\ ConcreteRep(c',a')
~~~

`EmptyVolatileWithFreshEpoch(v',v)` means that at the recovery-load barrier
all claim and candidate maps, adapter in-flight keys, and the append slot are
empty; no new work is dispatched until this load completes. The new
controller epoch has never been used before. The pending external intent
itself remains in the journal; P7 resumes it by its same key. A crash before
`RunStarted` uses the bootstrap rule and identical-request condition from
§4.2.

An implementation that groups several internal operations into one host
transition may instead prove a finite abstract simulation path for that
transition. A linearized journal commit must always correspond to exactly one
authorized abstract append; no implementation path may expose a candidate or
append an event outside `ControllerStep_R`. The concrete trace projection
preserves the order of committed events and the event's exact bytes. P10
proves the physical bytes/load/prefix law; P15 proves abstract authorization
for every resulting interleaving; P16 carries semantic provenance through
the recovered prefix. Concrete termination additionally uses P14's progress
premises; a safety simulation alone cannot prove that a host scheduler or
remote service makes progress.

The component proofs that establish `ConcreteRep` and the simulation must
cover at least:

1. **Exclusive coordinator and worker pool.** Enforce one append coordinator
   per run or prove a shared fencing protocol. Atomically claim each
   occurrence at most once per live epoch. Bind each callback to its exact
   non-reused attempt token, pinned identity, reconstructed input, and
   allocation. Reject canceled or old-epoch returns. A claimed task returns
   only the pinned local/generator result; candidates remain invisible until
   the authorized append commits. If P14 is claimed, prove the concrete
   executor returns results under its stated fairness/progress contract.
2. **Serial journaler.** Prove compare-and-append against the exact expected
   head, one linearization point, atomic prefix visibility, no unauthorized
   raw-write path, and stale rejection with no mutation. Acknowledgement
   follows commit. At every supported restart, prove exact physical load
   bytes decode to the latest committed prefix and canonical re-encoding is
   byte-identical. Settle or fence every old append before restart load; no
   old append may commit after the load. Show that the selected filesystem,
   database, or device operations refine these laws; a CAS or process-local
   mutex alone does not establish the recovery barrier.
3. **Current-head authorization.** On stale head, reload and replay, rebuild
   the exact input and allocation, recheck pending status, and reconstruct
   `AuthorizedEvent`. An old permit cannot be retargeted by changing only its
   head. Prove committed occurrences are absent from future dispatch and
   remain absent after every recovery cut.
4. **Adapter transport and effect history.** Show each submission follows
   one committed `CallIntent`, retains its exact `CallKey` and request/resume
   binding, and returns a result correlated to that key. Retries and overlapping
   calls across restarts refine P7's one immutable terminal tuple and its
   operation-specific effect/reconciliation law. `CallOutcome` construction
   invokes the exact pinned `validate_reply` at the reconstructed input and
   uses the matching `persist_x` projection of that same P7 receipt. The
   adapter may be nondeterministic across distinct keys. Any assumption about a remote
   service's deduplication, status, or effect semantics must appear as an
   explicit proof-bearing environment contract; it cannot be silently
   inferred from local transport code. P14 liveness also requires fair retry,
   response delivery/consumption, and terminal reconciliation per admitted
   key.
5. **Manifest, extraction, and codecs.** Prove that run creation allocates a
   unique `RunIdentity` in the shared adapter-key namespace. At load and every
   restart, prove the concrete loader resolves the journal's identity to the
   same complete manifest and exact identity-to-package mapping. Prove compiled
   or interpreted local/generator code and `validate_reply` refine the pinned
   F* functions. Concrete indexed codecs preserve the abstract encode/decode,
   typing, and canonicality laws at the exact input index. If identities use
   digests, establish the required collision-resistance/uniqueness premise
   explicitly.
6. **Optional persistent resources.** Only when claiming P9, prove exact
   typed reference projection, complete durable publication before journal
   commit, immutable logical type/version identity, and same-object
   post-restart resolution. A fresh host handle is acceptable when it denotes
   the same object under the pinned resource semantics. Without P9, artifact
   refs remain typed opaque values and no physical-store guarantee is claimed.

The simulation proof must reject these concrete counterexamples: an old
worker return crossing an epoch; two coordinators claiming or appending the
same run independently; a torn/trailing journal tail exposed as committed;
an old append linearizing after restart loaded; a changed implementation or
codec hidden behind a reused identity; a retry after lost remote response
performing a second logical effect; two runs sharing one adapter key; or a P9
reference resolving to missing, overwritten, or different content. These are
violations of a named P0/P7/P9/P10/P15 contract, not grounds to weaken P13.

P13 proves the concrete service refinements and composes them into a forward
simulation using P0-P8, P10-P12, and P15. P9 is additionally required only
when persistent resource identity is claimed. For liveness, it must also
establish that concrete scheduling and service behavior satisfies P14's
fairness premises, or leave those premises explicit in the instantiated
claim. P13 establishes no platform fact by declaration. If a host,
filesystem, operating system, compiled-code boundary, or remote provider
cannot supply a required law, that law remains an explicit premise of the
instantiated system and the corresponding end-to-end claim is conditional on
it.

`P16` is the central semantic recovery theorem. `P10` alone proves byte
prefixes and canonical replay; it does not prove event provenance. `P15`
proves abstract authorization for every schedule; append-only refinement
preserves the authorized prefix; P16 composes those facts with P0-P8 and P10.
P9 strengthens this result when persistent artifact identity is claimed. P13
then transfers the abstract result to a concrete implementation. This split
prevents a well-typed journal from being mistaken for proof that its values
came from the declared local code, external validator, or graph generator.

### Contract-bearing inputs and refinement boundary

The abstract theorem module is polymorphic in explicit records that pair each
service with proofs of its laws. If a required contract record cannot be
constructed, the corresponding system instance cannot be constructed. This
keeps premises visible in theorem arguments without treating them as F* axioms.

- **Journaler record:** serial compare-and-append, one linearization point,
  atomic prefix visibility, monotone durability, latest-prefix byte load,
  proof that decoding those bytes yields the committed prefix (and canonical
  encoding therefore reproduces the exact bytes), restart availability, and
  no external mutation. These are exactly the premises of P10; the journaler
  does not implement semantic authorization or accept parallel writes.
- **Pinned registry record:** actual package tables and their canonical
  manifest projection; identity-level uniqueness/coherence for work,
  generator, operation, validator, graph-codec, schema/rule, resolver, codec,
  and root-entrypoint packages; cross-table signature/schema/codec laws;
  total pure local/generator functions; canonical indexed codecs; and
  restart-stable identity-to-package association. Correspondence between
  identities and extracted host binaries/loaders is proved by P13 refinement.
- **Graph builder/resolver record:** sound and complete construction and
  resolution for the declared graph language, universal edge rule, canonical
  bytes, finite DAG checking, and typed expansion preservation. P1/P2 prove
  these properties; no arbitrary type equality is presumed reifiable.
- **Local/generator executor record:** exact results for pinned total pure
  code and generator, immutable occurrence claims, bounded concurrency only
  among distinct ready occurrences, and fair claim service when termination
  is claimed.
- **Adapter record:** multiple distinct in-flight keys, keyed outcomes,
  effect-safe retries by deduplication/status lookup or operation-specific
  idempotence/reconciliation, exact validation/evidence/charge correlation,
  and per-key eventual outcome only under named liveness conditions.
- **Artifact-store record:** publish-before-reference durability and
  post-restart resolution to the same typed object under pinned identity.
  This contract is representation-independent for files, trees, network
  resources, databases, and other handles.
- **Scheduler/host refinement record:** fair admission and append service for
  liveness; proof that the concrete controller, worker pool, extraction, and
  service implementations refine the abstract interfaces for P13.

These records are theorem inputs carrying proofs, not unchecked assumptions.
No system theorem may contain `assume` or `admit()` as its proof. Concrete
SQLite/filesystem, process, network, and extraction claims remain separate
refinement results and are not silently inferred from the abstract model.

## 7. Expressibility targets (not tests)

These workflows constrain what the API must encode. They are examples for
proof development, not substitutes for proofs or a request to write tests.

1. **Dependent pure result:** a total F* node computes
   `Work nat (fun n -> Prime n)` and returns a witness or certificate.
2. **Verified local computation:** a dependent result is reused after recovery
   once `NodeCompleted` is committed.
3. **Static analysis over files:** take a typed list/tree of source files;
   generate one CLI-analysis node per input file and a parser/join node;
   materialize files through the adapter, collect report artifacts, and
   validate the aggregate in F*. Prove parsing/refinement in F* and the
   materialization/CLI behavior through the adapter contract.
4. **Data-dependent DAG:** use a committed input to build differing finite
   node counts, edges, fan-out, and joins; recover the exact graph after
   `GraphCommitted`.
5. **Network or reusable operation package:** import a library adapter or
   define an inline adapter and use the same typed request, intent, result,
   and proof interface.
6. **Deterministic dummy adapter:** implement a scripted event queue as an
   adapter and prove its behavior refines the same intent/outcome contract.

## 8. Open representation work

The following source-level representation choices remain open for the later
implementation; none may weaken theorem targets above. “Ready for
implementation” means the semantic definitions, theorem statements,
dependencies, and acceptance rules are fixed, and each remaining source
encoding has an owner and a decision rule that preserves those contracts. The
implementation packet records that mapping. It does not need to preselect
every F* encoding. If an owner cannot find an encoding that meets its rule, or
a proposed encoding changes semantics, stop for human review with the exact
counterexample and choices. This does not defer or weaken any proof obligation:
the eventual implementation must prove every applicable theorem below.
The non-normative [implementation packet](implementation_packet.md) maps
these choices to module owners, proof order, and acceptance checks; this
specification remains the semantic source of truth.

- The source-level F* encoding of heterogeneous dependent port contexts, typed
  wiring, existential node signatures, and graph codec. S2-03 specifies their
  abstract judgments; the later implementation DAG owns the source encoding.
- The ghost `WorkMember` relation and builder binding to one pinned registry
  bundle, including exact resolution of work and constant-codec identities.
- The concrete canonical registry-manifest representation and proof that a
  `RegistryIdentity` denotes exactly one manifest derived from that bundle;
  this must include root entrypoints, graph codecs, work/value codecs, and the
  graph resolver and `SchemaMember` coherence needed to transport existential
  type indices.
- The source-level F* encoding of the selected registry-pinned schema AST,
  its denotation proofs, total normalization/equality calculus, and checker
  soundness/completeness. S2-03 defines the abstract syntax, judgments, and
  theorem contracts; the later implementation DAG chooses and proves the
  source encoding. The resolver may not serialize per-edge proofs, use
  internal runtime outputs, or claim completeness for arbitrary erased
  `Type0` equality. P1/P2 are exactly relative to the pinned manifest's
  `SchemaSupported` language.
- The root-entrypoint relation tying root input codec, graph codec, output
  family, and the bundle named by `RunStarted`.
- Whether the minimal graph builder is encoded as a topologically ordered
  port table, a typed constructor term, or an equivalent representation.
- The exact node-key and canonical graph-byte representation. The contract
  requires stable occurrence identity and exact recovery, not a particular
  hash or naming scheme. `NodeKey` must have decidable equality and a
  canonical encoding so uniqueness, lookup, and replay checks are executable.
- Concrete refinements for journal durability, artifact storage, CLI/network
  adapters, and scheduler/extraction behavior.
- Library combinators such as `then`, `fan`, `lift`, and `case`, after their
  expansion into the minimal `Work`/typed-graph interface is proved.

Predicates such as `dag_wf`, `graph_wf`, `graph_isomorphic`, `SemWF`, and the
syntax-directed `WireTyping` relation are definitions fixed by the clauses in
this document, not assumptions available to top-level proofs. The later F*
system must implement them and prove their soundness/completeness before any
theorem relies on them. The planning DAG's final packet must leave no open
semantic definition or hidden admission.

The existing `expand` in earlier `.fst` sources selects registered child
plans and is not evidence for this graph-completeness contract. Those files
remain untouched by this planning task. A later implementation must prove
P0–P16 and the explicit concrete service refinements; contract records cannot
be replaced with hidden `assume` or `admit` declarations.
