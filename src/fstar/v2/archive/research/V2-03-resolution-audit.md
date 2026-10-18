# V2-03 typed-resolution audit

Read-only audit of current `WorkflowV2.Identity`, `Graph`, `Kernel`, and
`implementation_spec.md` P0/P2. No implementation files changed.

## Verdict

Current code proves only local facts about supplied records and a successful
list lookup. It does **not** bridge canonical graph bytes to one typed graph
whose work, codecs, constants, and graph codec are all selected by the exact
manifest named at run start. P0/P2 remain open. Main missing bridge is not byte
round-trip: it is equality between each record used to encode/validate/run and
the unique record resolved from the pinned snapshot, including existential
indices.

## Existing facts versus open assumptions

### Work references

- `durable_ref_of_work` derives one first-order key from a `Work` and its input
  and output codec identities (`Identity.fst:50-69`). `durable_work_ref_eq_sound`
  establishes structural key equality (`:71-77`). This removes free pairing of
  an executable value with a separately supplied key.
- Registry entries existentially package heterogeneous `work i o`
  (`Identity.fst:84-90`). Lookup is executable over a list (`:106-135`). The
  exactness lemma proves a successful result has the requested derived key and
  the registry's uniqueness field bounds matching entries (`:139-151`).
- This does not prove the graph's in-memory `Work` is the returned package.
  `typed_graph_witness` receives `pinned_registry_bundle`, but constructor does
  not include lookup or membership evidence (`Graph.fst:450-467`). Its comment
  explicitly leaves this link open. `add_node` accepts arbitrary `work` and no
  `WorkMember` (`Graph.fst:348-366`), while spec requires `WorkMember` in
  `add_node` (`implementation_spec.md:331-344`) and documents this mismatch
  (`:366-373`).
- The uniqueness facts are fields of registry records, not proved from a
  closed registry constructor (`Identity.fst:100-104, 172-176`). They are
  potentially legitimate construction obligations, not the desired theorem
  itself; but current F* source supplies no closed constructor/presence proof.

### Value codecs and indexed constants

- `packed_codec` existentially stores plain or indexed codecs
  (`Identity.fst:153-162`); resolver compares codec identity, and successful
  lookup lemma proves returned package carries that key (`:178-222`). This is
  useful but conditional on uniqueness field and says nothing about a constant
  wire's selected package.
- Wire constructors carry the actual codec record and value, including
  root-indexed values (`Graph.fst:163-182, 272-293`). This proves that the
  builder-side syntax is the encoding of that supplied value at exact `x`.
- No `CodecMember`/`IndexedCodecMember` evidence exists in source. A wire
  derivation can use an unregistered codec, or a codec with same identity as a
  registry entry but different implementation. Spec now declares those
  membership relations and requires them for constant constructors
  (`implementation_spec.md:279-305`), but code does not.
- For decoded bytes, P2 must resolve identity to one package, distinguish
  `PlainCodec a` from `IndexedCodec i A`, decode with that package, and build
  the corresponding typed derivation. Indexed decode must use the graph's exact
  root `x`; `decode_indexed x bytes : option (A x)`. Canonicality then follows
  from that resolved codec's law, not from an unrelated codec passed by the
  builder.

### Pinned bundle / manifest

- `pinned_registry_bundle` merely contains an arbitrary `registry_identity`,
  work registry, and codec registry (`Identity.fst:224-232`). Its own comment
  says there is no relation between identity and contents. Spec requires a
  manifest derived from actual registries and root entry point, equal to the
  identity named in `RunStarted` (`implementation_spec.md:106-115`).
- Therefore uniqueness within one list is not restart exactness. A host can
  reload a different registry under same nominal identity unless manifest
  binding and host reload refinement are proved. Do not use digest equality as
  semantic equality without the spec's collision premise.

### Graph codec and root entry point

- `graph_codec` record has encode/decode, roundtrip, canonicality
  (`Kernel.fst:126-136`). These laws are for the supplied record only. There is
  no global graph-codec registry/resolver in `Identity.fst`: `packed_codec`
  only has `PlainCodec` and `IndexedCodec` cases (`:153-157`).
- A child generator embeds a `graph_codec` directly in `generator_ref`
  (`Kernel.fst:151-159`). After exact `GeneratorRef` resolution this can select
  the child codec, but no theorem ties its `graph_codec_id` to a registered
  implementation/manifest entry. Root `RunStarted` carries a graph-codec
  identity; there is no root-entry-point record/resolver in source. Spec names
  root entry relation and graph-codec manifest binding as open
  (`implementation_spec.md:106-115, 1067-1070`).
- `GraphCodec.roundtrip` accepts any raw `GraphDesc` and returns the same raw
  descriptor; it carries no `graph_wf` or typed witness (`Kernel.fst:126-135`).
  This is byte inversion only. It does not prove decoded graph is well-typed,
  registered, or executable. Spec correctly requires caller to prove
  `graph_wf registry g` after decode and P2 to reconstruct typing evidence
  (`implementation_spec.md:375-399, 493-503`).

### Generator boundary

- Type split is coherent: `generate_graph x allocation` returns
  `graph_desc input output x`, while `GenerateWork` remains `work input output`
  (`Kernel.fst:151-170`). Spec says child graph's output wire supplies eventual
  `output x`, and graph is committed as control transition, not
  `NodeCompleted` (`implementation_spec.md:347-352`).
- Still open: no membership proof binds the selected generator to bundle;
  no manifest theorem binds its `generator_ref_id`, schemas, and embedded
  `graph_codec`; no P2 theorem proves graph bytes decode under that exact codec
  to a typed graph equal to generator output. `generate_graph` totality and
  type are declarations, not evidence of registry pinning or extracted-host
  identity.

## Smallest useful bridge

Avoid a second durable reference or unconstrained equality of functions. Build
lookup evidence around exact existential packages, and make every accepted
graph witness carry those results.

```fstar
// Membership is proposition over exact package, not just matching key.
type WorkMember (r:pinned_registry_bundle) (#i:Type0)
    (#o:i -> Type0) (w:work i o) : Type =
  exists package:packed_work.
    resolve_global_work r.bundle_work_registry (durable_ref_of_work w)
      == Some package /\
    package == PackedWork w

type CodecMember (r:pinned_registry_bundle) (#a:Type0)
    (c:codec a) : Type =
  resolve_global_codec r.bundle_codec_registry c.codec_id
    == Some (PlainCodec c)

type IndexedCodecMember (r:pinned_registry_bundle) (#i:Type0)
    (#A:i -> Type0) (c:indexed_codec i A) : Type =
  resolve_global_codec r.bundle_codec_registry c.indexed_codec_id
    == Some (IndexedCodec c)

val resolve_work_for_ref : r:pinned_registry_bundle ->
    key:durable_work_ref ->
    Tot (option (i:Type0 & o:(i -> Type0) & w:work i o &
      durable_ref_of_work w == key))

val resolve_codec_for_wire : r:pinned_registry_bundle ->
    key:codec_identity -> Tot (option packed_codec)
```

F* equality of noeq records/functions may make the displayed `package ==`
unusable. Equivalent safer shape: `WorkMember` is an inductive/list-membership
proof whose `Here` constructor carries the exact `PackedWork w`; prove its
derived key equals graph label. Or have `add_node` obtain `w` from resolver and
return the resolved existential as authoritative typed value. Do not fake
existential type equality from codec-key equality alone.

Then extend typed wire derivations:

```fstar
| ConstantPlainTyping : c:codec a -> CodecMember registry c -> v:a
    -> wire_typing_witness ...
         (ConstantWire c.codec_id (c.encode v)) ...
| ConstantIndexedTyping : c:indexed_codec i A
    -> IndexedCodecMember registry c -> v:A x
    -> wire_typing_witness ...
         (ConstantWire c.indexed_codec_id (c.encode_indexed x v)) ...

| TypedNode : work:work a b -> WorkMember registry work
    -> input:wiring ... (fun _ -> a)
    -> ... // extend dependent output context with b(input_value)
```

For decoding, prove resolver-directed typing, not merely builder constructor
typing:

```fstar
val decode_constant_sound : r:pinned_registry_bundle -> x:i ->
    key:codec_identity -> bytes:Bytes ->
    decode_constant r x key bytes == Some (fam, value) ->
    (member:IndexedCodecMember r codec_for_fam &
     codec_for_fam.decode_indexed x bytes == Some value &
     bytes == codec_for_fam.encode_indexed x value)

val resolve_work_ref_exact : r:pinned_registry_bundle ->
    key:durable_work_ref -> resolve_work r key == Some packed ->
    packed_work_ref packed == key /\
    // unpack result preserves exact existential input/output indices;
    // no cast from first-order schema identity.
    resolved_semantics packed
```

Registry uniqueness plus exact lookup gives same package for repeated lookup
within one immutable list. Separate manifest theorem must bind the list contents
to `bundle_identity`, and host reload theorem must preserve that exact bundle.

For graph codecs add a pinned resolver (or equivalent manifest membership
relation for embedded generator/root codecs):

```fstar
type packed_graph_codec : Type =
  | PackedGraphCodec : #i:Type0 -> #o:(i -> Type0)
      -> graph_codec i o -> packed_graph_codec

val resolve_graph_codec : bundle -> graph_codec_identity
  -> Tot (option packed_graph_codec)

val graph_decode_typed : bundle -> x:i -> codec_id -> bytes ->
  Tot (option (g:graph_desc i o x & graph_wf bundle g))

val graph_codec_resolution_exact : ...
  decode_typed bundle x id bytes == Some (g,pf) ->
  resolved_graph_codec bundle id is codec used by pf /\
  canonical re-encoding bytes == encode_graph resolved x g
```

Root entry point must pin `(input codec, root GraphCodec i o, output family,
registry bundle)` as one typed package; `RunStarted` identity resolves exactly
that package. Generator `WorkMember` then pins embedded `GeneratorRef` and its
GraphCodec together. A standalone graph-codec registry is optional only if the
manifest relation and root entry point still resolve exact codec implementation.

## Required bridge theorem order

1. `identity_eq_sound_complete`: structural equality equivalent to full identity
   field equality; no digest-as-definition inference.
2. `registry_manifest_exact`: bundle identity resolves to exact contents; closed
   constructor proves work/codec key uniqueness. Host restart premise reloads
   same manifest.
3. `resolve_work_sound_unique`: successful key resolution returns one exact
   existential `work i o`, preserving both indices and executable value;
   missing key fails closed.
4. `resolve_codec_sound_unique`: plain/indexed constructor tag, family indices,
   codec implementation, and canonical laws preserved; no cross-kind identity
   collision.
5. `wire_decode_typed`: every constant bytes node resolves through same bundle;
   indexed bytes decode at exact root `x`; successful decode yields syntax
   derivation and canonical re-encoding.
6. `graph_codec_decode_sound`: selected graph codec decodes/re-encodes bytes;
   then derive `typed_graph_witness` by resolving every label/constant. Roundtrip
   alone does not imply `dag_wf`.
7. `generator_graph_commit_exact`: resolved GeneratorRef applied to reconstructed
   input and ledger allocation yields exact descriptor bytes encoded by its
   resolved graph codec; after commit, recovery uses bytes and no regeneration.

## Strongest objections

- `global_registry_unique`/`global_codec_unique` are proof fields; uniqueness
  is assumed for any supplied registry record, not derived by current code.
  P0 needs a closed registry builder/inductive representation or the exact
  finite-list uniqueness proof at construction.
- Current work resolver exactness proves key equality, not across-registry
  manifest identity, not that graph witness work is lookup result, and not
  actual extracted code build identity. These are distinct obligations.
- `graph_codec` laws do not include `graph_wf`; a perfectly canonical encoding
  can round-trip a malformed graph. Typed graph decode must validate after
  decode and fail closed.
- Current global codec registry treats plain and indexed codecs as one identity
  space (`Identity.fst:153-175`), which is fine only if uniqueness rejects same
  identity across constructors. State this as a proved invariant, not an
  unstated convention.
- F* registry package stores functions in process memory. Identity records and
  key comparisons cannot prove a host binary loaded the same implementation
  after restart; keep host reload/build binding as explicit P0/P13 premise.

## Source anchors

- `src/fstar/v2/src/WorkflowV2.Identity.fst:50-77` derived key and equality.
- `.../Identity.fst:84-151` packed work and conditional resolver exactness.
- `.../Identity.fst:153-232` codec registry, uniqueness field, unbound bundle.
- `src/fstar/v2/src/WorkflowV2.Kernel.fst:90-136` codec/graph-codec laws;
  `:151-170` generator/work type split.
- `src/fstar/v2/src/WorkflowV2.Graph.fst:163-182` wire derivations;
  `:450-482` typed graph witness without registry links.
- `src/fstar/v2/implementation_spec.md:106-115` manifest obligation;
  `:279-344` membership API; `:381-399` first-order persistence and P2 gap;
  `:493-503` exact indexed constants/generator pinning;
  `:1009-1025` P0/P2 required proofs.

