# A03 independent acceptance audit

**Date:** 2026-10-14
**Status:** accepted and committed as `09ed6ea`.

This audit compares A03's task brief and implementation-spec §2.0 against the
current `WorkflowV2.Kernel`, `ManifestCore`, and consumers. It separates
first-order syntax obligations from A04/P0 package binding and A05 schema
denotation.

| Burden | Current evidence | Decision / remaining work |
|---|---|---|
| 12 disjoint top-level identity tags | `ManifestCore.fst`: tagged identity sum, tag/payload encoding, decoder cases, and suffix roundtrip/injectivity lemmas (`:67-257`) | Exactly the 12 spec tags remain. Contract IDs are typed slots in owner rows, not a thirteenth identity domain. |
| Identity/token representation | `Kernel.fst` defines `identity_token = bytes`; all identity names and manifest labels use it. Framed sequence inverse is proved locally (`Kernel.fst:7-10, 161-191`; `ManifestCore.fst:99-105, 318-390`). | No `FStar.String`/`FStar.Char` conversion or host-text promise in the core. Here `bytes = list nat` is an abstract proof alphabet; physical octet encoding belongs to a later concrete refinement. |
| Row metadata and slot shape | `manifest_entry_fields_well_formed` covers all code, operation, generator, codec, artifact, store, metric, graph-codec, schema, resolver, and root fields (`ManifestCore.fst:550-641`). | Exact field order and contract-kind checks are enforced. A04/P0 still binds each token to the exact typed field of the selected proof-bearing package. |
| Top-level reference closure | `manifest_value_references`, `manifest_references_closed`, `manifest_entries_references_typed`, uniqueness and lookup lemmas (`ManifestCore.fst:645-852`). | Every top-level identity reference must resolve to one unique, correctly tagged row. Contract-slot/package existence is explicitly A04/P0, with no duplicate contract table. |
| Artifact schema and codec | Artifact rows require a value codec; `manifest_entries_links_coherent` checks `schemas_match_codec reference_codec [logical_schema]` (`ManifestCore.fst:826-833, 889-891`). This predicate is part of `manifest_data_canonical` (`:1330-1343`). | Accepted. A04/P0 must additionally bind manifest schema tokens to exact carrier and codec packages. |
| Schema-expression payload | A03 frames schema payload syntax bytes but does not parse them. | Intentional boundary: A05 parses the restricted AST and proves canonical encoding and denotation; P0 must require those proofs before pinning a bundle. An arbitrary payload such as `[999]` is correctly rejected only by A05, not A03. |
| Canonical ordering and permutation | Constructive byte-key insertion sort, sortedness and count preservation (`ManifestCore.fst:1008-1109`); no-repeat/count uniqueness and sorted fixed-point/permutation proofs (`:1110-1322`). | Duplicate tagged IDs are rejected before sorting. Canonicalization preserves every row, is permutation invariant for valid inputs, and is idempotent. No Classical/Squash `total_order` or `sortWith` path remains. |
| Codec and rejection | Identity/value/entry/list/manifest suffix inverses and injectivity; complete-input manifest decoder checks canonical predicate and exact re-encoding (`ManifestCore.fst:1422-1538`). | Accepted for manifest syntax. Schema-AST canonicality remains A05. |
| Registry identity | `registry_manifest_identity` requires `manifest_data_canonical` (`ManifestCore.fst:1540-1551`). | Accepted as the canonical-manifest constructor. The low-level `registry_identity_of_bytes` remains available for decoded raw keys, and `GenerationExample` still uses `[0]` as a legacy placeholder; neither proves a pinned bundle identity. A04/P0 owns exact bundle-to-manifest identity. |
| Projection | `first_order_manifest_projection_exact` is full list equality, with a membership-equivalence theorem (`ManifestCore.fst:1552-1562`). | This is A03's syntax-level relation. A04/P0 must prove executable package tables project to exactly these rows in both directions, including contract slots. |
| Imported proof helpers and trust | A03 uses structural Base definitions for `length`, `count`, `mem`, `noRepeats`, `hd`, append, and `bool_of_compare`; Properties helpers `mem_count`, `noRepeats_nil`, `noRepeats_cons`, and `sorted` have checked F* bodies. Installed F* 2026.03.24 source audit found no admission or unchecked helper in these paths. | No project-owned `assume`/`admit` or unchecked application declaration in Kernel, ManifestCore, or GraphCodec. F* checker, logical prelude, and SMT are the stated trusted base. `--report_assumes` is diagnostic only: cache-off fails even on a trivial lemma at `Prims.admit`; cached strict reporting passes both old and new sort sources. |

## Verification evidence

Full configured build:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m \
  make -C src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a03-integrated
```

F* 2026.03.24, Z3 4.13.3, OCaml 5.3.0. All eight configured modules
verified and all VCs discharged. Warning 328 remains for the unused recursive
`WorkflowV2.GraphCodec.nodes_decode_encoding` helper; warning 271 no longer
appears. A separate cached `--report_assumes error` run on Kernel and
ManifestCore passed, but is not treated as transitive-trust proof. Independent
full builds and source audits confirmed the same result.

## A03 completion boundary

A03 establishes canonical first-order manifest syntax, its self-contained
codec/canonicalization laws, and exact top-level identity closure. It does not
claim P0: package-table projection, exact contract-token-to-package binding,
schema denotation, carrier/codec agreement, and reload-stable executable
selection remain A04/A05 obligations. The trusted base is explicit; no proof
burden is discharged by a sample or by raw registry bytes.

For every contract-bearing row, A03 validates ordered slot kind and preserves
the token canonically. A04/P0 must prove both directions:

```text
manifest_slot(owner, kind) = token
  iff
the uniquely selected owner package has the exact typed contract field
whose pinned token is `token`
```

That field carries the actual proof-bearing validator, adapter, or law object.
The theorem compares stable tokens and package membership, never closure
equality. It therefore establishes contract existence without a duplicate
global contract registry.
