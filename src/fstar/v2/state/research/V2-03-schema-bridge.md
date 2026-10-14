# V2-03 schema/type bridge — current status

**Status (2026-10-13):** the original token-manifest proposal below is only a
partial carrier-selection route, not a complete resolver. Schema identity
coherence can transport equal carrier types after identity equality is
established, but it does not establish the required universal prior-edge fact
`forall env. source_type env == target_input`. A canonical compatibility
certificate or schema-expression checker is still needed for that fact.

`PairWire` has since been simplified to a structural pair with no codec
identity. Its dependent pair type follows from recursively resolved children;
the consuming Work's input codec handles pair inputs, and graph output pairs
are reconstructed from their durable sources. This removes the exact-
environment family-codec blocker described in the historical proposal below.
The current decision and evidence are in
[`V2-03-pairwire-simplification.md`](V2-03-pairwire-simplification.md).

## Historical token-manifest candidate (incomplete)

The candidate below remains useful for carrier uniqueness, but cannot alone
complete `resolve_graph`.

**Candidate:** use first-order schema tokens interpreted by one pinned typed manifest. Type-index each producer and consumer from the same manifest interpretation. Never compare arbitrary `Type0` values at runtime.

All signatures below are F*-shaped design notation, not checked declarations.

## Token and manifest

Tokens name value *types*, independently of codec implementation identity.
Product values can use structural pair tokens. A dependent pair wire itself
does not need a registry codec: child wire witnesses define its left and right
type families.

```fstar
type schema_id = { name:string; version:nat; build:digest }

type type_token =
  | Named : schema_id -> type_token
  | Product : type_token -> type_token -> type_token

noeq type schema_manifest = {
  // Finite typed map, assembled from and validated against a table of entries.
  // For unregistered IDs, carrier is an unusable default; registration is
  // the admission boundary.
  registered : schema_id -> bool;
  carrier : schema_id -> Type0;
  rep : id:schema_id -> SchemaRep (carrier id);
  keys_complete : ... // registered iff ID occurs exactly once in source table
}

let rec token_type (m:schema_manifest) : type_token -> Type0 = function
  | Named id -> m.carrier id
  | Product l r -> token_type m l & token_type m r

let rec token_registered (m:schema_manifest) : type_token -> Type0 = function
  | Named id -> m.registered id == true
  | Product l r -> token_registered m l /\ token_registered m r

val resolve_token : m:schema_manifest -> t:type_token ->
  Tot (option (token_registered m t))
```

`token_type` is the key design point: equal first-order tokens have the same
type by reduction, not by comparing `Type0`. The manifest is a dependent
function-backed finite map assembled from typed entries; duplicate IDs are
rejected at construction, and its completeness proof ties `registered` to
the source table. `rep` supplies the codec/structural description indexed by
that same carrier. `Product` therefore gets a structural dependent-pair
carrier. Invalid IDs may have a default carrier, but cannot pass
`token_registered` and are never admitted by builder or decoder.

For nondependent `Product`, `rep` is selected compositionally from the child
reps; a production signature should expose
`token_rep m t : SchemaRep (token_type m t)` and define it by recursion. In
this notation, `rep` abbreviates that recursive construction.

## Structural dependent-pair wiring

`PairWire left right` resolves each child recursively. Given left family
`A env` and right family `B env`, the right child is checked at
`B env (left_value env)`, then `PairWireTyping` constructs
`dtuple2 (A env) (B env)`. Fst/Snd project from that witness. The pair wire
stores no codec identity because it stores no pair value; the consuming
Work's input codec handles a pair input, while graph output pairs are
reassembled from already-durable root, constant, and node-output sources. A
concrete adapter may provide a pair codec as a library combinator at its
input boundary.

Each resolved work/codec entry carries token validity and a type-indexed
denotation proof. The equality is propositional evidence supplied by the
typed manifest entry, never a runtime test over `Type0`:

```fstar
type TokenMember (m:schema_manifest) (t:type_token) (a:Type0) =
  token_registered m t /\ token_type m t == a
```

For equal tokens, type equality is definitional after reducing the one
manifest interpretation:

```fstar
val token_type_unique : m:schema_manifest -> t:type_token ->
  TokenMember m t a -> TokenMember m t b -> Lemma (a == b)
```

Proof: both sides reduce to `token_type m t`; no package equality or
proof-irrelevance axiom is needed. A `Named id` carrier is the unique
function-backed entry for `id`; `Product` follows by reduction. Equality of
type indices supports ordinary F* equality elimination, not unsafe casting.

## Bind plain inputs and dependent outputs

Keep public `work i o` constructors and `Work` indices. Put tokens in pinned registry entries, not executable closures or graph port values. For a resolved work package:

```fstar
type ResolvedWork (m:schema_manifest) (ref:durable_work_ref) : Type =
  exists (i:Type0) (o:i -> Type0) (w:work i o).
    WorkSelectedByRef ... ref w /\
    ref == durable_ref_of_work w /\
    TokenMember m (input_token w) i /\
    (forall x:i. TokenMember m (output_token w x) (o x))
```

`input_token w` is plain. `output_token w x` is indexed: it names exact result type `o x`, and may vary with runtime input `x`. Registry entry pins the token function/version with the work implementation. No output-family codec is treated as a single constant output type.

Likewise, codec registry packages become schema-aware:

```fstar
type ResolvedPlainCodec (m:schema_manifest) (id:codec_identity) =
  exists a (c:codec a) (t:type_token).
    PlainCodecSelectedById ... id c /\
    codec_token c == t /\ TokenMember m t a

type ResolvedIndexedCodec (m:schema_manifest) (id:codec_identity) =
  exists i (o:i -> Type0) (c:indexed_codec i o) (ti:type_token)
         (to:i -> type_token).
    IndexedCodecSelectedById ... id c /\
    indexed_input_token c == ti /\ indexed_output_token c == to /\
    TokenMember m ti i /\ (forall x. TokenMember m (to x) (o x))
```

`WorkSelectedByRef` and codec-selection predicates mean the ordinary
deterministic resolver returned a package whose constructor contains exactly
the displayed implementation. They are graph-relation propositions, not
equality tests on noeq packages. The lookup result itself should be unpacked
once and threaded through validation/building; an implementation should not
resolve twice and try to compare the resulting existential values.

The existing `work i o` API can stay. `codec`, `indexed_codec`, or their registry wrappers must gain schema-token fields; durable work references can remain unchanged only if exact registry lookup guarantees these fields are pinned by the referenced package/build. Prefer wrappers to avoid altering codec call sites. The pinned manifest must bind work, codec, schema entries, and registry identity to actual contents.

## Builder and decoder use

Change `graph_builder`/`typed_graph_witness` to be registry-indexed. `add_node` accepts `ResolvedWork`, not arbitrary `work`; constant-wiring constructors accept exact `ResolvedPlainCodec` or `ResolvedIndexedCodec`. This prevents a same-label local value from standing in for the registered implementation.

During decode, process topological nodes left-to-right:

1. Parse descriptor bytes to first-order `GraphDesc`; parse never claims typing.
2. Resolve each durable work reference; use returned package as the node's executable/type witness.
3. Resolve its input wire at the package's input token. `RootWire` uses root token; `OutputWire` uses earlier node's indexed output token at its actual input; constants resolve their codec token and decode with that exact codec. Indexed constants receive exact graph root `x`.
4. Compare first-order tokens. On equality, `token_type_unique` transports wire result to work input. `Product`, `Fst`, and `Snd` use structural token rules and matching dependent-pair constructors.
5. Extend typed port environment with `o input_value`; after all nodes, require output wire token/type equal `o_root x`.

Resolver contract:

```fstar
val resolve_graph :
  bundle:pinned_registry_bundle -> x:i -> g:graph_desc i o x ->
  Tot (option (w:typed_graph_witness bundle i o x (interpret_graph x g)))

val decode_graph_resolved : bundle:pinned_registry_bundle -> x:i -> b:bytes ->
  Tot (option (g:graph_desc i o x & graph_wf bundle x g))
```

`graph_wf` witness must include resolved work and codec packages, schema transport proofs, prior-port typing, exact projection to descriptor, unique keys, and topological-reference proofs. Build resolved witness constructively; do not make `graph_wf` a Boolean check or return `Some` after name matching alone.

## Current declarations: gap

Current `resolve_global_work`/`resolve_global_codec` establish returned-key equality and exact list membership. Concrete port contexts and refs now prove prior-key membership; typed graph witnesses require exact selected work/codec membership. These changes still do **not** establish type equality from matching IDs. `pinned_registry_bundle` has no identity-to-content manifest theorem, and no general typed resolver reconstructs `graph_wf` from first-order syntax. Node input remains fixed at one type `a`; an output wire can have type family `source_type env`, requiring a universal proof `forall env. source_type env == a`. The token candidate above does not derive this by itself. Therefore P0/P2 cannot be discharged with current declarations.

Schema bridge is a partial route, not a completed source implementation. Still prove registry construction and exact bundle identity; exact resolver package usage; universal prior-output/work-input compatibility; indexed-constant transport; constant decoder soundness; generator admission; and host reload/build refinement. An indexed family token is pinned code metadata, not a proof that a real extracted host loaded matching code.

## Resolver feasibility prototype — 2026-10-12

Two read-only F* scratch prototypes were checked with `opam exec --
fstar.exe --cache_off --warn_error @285`: `/tmp/V2ResolvePorts.fst` verifies a
dependent snoc port context and syntax-directed root/constant/prior-output
resolution for a small closed registry; `/tmp/V2ResolveMany.fst` recursively
resolves a finite input-shaped node list for a homogeneous Nat schema, keeps
the actual dependent `Work i o` output family, checks output ports, and needs
no `assume`/`admit`.

These prototypes establish feasibility for a restricted universe. They do not
implement the repository `GraphDesc`, do not handle heterogeneous `Type0`
transport or universal input-edge compatibility, and do not prove descriptor
labels equal the exact resolved packages in a `typed_graph_witness`. They also do not
bind a registry identity to a manifest. The concrete next step is to make the
schema universe a parameter of the pinned manifest: each work/codec/family
entry carries a typed schema witness; one resolver result is threaded through
wire construction; equality of schema entries transports the hidden type; the
port telescope is a concrete snoc GADT keyed by graph-node IDs. The general
source resolver must then prove soundness (returned graph is `graph_wf`) and
rejection/completeness laws, and generator admission must use that same result
before commit. These results show the route is implementable with a
schema-indexed manifest; the general proof and source integration remain open.

## Provenance, assumptions, and obligations

- **Observation** — `Kernel.fst` defines `durable_work_ref` only from work and
  codec identities (57–61), first-order wire syntax (66–75), plain and
  indexed codecs with their laws (90–108), and `work input (input -> Type0)`
  (161–170). Thus a work's output is already input-indexed, but type tokens
  are absent.
- **Observation** — `Identity.fst` stores existential `packed_work` and
  `packed_codec` and proves resolver key exactness/registry uniqueness
  (84–151, 153–222). Its pinned bundle holds identity plus two registries
  (224–232); it does not relate bundle identity to content.
- **Observation** — `Graph.fst` has `add_node` over a raw `work` (350–366)
  and a typed graph witness that carries a bundle but lacks exact membership
  evidence (451–467). Existing `ConstantWireTyping` embeds codec/value
  directly (see `Graph.fst` 273–292).
- **Derivation** — registry-key exactness proves which durable key matched;
  it does not equate the carrier types hidden inside distinct existential
  work/codec packages. A first-order type token and a single typed manifest
  interpretation are needed to connect those indices.
- **Assumption** — bundle construction is closed-world or generated from a
  statically known finite schema table. `carrier : schema_id -> Type0` is an
  F*-shaped denotation family, not an extracted function dynamically
  manufacturing types from arbitrary strings. If runtime-open registration
  is required, this sketch is insufficient as written: specify a GADT table
  plus a proved carrier-coherence relation, or use an explicit type-equality
  witness in each resolved registry entry.
- **Decision** — leave `work i o` unchanged; extend pinned registry entries
  (or wrappers) with input/output token metadata, add schema-aware codec
  wrappers, index graph builders by the exact resolved registry snapshot,
  and make decoder-produced witnesses include token/type transports.
- **Unresolved obligation** — choose and prove the finite manifest encoding
  in F*: generated family versus GADT keyed table; prove token validity,
  canonical schema identity, and bundle-content binding. This artifact
  specifies the type-level bridge, not that representation proof.

## Why this is minimal enough

One schema table supplies type equality for every graph edge. It adds no second codec implementation and no per-node type casts. Existing `Work i o` and first-order `GraphDesc` remain; only registry packages, builder evidence, and graph resolver gain token metadata. Pair tokens are structural, so normal pair/fst/snd wires need no user registrations. Named user types remain explicit registry entries. Current declarations cannot silently imply these obligations.
