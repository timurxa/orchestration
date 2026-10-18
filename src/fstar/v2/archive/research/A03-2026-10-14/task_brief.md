# A03 — Canonical ManifestCore

**Status:** complete; source and proof result committed as `09ed6ea` and
recorded in the canonical state files.

## Goal

Build the first-order canonical manifest layer required by
[`../../implementation_spec.md`](../../schema_era_2026-10-14/implementation_spec.md), without
mixing executable closures, runtime artifact handles, or proof terms into
durable bytes. A03 supplies canonical syntax and proofs that A04 can connect
to exact package tables; it does not claim P0 by itself.

## Required work

1. Audit all identity domains and metadata enumerated in implementation spec
   §2.0, the current Kernel and GraphCodec identity encoding, and the A01
   module boundary. Add any missing first-order identity wrappers at Kernel's
   owner boundary; make tagged entry domains disjoint.
2. Define `RegistryManifest` as a finite first-order list of tagged entries.
   Include every semantically relevant reference/version from the spec:
   Work signatures and codec/schema links; operation validator/adapter/config,
   result/request schemas, metric and charge bound; generator graph/schema and
   allocation contract; codec schema/version; artifact type/reference codec,
   store, interpretation and projection-law IDs; graph codec schemas/version;
   schema family/rule equations and denotation-law IDs; resolver language
   version; root entry signature/construction version. Store no closures or
   proof values. Identity names/labels are opaque byte sequences, not F*
   `string`; host text conversion belongs outside the kernel.
3. Specify uniqueness separately per tagged identity domain. Reject duplicate
   IDs before canonical sorting; never silently deduplicate or use table order
   as a winner. Prove every top-level identity reference resolves to exactly
   one correctly tagged manifest member. Contract IDs are typed owner-row
   slots, not separate manifest identity domains: A03 proves exact slot
   position/kind; A04/P0 proves each token is exactly the proof-bearing
   contract field on the selected package, without a duplicate contract table.
4. Choose one deterministic canonical order (tag, then canonical identity
   encoding) and define the canonical manifest encoder. Prove encoder
   injectivity, canonical-order uniqueness/idempotence, tagged identity
   injectivity, and duplicate-rejection facts used by P0. Keep the encoding
   over the current abstract `bytes` representation honest; do not claim a
   host octet/file format or hash collision resistance. Check that each
   artifact type's logical schema equals the schema of its reference codec.
   Schema-expression payload bytes stay opaque here; A05 parses and proves
   canonical AST form before P0 relies on them.
5. Make registry identity injective over the full canonical manifest. Require
   a canonicality witness at the manifest-to-registry-identity constructor;
   recovery validates raw bytes before using a registry key. Prefer
   the exact canonical manifest bytes as the logical identity; a digest may
   be an index only and must not replace this proof. Compare with retaining
   `registry_name/version/build` or a digest key, and record the decision and
   its consumer migration.
6. Define a first-order manifest-projection relation and prove its exact
   forward/backward shape. A04 later proves the executable bundle's package
   tables project to this manifest; do not introduce Bundle or closure
   equality here.
7. Keep the module acyclic: `WorkflowV2.ManifestCore` depends on Kernel only.
   Avoid a second source of truth for identity encodings; reuse or relocate
   the existing canonical identity routines consistently within the approved
   module graph. Preserve a full verifier build including all currently
   configured legacy modules; if a new `.fsti` is needed, pair and check its
   `.fst` immediately.

## Proof acceptance

- No project-owned `assume`, `admit`, unchecked application declaration, or
  theorem placeholder may discharge a new ManifestCore claim. The F* checker,
  logical prelude, and SMT solver are the explicit trusted base. Audit imported
  proof helper implementations; do not use helpers whose theorem body relies
  on an admission. `--report_assumes` is diagnostic only: cache-off mode fails
  at `Prims.admit` even for a trivial lemma, while cached mode did not flag the
  previous Classical/Squash path.
- Prove from definitions: identity encoder roundtrips/injectivity; manifest
  encoder roundtrip/injectivity over valid canonical manifests; uniqueness
  of lookup for each tagged identity; no-duplicate canonicalization; exact
  reference closure; and exactness of the first-order projection relation.
- The full configured F* verifier must pass, and the exact command, tool
  versions, modules, warnings, and trust limits must be recorded.
- A03 completion does not claim P0; exact executable package projection,
  codec/schema carrier coherence, restart-stable package selection, and
  generator law binding remain A04/P0.

## Research assignments

See [`approach_registry.md`](approach_registry.md). Root owns source and
shared-state edits; reviewers are read-only.

## Integrated findings so far

- The identity, encoder-proof, and manifest-shape reviews are complete. Their
  reports are linked in the approach registry.
- Use exact canonical manifest bytes as the logical registry key. A digest can
  accelerate lookup only if full bytes are checked after lookup; it cannot
  establish manifest equality.
- Keep one shared identity encoder/decoder source in Kernel, because A01
  requires both GraphCodec and ManifestCore to depend on Kernel. ManifestCore
  owns tagged manifest serialization, ordering, uniqueness, and link closure;
  GraphCodec reuses shared identity routines and keeps graph syntax codec
  ownership.
- The first-order projection relation belongs to A03. Projection from actual
  `noeq` executable package tables and exact carrier/callback binding remain
  A04/P0 obligations.
- Root is performing the adversarial duplicate/collision/omitted-link pass;
  the completed independent review is now in
  `manifest_adversarial_review.md`. It requires separate predicates for
  unique tagged keys, required fields, canonical order, link closure/coherence,
  and a two-way projection relation.
- The existing identity encoder migration review is in
  `source_migration_review.md`. The shared framing, identity codecs, and
  suffix laws have been moved mechanically from GraphCodec into Kernel;
  GraphCodec now owns graph syntax codecs only. The full seven-module verifier
  passed after this migration; exact command and limitations are recorded in
  `source_migration_verification.md`.
- The initial `FStar.Classical`/`FStar.Squash` sorting proof was replaced by a
  structurally proved insertion sort. The final trust criterion is the
  project-owned source/call-path audit plus full F* verification; the global
  `--report_assumes` mode is not a reliable detector for imported helper
  admissions. Kernel identity-name codecs will use opaque byte tokens so
  their roundtrips do not depend on unchecked `FStar.String`/`FStar.Char`
  conversion laws.
- Independent A03 acceptance review found two required integration points:
  artifact-reference codec schema agreement belongs in A03; typed contract
  token existence/equality belongs in A04/P0's exact package projection.
  Schema AST byte validity is an A05 obligation, not claimed by A03's framed
  manifest codec.
- Integrated closeout: opaque-by-convention identity tokens are represented
  as `identity_token = bytes` (`bytes = list nat` in the abstract kernel),
  with local framed-sequence inverse proofs. No Unicode, UTF-8, or octet-level
  representation is claimed. Journal run names and artifact identities use
  the same token type.
- Added artifact logical-schema/reference-codec-schema agreement to
  `manifest_entries_links_coherent`, and made `registry_manifest_identity`
  require canonical manifest data. Exact executable package projection and
  contract-slot binding remain A04/P0; schema-byte parsing/canonicality
  remains A05.
- Full configured verification passed after integration:
  `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
  src/fstar/v2 verify BUILD_DIR=/tmp/fstar-v2-a03-integrated`. F* 2026.03.24,
  Z3 4.13.3, OCaml 5.3.0; all eight configured modules and all VCs passed.
  Only warning 328 remains for an unused recursive GraphCodec lemma. Three
  independent source/proof reviews plus an imported-list-helper source audit
  found no A03 blocker; see `acceptance_audit.md` and `stdlib_axiom_audit.md`.
- Trust claim is scoped to the A03 dependency path: Kernel and ManifestCore
  contain no project-owned `assume`/`admit`/unchecked declaration and invoke no
  admitted helper. The checker, logical prelude, and SMT remain the trusted
  base. A03 makes no claim that the legacy `Graph`/`ChainProof` sources are
  admission-free; their replacement is later DAG work.
