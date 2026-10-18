# A03 ManifestCore property review

> Historical adversarial snapshot from before the current ManifestCore proof
> integration completed. Findings about then-missing validation/ordering
> guided later work; they are not a current-source status report. Current
> source and trust status are summarized in `stdlib_axiom_audit.md` and the
> A03 node summary.

Scope: adversarial read of `src/WorkflowV2.ManifestCore.fst` against the
manifest contract in `implementation_spec.md` §2.0. No source or canonical
state files changed for this review.

## Critical findings

1. **No accepted/canonical manifest predicate is wired into decoding.**
   `decode_manifest_data` parses framing and returns any `registry_manifest`;
   it does not check format version, field shape, unique identities, closed
   references, or canonical row order. The helper predicates exist separately,
   but there is no `manifest_wf`/`decode_canonical_manifest` composing them.
   For example, duplicate an otherwise valid entry, reverse two valid rows,
   use format version `999`, or give a code row the wrong field variants: each
   remains decodable. This is **A03**. P0/A04 cannot repair an ambiguous
   canonical identity at the wire/parser boundary.

2. **Raw list order is identity; required canonical sorting is absent.**
   `encode_manifest_data` calls `enc_manifest_entries` on the input order.
   `manifest_data_encoding_injective` proves distinct ordered records have
   distinct encodings, not that permutations normalize to the same canonical
   manifest. Thus the same logical package table in a different order gets a
   different `RegistryIdentity`, contrary to §2.0's tag-then-identity sort.
   **A03** must add a checked canonicalizer or require/prove sortedness in the
   canonical manifest constructor, plus sorted-permutation uniqueness.

3. **Contract references are not included in closure.**
   `manifest_value_references` collects only `ManifestIdentityValue`; it
   skips `ManifestContractValue`. Consequently an operation can refer to a
   nonexistent validator/adapter/configuration contract, and schema rows can
   name nonexistent denotation laws, while `manifest_entries_links_closed`
   still succeeds. There are no contract entries in `manifest_identity`.
   **A03/A04 boundary:** A03 must state a closed typed contract-reference
   relation (or explicitly mark these as unresolved package slots); A04/P0
   must prove every such token selects exactly one real proof-bearing package.
   Current A03's unqualified “exact cross-reference closure” is too strong.

4. **Plain and indexed codec references are indistinguishable.**
   `is_indexed_codec_value` is currently identical to `is_codec_value`.
   Therefore, for example, a `CodeIdentity` row accepts a plain codec in its
   output slot, and an `OperationIdentity` row accepts a plain result codec.
   Conversely, any codec identity may fill a plain input slot. The mode marker
   only describes a codec declaration row; it does not constrain references
   to it. This is **A03** for reference-shape validity and **A04/P0** for
   binding the referenced codec identity to the exact package/mode. Do not
   claim codec-mode coherence until both are checked.

## Other gaps / boundaries

| Concrete case accepted by current syntax/predicates | Finding | Owning milestone |
|---|---|---|
| `ManifestSchemaSyntaxValue [999]` or arbitrary non-schema bytes in a schema row | Field shape checks only the constructor; no schema parser, AST validity, canonical schema syntax, or denotation law check exists. | **A05** parses and proves schema syntax/denotation; A03 should keep the boundary explicit. |
| Code input codec points to an indexed codec; output schema differs from referenced codec schema; generator graph codec schemas disagree with input/result schema | Identity refs are checked for a coarse tag and presence only. The row predicates do not equate referenced entries' metadata. | **A04/P0** exact package/codec/schema coherence, with **A05–A07** schema denotation/resolution. |
| An empty manifest or one missing a root entry | No aggregate required-domain/presence conditions are defined here. | **A04/P0** projection from actual package tables entails completeness; A03 may expose a validity predicate but should not invent bundle-dependent membership. |
| A syntactically parsed but noncanonical byte string | Current theorem proves `decode(encode(m)) = m` and encoding injectivity. It does not prove `encode(decode(b)) = b` for every accepted `b`, nor require a canonical parser. | **A03** needs accepted-byte canonicality/rejection theorem for the manifest codec. |
| Two identities share the same textual name/version/build fields in different identity domains | This is correctly distinguished by the outer tag; `manifest_identity` constructors and encodings keep domains disjoint. Same `schema_identity` payload in family vs rule has tags 8 vs 9. | No defect. Keep duplicate uniqueness over tagged identity, not raw payload. |
| Two entries have exactly equal tagged IDs (including equal duplicate rows) | `entries_ids_unique` would reject these if called, but the decoder does not call it. It does not silently deduplicate. | Predicate is a useful A03 component; wire acceptance remains A03 gap #1. |
| An identity-valued field points to an absent ID | `manifest_entries_links_closed` detects this, but only if explicitly required; decoder does not call it. | A03 validator composition. |

## What is already sound/useful

- Tagged identity encoding has a decoder-with-suffix round-trip, and the
  derived injectivity theorem distinguishes identity domains.
- Entry/value/manifest encoders have encode-then-decode theorems and framed
  parsers reject trailing bytes at the outer manifest boundary.
- Exact duplicate IDs have a check that rejects them; no winner is chosen.
- Field-list arity and value constructors are checked by each row's pattern.
- Identity references have a first-order closure checker.

These facts establish syntax round-trip and some reusable predicates. They do
not yet establish “valid manifest,” canonical ordering, exact projection, or
package coherence. The completion claim in A03 should wait for one explicit
accepted-manifest definition and the theorem that every accepted wire is its
unique canonical encoding.

## Recommended A03 acceptance boundary

Define one predicate/constructor for canonical manifest data that checks:

1. supported format version;
2. exact per-domain field shape, including plain/indexed mode at every codec
   reference;
3. no repeated tagged IDs;
4. all identity and typed contract references are closed (contract resolution
   may be a manifest-level table or an explicit A04 package relation);
5. entries sorted by `(domain_tag, canonical_identity_encoding)` and no
   duplicate key;
6. decoder accepts only that form, with `encode(decode(bytes)) = bytes`.

Keep schema AST parsing and denotation in A05 and exact projection to runtime
package tables in A04/P0. Those are separate semantic obligations, not reasons
to leave the A03 byte-level canonicality undefined.
