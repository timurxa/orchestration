# V2-02 typed DAG builder: independent audit

> **Historical snapshot — pre-simplification.** This design review predates
> indexed constants and the current `GraphDesc` generator result. Current API
> decisions are in `V2-01-02-simplification.md` and `implementation_spec.md`;
> retain this report for its completeness and counterexample analysis.

## Status and conclusion

**Proved facts:** none about DAGs in current `Kernel.fst`. File defines typed
`work`, codecs, references, and a payload-only `graph_desc`; no vertex table,
wire syntax, builder, `dag_wf`, soundness, or completeness theorem.

**Proposal:** current spec materially fixes source-port completeness by adding
codec-backed constant wires. It now expresses every *root/earlier-output/
constant-generated* typed DAG, if constants are restricted to closed values
with suitable codecs. It still does not fully state dependent constants,
constant decoding identity, or fresh-key allocation. Those are P1 blockers.

**Recommendation:** define arbitrary DAG precisely as finite typed graph whose
node inputs are syntax trees over root, earlier outputs, closed constants, and
dependent pairs/projections. Add input-indexed constants (or explicitly
exclude root-dependent constants). Make `NodeKey` a builder-allocated natural
and put executable codec resolution in `WireTyping`. Then prove builder
soundness/completeness by topological induction. Do not treat schematic
signatures or `graph_wf : ... -> prop` alone as proof.

## Source map

- Spec's three-kind core and dependent `Work`: `implementation_spec.md` §§2,
  around lines 19–69; executable node graph and constructor discussion around
  lines 183–205.
- Proposed `Wire`, `ConstantRef`, typed DAG record, builder signatures, and
  graph theorem signatures: lines 207–315.
- DAG clauses, wire typing, isomorphism, and builder laws: lines 325–447.
- Graph codec, bounds, nested generator allocation, and expressibility target:
  lines 402–470.
- Actual kernel: `src/WorkflowV2/Kernel.fst:33-71` defines codec, indexed
  codec, local code, and operation. Lines 73–97 define `graph_desc` as only
  `{ graph_payload:bytes }` plus generator returning it. Lines 99–140 define
  three `work` constructors and wrappers. Comments at lines 73–75 explicitly
  defer V2-02 graph structure and builder laws.

## What “arbitrary typed DAG” can mean here

Representable topology is arbitrary finite fan-out/fan-in, provided each
vertex's input value can be assembled by the declared wire language:

1. graph root input;
2. outputs of earlier vertices;
3. codec-backed constants;
4. dependent pair construction and projections.

Every nontrivial transform remains a `Work` vertex. Edges are exactly
`OutputWire` references. Disconnected source vertices need constant/root
inputs. This is a legitimate general DAG language, but it is narrower than
unqualified “every typed DAG” unless `FiniteTypedDAG` itself requires every
input to have such a `Wire` derivation. State that restriction in the theorem
quantifier; don't define completeness over a wider independent graph type.

### Constant-wire gap remaining

Spec now has `ConstantRef = exists a. CodecIdentity * Bytes`,
`ConstantWire`, and `constant_wiring : Codec a -> a -> Wiring ... (fun _ -> a)`
(lines 211–14, 250–51). This fixes a plain source node such as `Work unit ...`
rooted at `nat`: old root/output-only wires could not feed it; a canonical
unit constant can.

But this API only states an **unindexed** `Codec a` and constant type
independent of `x` and prior-port environment. `GraphDesc i o x` supports
input-dependent families. Example: zero-node graph with result family
`o x = Fin x`, or source node requiring `Fin x`. There may be a valid constant
for each exact root `x`, yet current `constant_wiring` does not express an
`IndexedCodec i A` plus value `A x`. Either:

- add `ConstantRef (i) (x)` with existential family `A : i -> Type0`, codec
  identity resolving to `IndexedCodec i A`, and canonical bytes decoded at
  exact `x`; use it for dependent constants; or
- explicitly constrain all constant wire types to be closed and accept a
  narrower DAG theorem.

Constants depending on *previous runtime outputs* should not be wires: they
are computations and must be represented by a `Work` node. Root-indexed
constants are different: graph is already indexed by exact `x`, so an indexed
codec can safely decode them.

Also make `constant_wiring` prove that it stores exactly the codec identity
and canonical `encode value` bytes, and that decode resolves to that same
codec/value. Its current `val` signature alone does not expose those laws.

## Suggested core definitions

These are F*-shaped proposals, not current source or verified declarations.
Use an explicit dependent typing judgment rather than an unconstrained
`dag_wf` predicate.

```fstar
type node_key = nat

type constant_ref (i:Type0) (x:i) =
  a:(i -> Type0) & {
    constant_codec:codec_identity;
    constant_bytes:bytes
  }

type wire =
  | RootWire
  | OutputWire : node_key -> wire
  | ConstantWire : constant_ref i x -> wire
  | PairWire : wire -> wire -> wire
  | FstWire : wire -> wire
  | SndWire : wire -> wire

type wire_typing
  (registry:codec_registry)
  (x:i)
  (env:port_env)
  : wire -> (Type0 & Type0) -> prop
```

`constant_ref` above means decoder resolves `constant_codec` to an
`IndexedCodec i a`, then `decode_indexed x constant_bytes = Some v`; proof
object is reconstructed, never serialized. Independent constants use
`a = fun _ -> closed_type`. `WireTyping` should carry resulting type/value
semantics, or an equivalent indexed judgment:

```fstar
Root:       WireTyping env RootWire (fun _ -> i) (fun _ -> x)
Output(k):  env_has k / WireTyping env (input_wire k) A v
            ==> WireTyping env (OutputWire k) (fun e -> B (v e))
Constant:   resolve codec_id = Some c /\
            c.decode_indexed x bytes = Some v /\
            c.canonical_indexed ...
            ==> WireTyping env (ConstantWire ref) (fun _ -> a x) (fun _ -> v)
Pair/Fst/Snd: syntax-directed dependent product rules
```

Exact syntax will depend on the `PortEnv` encoding. Required semantic property:
each wire has one reconstructed typed value for each valid environment; no
unchecked cast or arbitrary closure enters persisted graph bytes.

Use a finite graph record with totality-on-vertices stated explicitly:

```fstar
type finite_typed_dag (i:Type0) (o:i -> Type0) (x:i) = {
  vertices:list node_key;
  label:node_key -> option packed_work_ref;
  input_wire:node_key -> option wire;
  output_wire:wire;
  topo:list node_key
}
```

`dag_wf` must assert: `vertices` has no duplicates; `topo` is a permutation;
label and input wire are defined iff key is a vertex; each label resolves to
one pinned typed `Work`; each input wire's derivation equals that Work's input
family at reconstructed environment; every output reference names an earlier
vertex; each constant decodes canonically under its pinned codec; output wire
has type `o x`. Define edge by prior `OutputWire` occurrence. This makes
topological order a checkable acyclicity witness.

## Builder representation and exact laws

Use `NodeKey = nat` locally. Builder stores ordered vertices, wires, typed
port telescope, graph/codec registry, and `next_key = length vertices`. Each
`add_node` allocates that key; callers cannot inject a duplicate or colliding
string. Canonical graph encoding serializes natural key, pinned work ref,
canonical wire syntax/constants, output wire, and bounds. Graph occurrence
identity adds containing graph commitment as namespace; local key alone is not
global identity.

Current `add_node` signature returns builder and output `PortRef` but no key
or explicit freshness witness (lines 265–73). Make fresh allocation part of
the builder state/invariant, or accept a key plus a freshness precondition.
Need `NodeKey` decidable equality and canonical encoding (spec line ~994); a
canonical monotonically allocated natural is simplest.

Required laws:

```fstar
start_sound x:
  interpret_graph (start_graph x) = root_only_graph x

add_node_sound b ref w:
  builder_wf b /\ wiring_wf b w
  ==> let (b', out) = add_node b ref w in
      b'.vertices = b.vertices @ [b.next_key] /\
      b'.next_key = b.next_key + 1 /\
      old_vertices_and_wires_preserved b b' /\
      new_label b' b.next_key = ref /\
      new_input_wire b' b.next_key = encode_wire w /\
      wire_typing b' (OutputWire b.next_key) (ref.output ...)

finish_sound b w:
  builder_wf b /\ wiring_wf b w
  ==> graph_wf (finish_graph b w) /\
      same_vertices_labels_inputs b (finish_graph b w) /\
      output_wire (finish_graph b w) = encode_wire w
```

Also require constant-wiring sound/canonicality and port-wiring reification.
Those are needed to prove builder completeness, not optional API conveniences.

## P1 proof sequence

1. **Wire typing/evaluation.** Induct on wire syntax. Root reads exact `x`;
   output lookup uses a prior typed port; constant resolution decodes exact
   canonical bytes; pair/projection cases use dependent pair typing. Prove
   deterministic evaluation and type uniqueness. Codec uniqueness is
   conditional on registry identity resolving one codec implementation.
2. **Builder invariant.** `start_graph` has empty unique key list and root
   port. For `add_node`, fresh `next_key` is not in prior vertices; all
   `OutputWire` refs arise from existing `PortRef`s and therefore point to
   earlier keys. New vertex preserves old data. Induct to show uniqueness and
   `topo = [0..n-1]`.
3. **Soundness.** Induct builder operations; `start_sound`, `add_node_sound`,
   `finish_sound` imply interpretation satisfies explicit `dag_wf`. Earlier
   references strictly precede consumer in builder order, so no cycle.
4. **Completeness.** Given `dag_wf d`, enumerate `d.topo`. Maintain bijection
   from already visited source keys to allocated builder keys plus relation
   between source wire derivations and builder ports. For each source vertex,
   recursively reify its wire: root; remapped prior output; canonical constant;
   dependent pair/projections. Apply `add_node`; extend bijection. At end
   reify output wire and `finish_graph`. Prove graph isomorphism preserving
   labels, constant codec/bytes, all wires/edges, output, and occurrence
   multiplicity. Independent topological ordering only allowed via that
   explicit bijection.
5. **Acyclicity/unique occurrences.** In `dag_wf`, every edge points to a
   strictly earlier position. Any directed cycle implies a strict descending
   cycle of natural positions, contradiction. Builder keys are unique by
   `next_key`; isomorphism preserves bijection, so no node is dropped,
   duplicated, or merged.
6. **Bounds.** Separately prove finite graph has finite node/depth/byte/charge
   costs; select sufficient bounds. Nested generators require universal
   boundedness of their `generate_graph` contract over admitted inputs. Do not
   infer nested-generation cost from a single graph's immediate vertex count.

## Counterexamples and remaining obligations

- **No constants (old design):** root `nat`, source `Work unit ...`; neither
  `RootWire` nor prior outputs has type `unit`. Completeness fails without
  constant wire or narrower DAG definition. Current spec adds constants and
  closes this case.
- **Dependent constant:** root `x:nat`, source input `Fin x`, or zero-node
  graph output `Fin x`. Plain `Codec a`/`constant_wiring` does not state an
  input-indexed codec/value. Add indexed constants or narrow theorem.
- **Forged constant identity:** two codec implementations share an ID, or
  stored bytes decode under a different codec than builder's `codec`. Need
  immutable unique registry law and builder proof that wire stores
  `codec_id` plus canonical encoded bytes. Codec identity name alone does not
  prove implementation equality.
- **Duplicate key:** caller-supplied keys `k` repeated can preserve type shape
  while collapsing graph occurrences. `add_node` must allocate fresh keys and
  `dag_wf` must assert distinct vertex keys; string hashes alone require
  collision premises.
- **Vacuous predicate:** declaring `dag_wf d = True` makes `graph_sound` easy
  but P1 false. Spec rightly says `dag_wf` is defined by its clauses, not an
  axiom (around lines 364–78, 1000–05). Give it an explicit inductive/checkable
  definition and prove the judgment corresponds to mathematical edges.
- **Existential work label:** `PackedWork` retains executable terms, but graph
  bytes must contain only canonical `WorkRef`. Completeness/isomorphism must
  compare exact existential input/output families and pinned identities, not
  just node kind or identity strings.
- **No proof in current kernel:** `Kernel.fst:73–97` permits arbitrary bytes
  as graph payload and generator output; there is no witness that bytes decode,
  are canonical, bounded, typed, or acyclic. `work_ref` at lines 115–25 is a
  record but no registry consistency proof exists. All P1 statements above
  remain proposals/targets.

## Proved vs proposed

| Claim | Status |
|---|---|
| Dependent `work`, local/external/generator constructors | Defined in current `Kernel.fst:99–140` |
| Codec roundtrip/canonical fields | Contract fields in current `Kernel.fst:33–50`; no concrete codec implementation here |
| Graph descriptor | Payload bytes only, current `Kernel.fst:73–78` |
| Constant wire, typed DAG, start/add/finish | Proposed in v2 spec lines 207–315; absent from `Kernel.fst` |
| `dag_wf`, graph soundness/completeness, builder laws | Theorem targets/spec clauses, not proved |
| Unique occurrences and no cycles | Claimed via clauses/topological order; needs explicit predicate and induction proof |
| Arbitrary DAG including closed constant sources | Representable in current proposed wire language if constant decoding/typing laws hold |
| Arbitrary DAG with root-indexed constant values | Not explicit in current API; add indexed constant codec or narrow claim |

No implementation files edited. No builds or tests run.
