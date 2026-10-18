# A03 adversarial manifest review

**Scope:** adversarial review of the proposed first-order manifest contract against implementation-spec §2.0 and the registry laws in §2.0. No code or canonical state files changed. Recommendations below are proof obligations, not claims that A03 has already established them.

## Main result

A manifest must be treated as a canonical, typed finite map whose rows carry complete package-selection metadata. “Sorted list” alone is insufficient. The validity predicate must jointly enforce: unique tagged keys, complete required fields, correctly typed/exact links, canonical order, and a bijection to the first-order package projection. A04 then binds that projection to executable packages. Weaker versions admit concrete counterexamples below.

## Counterexamples and required guards

### 1. Duplicate ID in one tagged domain

Take two `Operation` rows with the same `OperationIdentity`, but distinct `validator_id` or `maximum_charge`. A lookup by operation identity now has two candidates. A stable sort may preserve both; choosing first/last makes source order semantic. Even two byte-for-byte identical rows must be rejected: they represent two package claims for one ID, contrary to the spec’s “reject duplicate IDs” rule.

**Guard:** define key as `(entry_tag, canonical_identity_bytes)` and require pairwise key inequality over the original entry list before sorting. Duplicate test compares keys, not full rows. Sorting must preserve multiplicity; it must never deduplicate.

### 2. Same payload across different domains

A `Code` identity and an `Operation` identity may have equal `(name, version, build)` fields. This is not a collision if domains are disjoint. A global untagged ID map would either reject a valid pair or resolve one as the other. Conversely, if the serialized key omits the tag, the encodings collide.

**Guard:** encode a distinct constructor tag into every entry key and wire representation. Define lookup over a tagged identity (or expected domain plus identity); prove equal keys imply equal tags before deriving same-constructor payload equality. Per-domain uniqueness is the specification; global raw-field uniqueness is not.

### 3. Omitted required link / metadata

An operation row containing an operation ID and request codec but no result codec, validator, adapter/configuration, metric, or maximum charge could pass a closure predicate that only checks links which happen to be present. Similarly, a generator row can omit allocation-contract identity, or an artifact type can omit its interpretation/projection-law link. No decoder can infer an omitted field from an otherwise well-formed shorter representation unless the constructor grammar requires it.

**Guard:** make each entry constructor carry every §2.0-required field at the F* type level; do not model required links as optional lists. Define completeness per constructor. Exact first-order projection must compare every field, not just entry key. A03 can prove syntax-level completeness and projection-relation shape; A04 proves actual packages supply those fields.

### 4. Existing but misdirected link

Suppose an operation’s `request_codec_id` resolves to a valid `Codec` row and its `result_codec_id` also resolves, but the validator/result schema or adapter configuration is for a different operation signature. Or a generator references an existing graph codec with a different input/output schema. Mere existence plus expected tag does not prove the link is semantically the one selected by the package.

**Guard:** separate `LinkClosed` (exactly one target with expected tag) from `LinksCoherent` (all linked IDs and schema expressions satisfy the entry’s declared signature equations). For example, generator graph-codec input schema must equal generator input schema; operation validator schema and codec schemas must equal operation request/result schemas; artifact reference codec, store, interpretation, and projection law must agree on the same artifact schema. A03 proves only first-order equations; carrier/function coherence remains A04/P0.

### 5. Noncanonical ordering

If `encode_manifest` serializes an arbitrary input list directly, permutations `[a;b]` and `[b;a]` produce different identities for the same package set. If decode accepts either but the registry key uses the original bytes, lookup and restart identity depend on construction order.

**Guard:** define `valid_manifest` to require strict canonical order; define canonical construction by duplicate-check first, then deterministic sort. Prove sort preserves the exact multiset, yields strict order, is invariant under input permutation, fixes already-sorted lists, and has unique sorted representative per permutation class. Public canonical decode should reject trailing bytes and reject noncanonical order (or decode then re-encode and require byte equality). Do not silently normalize bytes at one boundary while retaining the original bytes as identity.

### 6. Ambiguous or partial lookup

With two same-tag rows sharing identity but different metadata, `lookup` may return either row. A lemma saying “if lookup returned `x`, then `x` is in the list” does not establish uniqueness. A lookup that ignores the tag can also return a `Codec` when asked for an `ArtifactStore` with identical raw fields. A valid registry identity with no corresponding manifest makes `manifest_named_by` partial unless its domain excludes such identities.

**Guard:** state exact-one lookup: for every reference required by a valid manifest there exists a row with matching tagged key, and any two such rows are equal as data. For arbitrary byte keys, use `option RegistryManifest`; successful lookup carries/derives `ValidCanonicalManifest` and exact identity equality. State the spec’s identity laws only over valid registry identities, or prove lookup total over the chosen identity subtype.

### 7. Encoder equality and injectivity

Naive concatenation can alias fields: `("a","bc")` and `("ab","c")` produce the same bytes without lengths/delimiters. Dropping the tag aliases constructor domains. Encoding only entry IDs aliases two rows whose metadata differs. Proving decoder-left-inverse for identity does not by itself prove arbitrary byte strings canonical; it proves the encoder is injective when decoder is a function and equality is substituted through it.

**Guard:** length-frame every variable-length field and entry; encode tags and versions explicitly. Prove typed suffix left-inverse for every primitive identity, tagged identity, entry, entry sequence, and manifest. Derive injectivity by decoder congruence and `Some` injectivity. Prove manifest injectivity over canonical data, including all metadata fields. Keep validity/proof witnesses outside records, or state data equality explicitly (`format_version` and `entries`) so proof-field equality/irrelevance cannot obscure the claim. Current `bytes = list nat` proofs establish only mathematical-list encoding properties, not octet, UTF-8, file, or digest properties.

### 8. Projection relation too weak

A one-way relation such as “every package has some matching manifest row” permits extra rows, duplicate rows, or rows with stale metadata. The reverse one-way relation permits unrepresented packages. Matching only identities misses changed codec links, versions, charge bounds, or schemas. Any of these breaks `pinned_manifest_exact` or allows package selection to differ while the manifest key stays the same.

**Guard:** define projection exactness as an identity-preserving bijection between package-projection rows and manifest rows: every package contributes exactly one complete row; every row is contributed by exactly one package; matched rows agree on every field; both sides preserve tagged-key uniqueness. In A03, formulate this over first-order projection data only. In A04, prove the actual `noeq` package tables induce that exact projection without claiming closure equality.

## Recommended predicate / theorem factoring

Keep predicates separate so counterexamples have precise failure points:

```fstar
UniqueTaggedKeys entries
RequiredFieldsWellFormed entries
CanonicalEntryOrder entries
LinkClosed manifest
LinksCoherent manifest
ValidCanonicalManifest manifest
ProjectionBijection projection manifest
```

`ValidCanonicalManifest` should imply the first five relevant data-only conditions; `ProjectionBijection` belongs to the first-order projection relation. Useful theorem shapes:

```fstar
lookup_exact : ValidCanonicalManifest m -> RequiredRef r m
  -> exists! e. entry_key e == r /\ Mem e m.entries
lookup_tagged_unique : UniqueTaggedKeys es -> ...
  -> lookup r es == Some e1 -> lookup r es == Some e2 -> e1 == e2
canonicalize_duplicate_rejects : duplicate_key es
  -> canonicalize es == None
canonicalize_permutation_invariant : Permutation xs ys
  -> canonicalize xs == canonicalize ys
canonicalize_fixed_point : CanonicalEntryOrder es
  -> canonicalize es == Some es
manifest_encoding_injective : ValidCanonicalManifest m1
  -> ValidCanonicalManifest m2
  -> encode_manifest m1 == encode_manifest m2
  -> manifest_data_equal m1 m2
projection_exact_both_ways : ProjectionBijection p m
  -> (forall row. Mem row p <==> exists! entry. Mem entry m.entries /\ row_matches entry row)
```

For `manifest_identity_injective`, compose canonical manifest encoding injectivity with exact-byte identity equality. For `manifest_lookup_identity_exact`, use only registry identities in the valid canonical identity domain; arbitrary bytes must yield `None` unless they decode to a valid canonical manifest.

## Spec alignment and boundary

This matches §2.0’s requirements: duplicates rejected before canonical sorting; every cross-reference resolves to exactly one member; the manifest is a projection, not a second independently editable registry; projection exactness is two-way; exact canonical bytes are the logical identity; and A04/P0 supplies executable package projection and restart-stable association. The boundary matters: A03 must not claim that a first-order row alone proves its referenced F* carrier, callback, validator, or host artifact interpretation. It must, however, make omission, duplicate selection, misdirected links, and byte aliases impossible in its own syntax and proofs.
