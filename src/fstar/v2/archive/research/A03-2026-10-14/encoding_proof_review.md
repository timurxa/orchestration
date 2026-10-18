# A03 encoding proof review

## Recommendation

Use decoder left inverses for identity and manifest injectivity. Define one
first-order tagged-entry sum, one total key `(tag, encoded identity)`, and one
framed entry codec. Validate duplicate IDs on the original list; only then run
deterministic insertion sort. Store manifest data without proof fields, and
state sortedness/uniqueness as predicates. This keeps proof equality out of
durable data and gives A04 a simple projection target.

## Existing identity evidence and ownership

`WorkflowV2.GraphCodec` already has useful suffix lemmas:

- `codec_identity_decode_encoding_suffix`
- `code_identity_decode_encoding_suffix`
- `operation_identity_decode_encoding_suffix`
- `generator_identity_decode_encoding_suffix`
- `graph_codec_identity_decode_encoding_suffix`
- `work_identity_decode_encoding_suffix`
- `output_identity_decode_encoding_suffix`

These show `dec (enc id @ suffix) == Some (id, suffix)`. The first five
duplicate the same `(length-prefixed name, version, length-prefixed build)`
format. There are no corresponding encoder-injectivity theorems yet.

Do not copy these routines into ManifestCore. A01 assigns both
`ManifestCore` and `GraphCodec` direct dependency on `Kernel`; keep that DAG by
moving shared identity encoders/decoders and their lemmas to Kernel, then have
GraphCodec call them. Kernel already owns all identity record definitions.
Keep graph syntax tags, graph parser, and graph codec laws in GraphCodec.
This is one source of truth and leaves `ManifestCore -> Kernel` and
`GraphCodec -> Kernel`.

Kernel needs encoders/decoders for all primitive identity records, including
currently absent schema, metric, artifact type/store, registry, journal codec,
resolver, root-entry, and any validator/adapter/configuration/allocation-law
IDs added for §2.0. Reuse a generic record-shape codec only if it preserves
each named record type at its API boundary; avoid coercing unlike identity
domains into one untagged record.

## Identity injectivity

Give each identity decoder a suffix result, as current GraphCodec does. Then
prove injectivity by applying the decoder to both equal encodings:

```fstar
val codec_identity_encode_injective : x:codec_identity -> y:codec_identity
  -> enc_codec_identity x == enc_codec_identity y -> Lemma (x == y)
let codec_identity_encode_injective x y h =
  codec_identity_decode_encoding x;
  codec_identity_decode_encoding y;
  FStar.List.Tot.Properties.append_eq_elim h;
  ()
```

The last line is schematic: F* may need `rewrite h` / a local equality
substitution rather than a library append lemma. Core argument is just
congruence of `dec_codec_identity` over equal byte lists, followed by
`Some` injectivity. Define a generic helper for this pattern where F* accepts
polymorphism over a decoder and left-inverse proof; otherwise keep short
per-type wrappers. Do not assert record equality from fields unless the
chosen F* equality encoding requires explicit field lemmas.

For sums, encode a fresh numeric tag before the existing payload encoder and
decode by matching that tag. Prove each tagged decoder suffix roundtrip by
constructor cases. Then prove injectivity by case analysis on both values:
equal tags force the same constructor and payload injectivity; unequal tags
contradict first-byte equality. A generic tagged-ID sum also makes domains
disjoint by construction. This is stronger and easier to audit than relying
on names never colliding across domains.

## Manifest syntax and key

Define `manifest_entry` as a first-order sum, one constructor per identity
domain. Constructor payloads contain identity plus all spec-required metadata
links/versions, represented as identity values, naturals, booleans, bytes,
and schema ASTs. No executable package, proof, closure, or host handle.
Derive `entry_tag` by constructor; derive `entry_id_bytes` using the shared
identity encoders. Define lexicographic byte-list order over `nat` elements,
then:

```fstar
let entry_key (e:manifest_entry) = (entry_tag e, entry_id_bytes e)
let entry_lt (x y:manifest_entry) = entry_key x <lex entry_key y
let NoDuplicateIds (es:list manifest_entry) =
  forall e1 e2. Mem e1 es -> Mem e2 es -> entry_key e1 == entry_key e2
    ==> e1 == e2
let StrictlySorted (es:list manifest_entry) =
  pairwise entry_lt es
```

Keep `registry_manifest` as data `{version; entries}`. Define
`valid_manifest m = NoDuplicateIds m.entries /\\ StrictlySorted m.entries /\\
all_entry_fields_well_formed ...`; do not place proof witnesses in the
record. Per-domain uniqueness can either be one predicate per tag or this
key uniqueness, with a lemma that tag equality identifies the domain.

For sorting, use total lexicographic order with standard finite-list
termination. `canonicalize_entries` first checks `NoDuplicateIds` on input,
returns `None` on a duplicate, else insertion-sorts. Prove:

```fstar
val sort_perm : xs:list manifest_entry -> Lemma (Permutation xs (sort xs))
val sort_sorted : xs:list manifest_entry -> Lemma (StrictlySorted (sort xs))
val sort_idempotent : xs:list manifest_entry
  -> StrictlySorted xs -> Lemma (sort xs == xs)
val sorted_perm_unique : xs ys:list manifest_entry
  -> StrictlySorted xs -> StrictlySorted ys -> Permutation xs ys
  -> Lemma (xs == ys)
val canonicalize_rejects_duplicate : xs:list manifest_entry
  -> duplicate_id xs -> Lemma (canonicalize_entries xs == None)
val canonicalize_exact : xs ys:list manifest_entry
  -> NoDuplicateIds xs -> Permutation xs ys
  -> Lemma (canonicalize_entries xs == canonicalize_entries ys)
```

Prove `sorted_perm_unique` by induction on `xs`: sortedness makes its head
the unique least key in the permutation; remove that same head from `ys`,
then recurse. Unique keys follow from identity-encoding injectivity plus tag
injectivity. If permutation library support is awkward, define a local
`remove_one` and prove permutation/removal lemmas once; do not prove sort
uniqueness by unfolding insertion sort repeatedly.

Important order: duplicate check precedes sorting. Never use `sort` that
silently collapses equal keys or chooses a row. Exact duplicate rows still
reject; otherwise they can conceal two packages claiming one identity.

## Canonical manifest codec

Frame every entry payload with a length. Manifest bytes should include a
format/version tag, manifest version, entry count, then each framed entry.
Use `enc_seq` / `dec_len_seq` pattern already present in GraphCodec; field
codecs must consume exact declared lengths. Give the parser a suffix-returning
form internally and require `[]` at public top-level decode. Thus concatenated
fields cannot alias, and malformed/unknown tags reject.

Useful theorem shape:

```fstar
val entry_decode_encode_suffix : e:manifest_entry -> suffix:bytes
  -> Lemma (dec_entry (enc_entry e @ suffix) == Some (e, suffix))
val entries_decode_encode_suffix : es:list manifest_entry -> suffix:bytes
  -> Lemma (dec_entries (enc_entries es @ suffix) == Some (es, suffix))
val manifest_decode_encode : m:registry_manifest -> valid_manifest m
  -> Lemma (decode_manifest (encode_manifest m) == Some m)
val manifest_encoding_injective : m1 m2:registry_manifest
  -> valid_manifest m1 -> valid_manifest m2
  -> encode_manifest m1 == encode_manifest m2 -> Lemma (m1 == m2)
```

The roundtrip can hold for every syntactically encodable manifest; sortedness
is needed for canonical construction/uniqueness, not for parser recovery.
Injectivity follows by decoder congruence and `Some` injectivity. If validity
uses proof-carrying records, `m1 == m2` can be blocked by proof irrelevance or
record equality; keep proofs in predicates and state data equality explicitly
as version and entries equality.

Prove exact canonical order separately: `canonicalize_entries` output is
strictly sorted; its output is invariant under input permutation; already
sorted input is a fixed point. Then equal canonical encodings imply equal
entry lists and all metadata, not just equal IDs.

## Registry identity consequence

Use exact canonical bytes as logical `RegistryIdentity`, or an injective
wrapper around them. If representation must remain in Kernel's current
`{registry_name; registry_version; registry_build}` shape, it cannot
identify an arbitrary full manifest injectively unless `registry_build`
stores the full canonical bytes and the other fields are fixed/derived.
Treat a digest as lookup index only; digest equality alone cannot prove
manifest equality. Then `manifest_identity_injective` is a direct composition
of `manifest_encoding_injective` and byte-identity injectivity. Update
`pinned_registry_identity`, `manifest_named_by`, and run-start consumers to
the exact key; A04 still proves package-table projection and P0 coherence.

## Lookup, closure, projection

After duplicate rejection, prove tagged lookup uniqueness by list induction:

```fstar
val lookup_unique : id:tagged_identity -> es:list manifest_entry
  -> NoDuplicateIds es -> lookup id es == Some x -> lookup id es == Some y
  -> Lemma (x == y)
val reference_closed : m:registry_manifest -> valid_manifest m
  -> Lemma (forall ref in refs(m). lookup ref m.entries == Some target
            / target.tag == ref.expected_tag)
```

Do not hide closure in sorting or decoder success. Validate references
against the unique-ID predicate before producing a valid manifest; prove
each schema/link category with a shared `lookup_unique` lemma.

Keep A03 projection first-order and independent of Bundle. Define exactness as
two directions: every manifest row has exactly one matching first-order
projection row, and every projection row occurs exactly once in the manifest.
Prove it from a relation or finite-map view; A04 supplies the relation between
these projection rows and actual executable package tables. Do not import
Bundle or claim closure/package equality in ManifestCore.

## Limits

`bytes = list nat` means proofs establish injective canonical representation
over mathematical natural-number lists. They do not establish octet bounds,
UTF-8 validity, host file encoding, cryptographic hash properties, or a
concrete package binary matching its identity. Keep those claims outside A03.
