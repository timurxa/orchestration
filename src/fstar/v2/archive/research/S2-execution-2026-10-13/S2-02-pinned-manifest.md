# S2-02 — Pinned manifest, identity, and codec contract

**Status:** complete at specification-contract level. This records no F* source
implementation or discharged source theorem. The normative contract is in
[implementation_spec.md, §2](../../schema_era_2026-10-14/implementation_spec.md#2-minimal-typed-api)
and P0 in its required-proof table.

## Decision

The pinned bundle owns the executable package tables. Its manifest is a
canonical first-order projection of those exact tables, not a second caller
supplied registry. The projection is exact in both directions: every package
contributes exactly one tagged row, and every row resolves to exactly one
package with all signature, schema, codec, configuration, and version links.
Duplicate identities fail construction before sorting.

`RegistryIdentity` identifies the canonical manifest encoding. The contract
states both lookup and bundle coherence:

```text
manifest_named_by (pinned_registry_identity b) = registry_manifest b
manifest_identity (manifest_named_by id) = id
manifest_identity (registry_manifest b) = pinned_registry_identity b
```

Identity uniqueness is required for each executable identity itself, not only
for a complete `DurableWorkRef`. Equal code, operation, generator, codec,
graph-codec, schema-rule, resolver, or root-entry identities must denote the
same complete package and laws. Work signatures derive from the exact codec
members in the selected package.

Plain and indexed codecs each have typed round-trip and accepted-bytes
canonicality laws. Indexed decoding is at the exact recovered input. The
root entry binds the root input codec, graph codec, output family, and a total
root constructor; its all-input/all-budget law uses the same manifest and
resolver and validates the graph and allocation plan. `RunStarted` persists
the root-entry identity, canonical input bytes, exact graph bytes, budget,
and plan, then proves those bytes and plan equal the constructor result.

The abstract loader returns the same canonical manifest after restart. This
is P0's model-level stability contract. Matching identity tokens to actual
host code, extracted binaries, and loaders belongs to P13 refinement. A
digest-backed implementation additionally needs a collision-resistance
premise; the abstract identity is exact.

The module boundary is acyclic: kernel syntax and schemas; first-order
manifest core; graph resolver over that core and descriptor syntax;
bundle-composition proof joining resolution to executable tables; runner.
The resolver identity names the accepted language/version but does not make
the manifest import its own resolver result.

## Alternatives considered

- **Identity beside mutable resolver tables:** rejected because equal labels
  would not show that the recovered package matches the run-start package.
- **Uniqueness only for full work references:** rejected because two code
  packages could share a code identity while disagreeing on implementation
  or schema.
- **Digest as the abstract identity:** rejected as a proof-free equality
  shortcut. A concrete digest is allowed only with the host collision
  premise.
- **Serialized closures or proof terms:** rejected; the journal stores stable
  identities and syntax, and recovery reconstructs packages/proofs from the
  pinned manifest.
- **Per-node typed registry wrapper:** unnecessary; the one immutable bundle
  resolves heterogeneous durable references after decode.

## Proof targets and boundaries

P0 proves exact projection, bidirectional identity coherence, identity-level
uniqueness, codec round-trip/canonicality, cross-table closure, root linkage,
and same-manifest abstract reload. These are contract and theorem targets,
not claims that the current V2 `.fst` files prove them. P13 must prove the
concrete host loader/extraction refines those abstract relations.

Independent review found the required identity equations and projection
relation present. No F* source changed, no verifier ran, and no test was
added. Review evidence: [P0 final review](/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-02-p0-final-review.md).
