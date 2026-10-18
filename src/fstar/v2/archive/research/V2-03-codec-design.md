# V2-03 graph codec and resolution design

**Status:** read-only design investigation, not implementation evidence. No F* module or existing state file was changed. This note records one recommended minimal architecture, competing approaches, proof obligations, and unresolved type-reflection work.

## Recommendation

Use one fixed, kernel-owned structural encoding for the first-order `GraphDesc` syntax. Decode bytes into the exact untyped descriptor first; then resolve its work and constant-codec references against the pinned registry and construct the typed graph witness. Compose these two stages in the public graph decoder. Reuse the same structural encoder, parser, resolver, and laws for root graphs and generated graphs.

Do not make users supply codecs for each graph component. Component-level encode/parse functions may factor the proof, but they should be fixed definitions in the kernel format, not independently registered codecs. Do not serialize `Work`, port environments, typing proofs, closures, or allocation ledgers inside graph bytes. Do serialize the exact `DurableWorkRef`, wire syntax, constants' codec identities/bytes, node keys, node order, and output wire. Commit the `AllocationPlan` in the journal event as current V2-03 decisions require.

The main unresolved requirement is type reconstruction: a parsed `DurableWorkRef` is first-order and does not, by itself, provide an F* equality proof between an existentially resolved node's input/output types and the dependent types inferred from prior wires. V2-03 must add a schema/type-token resolver (or equivalent proof-carrying typed manifest lookup) before it can claim P0/P2.

## Current evidence

- V2-03 acceptance explicitly requires round-trip, canonical rejection, typed work/constant resolution against the pinned manifest, root/generated reuse, allocation preservation, and no graph-size bounds (`state/work_dag.md:52-54`; investigation criteria `state/research/V2-03-brief.md:16-35`).
- `GraphDesc` is already a first-order list of nodes and output wire; each node stores `node_key`, `durable_work_ref`, and `wire`; wires are tagged root/output/constant/pair/projections (`Kernel.fst:63-87`). The work ref stores kind, input codec identity, and output codec identity (`Kernel.fst:55-61`). These fields have a direct structural encoding.
- `graph_codec` currently has only identity, `encode_graph`, `decode_graph`, round-trip, and canonicality fields (`Kernel.fst:126-136`). No structural encoder/parser is implemented.
- `generator_ref` carries one `graph_codec` and receives the occurrence's `generation_allocation` (`Kernel.fst:151-159`). The descriptor itself has no allocation fields; the journal stores child allocation plans separately (`Journal.fst:31-38,48-62`). This is the right separation.
- Work and ordinary codec values have heterogeneous global registries and exact-key lookup lemmas (`Identity.fst:79-222`), but there is no graph-codec registry. `pinned_registry_bundle` groups work/codecs but does not bind its identity to their contents (`Identity.fst:224-231`). The V2-03 brief already lists missing graph-codec resolution and manifest binding (`state/research/V2-03-brief.md:51-59`).
- `typed_graph_witness` currently carries a bundle but not evidence that node work and codecs resolve from it (`Graph.fst:450-467`). Source `add_node` accepts raw `work`; constant wiring accepts raw codecs (`Graph.fst:272-303,348-366`), while the spec separately sketches `WorkMember`/`CodecMember` evidence (`implementation_spec.md:279-305,337-371`).
- The spec's P2 asks for exact descriptor, indices, references, constants, wires, and typing-witness reconstruction (`implementation_spec.md:990-993`); its event design keeps allocation plans out of `GraphDesc` bytes and committed separately (`:658-693`).
- Existing code has `FStar.List.Tot`; no repository graph serializer or serialization library use was found. The installed F* library includes `FStar.String.list_of_string` / `string_of_list` and round-trip lemmas, plus `FStar.Char.int_of_char` (`FStar.String.fsti`, `FStar.Char.fsti`). `FStar.Bytes` supplies `append`, `split`, `hide`/`reveal`, and `repr_bytes`, but its model uses `UInt32` lengths (`FStar.Bytes.fsti`); using it directly would introduce a maximum encoded length below 2^32, contrary to the no graph-size-cap decision unless treated strictly as an explicitly bounded host refinement.

## Proposed API and proof boundary

Separate syntax decoding from semantic resolution while presenting a composed typed decoder:

```fstar
// Fixed canonical syntax functions; no user-supplied component codecs.
val encode_graph_syntax : x:i -> g:graph_desc i o x -> Tot bytes
val parse_graph_syntax : x:i -> bytes -> Tot (option (graph_desc i o x))

val graph_syntax_roundtrip : x:i -> g:graph_desc i o x -> Lemma
  (parse_graph_syntax x (encode_graph_syntax x g) == Some g)
val graph_syntax_canonical : x:i -> b:bytes -> g:graph_desc i o x -> Lemma
  (parse_graph_syntax x b == Some g ==> b == encode_graph_syntax x g)

type resolved_graph (r:pinned_registry_bundle) (i:Type0)
  (o:i -> Type0) (x:i) (g:graph_desc i o x) = {
  typed_witness:typed_graph_witness r i o x (interpret_graph x g)
}

val resolve_graph_syntax : r:pinned_registry_bundle -> x:i ->
  g:graph_desc i o x -> Tot (option (resolved_graph r i o x g))

val decode_graph : r:pinned_registry_bundle -> x:i -> bytes -> Tot
  (option (g:graph_desc i o x & resolved_graph r i o x g))
```

`decode_graph` is `parse_graph_syntax` followed by `resolve_graph_syntax`; it does not normalize or rewrite the parsed descriptor. `resolved_graph` should be the constructive derivation behind `graph_wf`, not a free-standing proposition or Boolean oracle. If the actual `graph_wf` includes this witness existentially, expose one proof-producing function and derive the predicate from it.

The crucial laws are:

```fstar
val decode_encode_exact : r:pinned_registry_bundle -> x:i ->
  g:graph_desc i o x -> typed_graph_witness r i o x (interpret_graph x g)
  -> Lemma
    (match decode_graph r x (encode_graph_syntax x g) with
     | Some (g', _) -> g' == g
     | None -> False)

val decode_success_sound : r:pinned_registry_bundle -> x:i -> b:bytes ->
  g:graph_desc i o x -> pf:resolved_graph r i o x g ->
  Lemma (decode_graph r x b == Some (g,pf) ==> graph_wf r x g)

val decode_success_canonical : r:pinned_registry_bundle -> x:i -> b:bytes ->
  g:graph_desc i o x -> pf:resolved_graph r i o x g ->
  Lemma (decode_graph r x b == Some (g,pf) ==> b == encode_graph_syntax x g)
```

Avoid proof-term equality in round-trip: `wire_typing_witness` contains functions and proof objects, and proof equality is not the semantic target. Require exact descriptor equality and existence of a valid resolver witness. The encoder round-trip follows parser inversion; resolver determinism follows the pinned registry's uniqueness and type-indexed exact lookup. Canonicality follows parser canonicality because successful resolution leaves the parsed syntax unchanged.

For every graph node, resolution must establish all of:

1. `resolve_global_work r durable_ref` succeeds at exactly one entry.
2. The selected `Work` reserializes to the exact durable reference; its input/output codec identities are those in the reference.
3. The node's input wire has the exact selected `Work` input type in the environment formed by *earlier* graph nodes.
4. The selected constant codecs are exact entries of the same bundle. Plain and input-indexed constants decode at the graph's exact root input `x` where applicable.
5. The reconstructed typed node sequence's keys and wires project exactly to the parsed `GraphDesc`; the final output wire has family `o x`.

The resolver must reject absent identities, duplicate/ambiguous identities, malformed wire references, trailing bytes, unknown tags, invalid constants, type/schema mismatch, duplicate keys, and edges to non-prior nodes. A parser accepting a prefix and ignoring trailing bytes violates canonicality.

## Structural wire format

Use a version/tagged, recursive, length-prefixed grammar over the project's abstract `bytes`. Current `bytes = list nat` (`Kernel.fst:7`) permits a simple proof model; the extracted storage layer must refine it to physical bytes. One possible logical grammar is:

```text
Graph    := format-tag, node-count, Node^node-count, Wire
Node     := node-key, DurableWorkRef, Wire
WorkRef  := work-kind-tag, pinned-kind-id, input-codec-id, output-tag, output-id
Wire     := RootTag
          | OutputTag, node-key
          | ConstantTag, codec-id, byte-count, constant-byte^byte-count
          | PairTag, Wire, Wire
          | FstTag, Wire
          | SndTag, Wire
Identity := length-prefixed name, version, length-prefixed build-bytes
```

For the current `bytes = list nat` mathematical model, `Nat` can be one list element and list/string framing uses explicit element counts. Encode strings via `FStar.String.list_of_string` and each character code via `FStar.Char.int_of_char`; prove the F* string conversion round trip. For a true octet codec, encode naturals with a canonical base-256 representation: explicit digit length, no leading zero (except zero's unique representation), and a decoder that rejects overflow/nonminimal forms. Do not rely on delimiter sentinels because names, digests, and constants may contain any byte. Every recursive list parser consumes exactly its declared count; the top-level parser requires exhaustion of the input.

This format has no `node_count`, depth, or encoded-size *policy bound*. A finite list gives finite encoding. Parser recursion is structurally decreasing on input/list structure; it must not require a user-provided graph bound. Physical memory and store limits are separate host premises. Fuel/charge are not encoded here: `RunStarted`/`GraphCommitted` own the occurrence allocation plan, and generation receives the ledger-derived allocation (`Kernel.fst:138-159`; `Journal.fst:31-62`).

Proof decomposition: prove each primitive's injective encoding/parser pair; prove the list codec by induction on list; prove `DurableWorkRef` and wire constructors by constructor cases; prove node and graph lists by induction; reject trailing input in the graph parser. This establishes `parse(encode(g)) = Some g` and accepted-byte canonicality without relying on external hash collision assumptions. Graph byte digests, if added for indexing, must not replace byte equality.

## Existential type-resolution blocker

The first-order parse phase can reconstruct `graph_desc i o x`, since its `i`, `o`, and root `x` are supplied statically by the caller. It cannot by itself recover the per-node existential F* types hidden behind durable references. Current `durable_work_ref` records type-relevant codec IDs but no explicit schema token (`Kernel.fst:55-61`); each resolved package has existential `i/o` (`Identity.fst:84-90`). Matching two codec identity values does not prove their F* type indices equal.

Smallest candidate is one schema table inside the pinned manifest:

```fstar
type schema_identity
noeq type packed_schema : Type =
  | PackedSchema: #a:Type0 -> schema_identity -> schema_codec a
      -> packed_schema

val resolve_schema : r:pinned_registry_bundle -> id:schema_identity ->
  Tot (option (a:Type0 & s:schema_codec a & schema_id s == id))
```

Each work entry names its input schema and output-family schema/representation; each codec entry is associated with the same schema token. Unique schema lookup returns the same packed entry for the same key, enabling type transport by using the returned existential directly rather than attempting general decidable equality on arbitrary `Type0` values. The `schema_codec` itself needs typed encode/decode laws. For an indexed output family, the schema descriptor must cover `o : i -> Type0`, not only one instantiated `o x`.

An alternative is to strengthen `resolve_graph_syntax` to return a witness-built typed sequence directly, and require each `Work`/codec package to carry equality evidence connecting its schema identity to that wire's inferred type. Either way, the proof-carrying membership is substantive; the current abstract `WorkMember` / `CodecMember` declarations in the spec do not yet provide constructors or laws (`implementation_spec.md:279-305,337-371`), and current `add_node` source does not take membership evidence (`Graph.fst:348-366`).

Strongest objection to the recommended two-stage design: unless the schema/type-token mechanism is solved, `resolve_graph_syntax` merely becomes a name for the hardest P2 obligation. A structural parser plus matching strings is not a dependent typed decoder. Do not accept P2 until the resolver constructs and projects an actual typed node-sequence witness.

## Root and generated graph reuse

Use exactly the same `encode_graph_syntax`, `parse_graph_syntax`, `resolve_graph_syntax`, and typed graph round-trip for both entry paths:

- Root graph: `RunStarted` supplies root input codec/bytes, graph-codec identity/bytes, pinned registry identity, and initial allocations (`Journal.fst` current records; normative fields `implementation_spec.md:679-683`). Decode root input first, then parse and resolve the graph at that `x`.
- Generated graph: `GenerateWork` reconstructs input `x` from committed predecessors; `generate_graph x allocation` returns `GraphDesc i o x`; append `GraphCommitted` with its exact structural graph bytes and child allocation plan (`Kernel.fst:151-159`; spec `:684-693`). After commit, recovery decodes those bytes through the same structural path and resolver; it does not invoke the generator again.

There must be no root-only or generated-only decoder. The graph descriptor bytes do not include root `x`; the decoder receives the exact `x`, which is essential for indexed constants and dependent output types. The allocation is a generator argument and durable event fact, not graph syntax.

### Graph codec identity choice

Minimal option: one kernel-owned structural graph format per format version, shared by root and generated graphs. `GraphCodecIdentity` then names this fixed parser/encoder version; `GeneratorRef` may refer to that canonical codec. Root `RunStarted` uses the same identity. This avoids a new graph-codec registry and prevents a user graph codec from changing graph typing semantics.

If custom graph codecs are retained, add `packed_graph_codec` to the pinned bundle, prove unique lookup and exact implementation identity, and make both root and child paths resolve the selected codec. Current `global_codec_registry` covers only plain/indexed codecs (`Identity.fst:153-222`); it cannot resolve `GraphCodecIdentity`. Custom codecs add real flexibility but are not needed for the first durable format.

## Competing approaches

### Rejected: compose the graph codec from registered generic component codecs

The spec's competition list names this approach (`state/research/V2-03-brief.md:36-49`). It can factor proofs, but treating each structural component as a separately identity-indexed codec creates a second registry-resolution chain: graph format → list codec → node codec → identity/wire codecs → actual work/value codecs. Current code has no graph codec registry, while generic codec lookup is already an open identity obligation (`Identity.fst:153-222`). Changing one component codec could change graph bytes and compatibility, and every component identity must be pinned or included in `GraphCodecIdentity`. There is no existing serializer in this repo to justify that overhead.

Use small private component functions/lemmas to keep proofs modular, but fix their definitions as one versioned graph format. This gets the proof decomposition without making every internal AST node an independently mutable adapter.

### Considered: one typed registry-driven parse pass

This can avoid representing a parsed-but-unresolved descriptor. However it interleaves byte cursor correctness, registry lookup, existential type transport, and topological wire typing in every recursive parser branch. The spec already separates graph byte round-trip from typed resolution (`implementation_spec.md:990-993`), and current `graph_desc`/`wire` are first-order syntax (`Kernel.fst:63-87`). Two stages give a clean parser theorem and a separate typed resolver theorem; compose them in one public `decode_graph` so callers do not manage a half-decoded state. A monolithic decoder should be revisited only if F* cannot express the resolver relation over the parsed descriptor.

### Considered: return `(GraphDesc, graph_wf proof)` from parser

This is appropriate only after the parser itself has access to the exact registry and can construct the typed proof. A structural parser cannot prove `graph_wf`; adding a proof field without a resolver would be circular/assumptive. Return raw syntax from `parse_graph_syntax`; have the resolver construct typed evidence; expose the composed result publicly.

## Remaining acceptance gaps

1. Add a closed/fixed structural graph codec implementation and prove parser exact round-trip and accepted-byte canonicality. No V2 source currently implements it.
2. Bind registry manifest identity to the exact immutable work, value-codec, schema/type, and (if custom) graph-codec entries; prove unique, complete/absent lookup behavior.
3. Add schema/type tokens or equivalent constructive equality evidence to resolve existential work signatures and constants. Prove typed wire reconstruction through the prior-node telescope.
4. Add membership evidence to source builder/wiring constructors; spec signatures already sketch membership but types are abstract and current source does not consume them.
5. Define `resolve_graph_syntax` and prove it matches exact parsed labels/wires, rejects dangling/nonprior refs and malformed constants, and preserves the exact outer `(i,o,x)` indices.
6. Compose root and generated entry points over the same format and registry snapshot. Check root graph codec identity can be resolved; current identity module has no graph-codec table.
7. Prove `generate_graph` output has the graph and allocation properties required before append; the current total return type does not provide `graph_wf`/typed resolution evidence (`Kernel.fst:151-159`; brief `:53-59`).
8. Verify the integrated modules with `opam exec -- make -C src/fstar/v2 verify` after implementation. A successful declaration check alone does not discharge admitted codec or resolver lemmas.

## Strongest objection

There is no “small codec trick” that avoids proving schema identity soundness. The graph's bytes carry only first-order names, but the recovery theorem demands values in dependent F* types. If the pinned manifest cannot turn each schema/type identity into the exact existential type witness, parsing and canonicality can be fully proved while P2 remains false. The schema-resolver design is therefore the gate for implementation, not an optional optimization.
