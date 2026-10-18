# A03 manifest contract coverage

> Historical reviewer snapshot from before the current ManifestCore proof
> integration completed. Its “missing” findings describe that earlier source
> state and guided later work; do not read them as a current audit. Current
> source and trust status are summarized in `../stdlib_axiom_audit.md` and the
> A03 node summary.

**Scope:** read-only audit of `WorkflowV2.ManifestCore.fst`, the A03 row in
`state/work_dag.md`, and the manifest/P0 contract in `implementation_spec.md`.
This report makes no source or DAG changes.

## Finding

A03 has useful, checked *syntax codec* groundwork, but its current source does
not yet meet A03's stated acceptance condition or the manifest portion of P0.
In particular, the types currently allow arbitrary lists to be called a
`registry_manifest`; the predicates that could reject malformed lists are not
connected to construction, decoding, or a canonical identity. Encoding is
injective over syntax as written, but there is not yet a canonical manifest
encoding/ordering or an exact projection from a pinned package table.

## Implemented

- `manifest_identity` has 12 disjoint tags (code, operation, generator,
  codec, artifact type/store, charge metric, graph codec, schema family/rule,
  resolver, root entry); its decoder and suffix roundtrip are in
  `WorkflowV2.ManifestCore.fst:12-146`. The derived injectivity theorem is at
  `:148-153`.
- Contract references are tagged by contract kind and have a suffix
  roundtrip/injectivity (`:155-233`). This is useful syntax, not proof that a
  referenced contract is the package's actual contract.
- Generic manifest values, framed field lists, entries, entry lists, and
  versioned manifest data have encoders/decoders and encode/decode roundtrips
  (`:235-375`, `:569-719`). The manifest decoder rejects trailing bytes
  (`:671-686`). These lemmas establish encode-to-decode and syntax injectivity;
  they do not establish accepted-byte canonicality.
- There are Boolean field-shape predicates for the 12 entry kinds
  (`:383-503`), recursive duplicate-ID detection (`:513-527`), and a basic
  identity-reference existence check (`:540-567`). They are presently
  disconnected helpers; no `ManifestValid` predicate or smart constructor
  requires them.
- `JournalCodecIdentity` is intentionally absent from the manifest tag sum.
  This is consistent with spec §4.1, which treats it as immutable replay
  context rather than a pinned application-package row. Kernel identity
  encoding for it can remain separate.

## Missing, weak, or mis-scoped

1. **No canonical order or canonical-manifest decoder law.** `encode_manifest_data`
   serializes `manifest_entries` in supplied list order (`:666-669`). There is
   no sorting, sortedness predicate, normalizer, duplicate-before-sort
   rejection, or theorem that every accepted byte string equals the encoding
   of its decoded manifest. Thus current “manifest encoding” is a reversible
   syntax encoding, not the spec's canonical encoding (spec §2.0, lines
   147-175; A03 row).
2. **Duplicate rejection is not enforced.** `entries_ids_unique` returns a
   Boolean, but neither encoding, decoding, nor a manifest constructor checks
   it. Identical duplicate rows and conflicting rows both remain accepted
   syntax. There are no characterization lemmas connecting the Boolean to
   lookup uniqueness or rejection.
3. **Field validation is only shallow shape checking.** `manifest_entry_fields_well_formed`
   checks list length and broad value constructors, but not exact expected
   identity domains at each position, identity-to-codec role, or a matching
   entry for that identity. In particular `is_indexed_codec_value` is
   identical to `is_codec_value` (`:383-391`); schema-family checks accept any
   family token, and `ManifestSchemaSyntaxValue` remains uninterpreted bytes.
   Generic `ManifestBytesValue`, `ManifestTextValue`, and arbitrary identity
   values also allow unstructured fields that do not belong to any row shape.
4. **Cross-reference closure is weaker than the spec.** The helper only
   collects `ManifestIdentityValue` references and asks whether some row with
   that identity exists (`:540-567`). It omits contract references; does not
   require the referenced tag to be the expected tag; and does not prove a
   unique target. It also does not prove cross-table coherence such as an
   operation's metric equaling the pinned run metric, or that generator and
   root graph-codec links resolve to the corresponding package signatures.
5. **No manifest identity API is composed here.** There is no definition
   identifying a validated, normalized manifest with its exact encoded bytes,
   nor a theorem that two such identities equal only when the manifests are
   equal. Kernel's byte-wrapper injectivity is necessary groundwork, not the
   `manifest_identity`/`manifest_named_by`/bundle laws in spec §2.0 and P0.
6. **No package-table projection relation exists in this module.** A03's DAG
   row currently says it will define the projection relation. Yet the spec
   correctly assigns the *actual* two-way package-to-row correspondence to
   `manifest_projection_exact` and P0 (spec §2.0, lines 177-246). There is no
   package/bundle input in `ManifestCore`, so this part cannot be established
   here; A04 is the appropriate owner. A03 can define a first-order projection
   relation's syntax if needed, but should not claim it is exact until A04
   connects it to package tables.
7. **Schema bytes are deliberately not schema proofs.** The schema payload is
   opaque bytes, without AST parsing, normalization, or denotation. This is a
   correct A03/A05 boundary if documented: A03 commits to exact payload bytes;
   A05 parses the restricted AST and proves its schema laws. Do not label
   these bytes a checked canonical schema expression before A05.
8. **Row domain details are incomplete relative to the spec.** The field
   shapes do not distinguish value vs indexed codec roles; the codec mode
   marker selects a shape but the “indexed” identity field is not different
   from a plain codec identity. Several fields are generic `contract_identity`
   tokens without a typed package/proof association. This is acceptable as
   first-order naming only if A04 proves the exact association and the
   manifest contract says what each token denotes.

## A03 acceptance and dependency recommendation

Keep A03 as a small, package-independent first-order syntax module. Its
proofable contract should be:

1. Define disjoint tagged identities and *row-specific typed syntax* for the
   required metadata. Prefer a sum of entry records over a generic value list;
   if the generic list remains, give each row a total exact validator and make
   valid construction/decoding require it.
2. Define a validity predicate covering exact row shape, unique tagged IDs,
   typed reference domains, closure, and deterministic canonical ordering.
   Reject duplicates before normalization; never deduplicate.
3. Define one canonicalizer/decoder boundary: either normalize valid unique
   entries by `(tag, canonical identity bytes)` before encoding, or accept only
   already sorted entries. Prove sortedness/order uniqueness and
   encode/decode roundtrip, plus accepted-byte canonicality (decode succeeds
   only for the unique encoding of the returned manifest).
4. Define registry identity as the exact canonical byte string, then prove
   identity injectivity. Keep digest identity as a later concrete refinement
   with its own collision-resistance condition.
5. Keep schema AST parsing/denotation out of A03: the manifest carries exact
   canonical schema syntax data; A05 establishes the AST/parser/canonical
   expression boundary.
6. Do not put function closures, host implementations, or proof terms in
   serialized rows.

Dependency split: **A03** proves the above syntax, validity, exact-byte
canonicality, and identity laws. **A05/A06** prove schema syntax/denotation and
declared equality. **A07** consumes manifest schema syntax. **A04/P0** alone
proves both directions of exact projection to the executable bundle, unique
identity-to-package lookup, cross-table package coherence, and restart-stable
association. This preserves the acyclic order and prevents a first-order
manifest helper from being mistaken for P0.

The A03 work-DAG row should consequently split its current “projection
relation from package tables” phrase: A03 may define the first-order
projection *shape*, while A04 proves the actual package-table projection. Its
acceptance should explicitly require canonical accepted-byte uniqueness and
duplicate/link rejection; those are not implied by the present codec
roundtrips.
