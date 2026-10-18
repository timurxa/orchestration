# A03 approach registry

| Assignment | Method | Evidence | Decision quality | Independent value | Status |
|---|---|---|---|---|---|
| Manifest/identity alternatives | Read spec and compare exact canonical-byte key, digest key, and named identity | `identity_design_review.md` | Accepted: exact canonical bytes are logical identity; digest only indexes | Focus on injectivity and consumer migration | Complete |
| Canonical encoder proofs | Explore F* codecs for tagged identities and sorted manifest lists | `encoding_proof_review.md` | Accepted: decoder left inverses prove injectivity; duplicate-check before total sort | Focus on terminating encoders, decoder roundtrips, sort uniqueness | Complete |
| F* proof feasibility | Scratch probes for tagged codecs, injectivity, and sorting | `proof_feasibility_review.md` | Tagged inversion/injectivity and insertion-sort sortedness verify without admissions; lex-order and sorted-permutation uniqueness remain to prove | Focus on actual F* verifier behavior and proof decomposition | Complete |
| Manifest schema and projections | Inventory required metadata, cross-reference closure, and exact projection boundary | `manifest_shape_review.md` | Accepted: first-order tagged entries; executable package projection remains A04 | Focus on completeness without duplicating package truth | Complete |
| Adversarial identity audit | Independent counterexample review across duplicates, links, ordering, lookup, encoding, and projection | `manifest_adversarial_review.md` | Incorporated: factor validity predicates and exact-one lookup; make projection bidirectional | Preserve rejection behavior and theorem strength | Complete |
| Existing identity encoder migration | Source audit plus mechanical move of shared encoders/proofs into Kernel | `source_migration_review.md`; `source_migration_verification.md` | Accepted and checked; A01 dependency graph preserved | Avoid parallel canonical encoders and keep A01 import graph | Complete (Root) |
| Proof trust boundary | Audit owned source and imported helper call paths; test report-assumptions modes and distinguish the F* trusted base | `stdlib_axiom_audit.md`, `acceptance_audit.md`; installed F* 2026.03.24 source | Initial Classical/Squash sort path rejected; current insertion sort uses checked local lemmas and checked List.Tot helper bodies; byte-token codecs avoid `FStar.String`/`FStar.Char` laws; `--report_assumes` is diagnostic only | A03 Kernel/ManifestCore path has no project-owned admission or unchecked declaration and invokes no admitted helper; do not generalize this to legacy Graph/ChainProof | Complete |

Three independent review reports converge on one direction: keep the A01
module graph, move shared primitive identity codecs to Kernel, and let
ManifestCore own tagged entries, canonical ordering, and cross-reference
closure. Registry identity wraps exact canonical bytes; digest and
human-readable name/version are not logical keys. A03 source fixes,
independent reviews, imported-list helper audit, and the full eight-module
verifier are complete. Artifact schema coherence is included in canonicality.
Exact contract-slot/package binding remains A04/P0; schema-byte parsing and
canonical AST validation remain A05. See `acceptance_audit.md` for the scoped
closeout matrix and canonical state files for commit evidence.
