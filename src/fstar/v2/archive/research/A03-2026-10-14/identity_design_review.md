# A03 identity design review

Read-only source review, 2026-10-14. Recommendation: make logical
`RegistryIdentity` the exact canonical manifest bytes (`bytes` / `list nat`).
No hash or external crypto premise needed.

## Choice

| Design | Injectivity | Verdict |
|---|---|---|
| Exact canonical bytes | Identity is manifest encoding itself; equality immediately gives byte equality, then manifest-encoder injectivity gives manifest equality. | Use. Smallest proof, no crypto assumption. |
| Digest identity | Requires collision-resistance premise for every identity equality use. | Reject as logical identity. Optional lookup index only; verify full bytes on lookup. |
| Named/versioned identity | Current `{name; version; build:digest}` is not linked to manifest. Name/version do not prove uniqueness; `build` digest retains collision assumption. Could make it injective only by storing full manifest bytes in `build`, which is redundant and misnamed. | Remove registry wrapper; keep human label outside identity if useful. |

Use `RegistryIdentity = Bytes` (or a constructor wrapping bytes if desired for
type distinction), and define `manifest_identity m = canonical_manifest_encoding
m`. Define `manifest_named_by id` only for valid canonical manifest bytes, or
return `option` for arbitrary bytes. Prove canonical encoder injectivity over
valid manifests. This matches spec §2.0 exact-byte requirement and avoids
pretending mathematical `bytes` are host octets or a hash format.

## Existing source and layering

Kernel currently has record identities for codec, code, operation, generator,
graph codec, schema, charge metric, artifact type/store, registry; sum tags
separate Work and Output identities. Registry is `{registry_name;
registry_version; registry_build:digest}`. It therefore does not itself identify
the registry projection.

GraphCodec currently owns length-prefixed encoders/parsers for codec/code/
operation/generator/graph-codec identities and tagged Work/Output encoders.
They prove decode-after-encode with suffix, but do not provide all identity
domains, manifest encoding, sorting, duplicate rejection, or registry identity.
The current GraphCodec dependency is Kernel only.

A01 requires `ManifestCore -> Kernel`, `GraphCodec -> Kernel`; resolver may
consume ManifestCore, but GraphCodec must stay syntax-only. Avoid a second
identity byte format: move shared primitive identity encoders/parsers to
Kernel (or an approved lower shared module imported by both), then have both
ManifestCore and GraphCodec reuse them. Do not make ManifestCore depend on
GraphCodec or GraphCodec on manifest/bundle modules. Keep manifest sorting,
entry encoding, duplicate checks and closure in ManifestCore. A04 Bundle alone
connects projection to executable tables.

## Domains and metadata missing from Kernel

Spec §2.0 requires disjoint tagged manifest-entry domains for code, operation,
generator, codec, artifact type, artifact store, charge metric, graph codec,
schema family/rule, resolver and root entrypoint. Kernel has several base IDs,
but no entry/tagged manifest syntax and no IDs for validator, adapter/config,
allocation contract, resolver, root entrypoint, denotation law, or artifact
interpretation/resource-projection law. Schema identity exists, but no separate
family/rule identity or canonical equation/law metadata. Codec identity has a
version/build, but no declared schema link or codec-version identity token.
JournalCodecIdentity appears in spec's abstract type list; §2.0's enumerated
manifest tags omit it. Clarify whether it is a separate pinned manifest domain
when journal codecs vary; do not silently fold it into a different domain.

Required per-entry projection fields (all first-order IDs/expressions, no
closures/proofs):

- Code: exact input/output codec IDs, implementation version.
- Operation: request/result codec IDs and schemas, validator ID, adapter and
  fixed-configuration IDs, charge metric ID, maximum charge.
- Generator: input codec, graph codec, result-family schema, allocation
  contract ID.
- Value/indexed codec: schema and codec-version identity.
- Artifact type: logical schema, reference-codec ID, store ID, interpretation
  ID, exact resource-projection-law ID.
- Graph codec: input/output schemas, canonicalization version.
- Schema family/rule: canonical expressions/equations and denotation-law IDs.
- Resolver: accepted schema-language version.
- Root entrypoint: input codec, graph codec, result family, root-constructor
  version.

Every cross-link must resolve to exactly one member in its proper tagged
domain; duplicate IDs rejected before canonical sort. Keep operation validator
and adapter/config IDs distinct from operation ID; likewise law IDs distinct
from artifact/schema IDs. These tokens select abstract packages; P13 still
binds tokens to host implementation.

## Consumer migration

- Replace Kernel `registry_identity` record with exact-byte alias/wrapper;
  update constructors and equality sites. Current example assigns
  `{registry_name="v2.example.chain"; registry_version=1; registry_build=[1]}`
  and must derive ID from encoded manifest instead.
- `Journal.started_registry` remains the durable run pin but now stores full
  canonical bytes. `RunStarted` encoder/decoder and replay/resume lookup must
  use the exact-byte key and reject invalid/noncanonical bytes. Audit any
  record-size/format consumers; current GraphCodec has no registry encoder.
- Bundle lookup API changes from record key to bytes (or valid-ID wrapper).
  On restart, lookup must yield same manifest and identity-to-package mapping.
- Human registry name/version can remain optional metadata outside identity;
  never use it as an equality shortcut. Any digest may index manifests only,
  followed by full-byte equality.
- Existing per-package name/version/build IDs can remain short selectors only
  if A04 proves one package per tagged ID and manifest entries bind all
  semantic signatures/versions. Their digests are not evidence that concrete
  code matches token; that remains P13.

Proof chain: tagged identity encoder injectivity; canonical manifest encoder
injectivity; `registry_identity_of_bytes` identity embedding; then equal IDs
imply equal bytes/manifests without cryptographic assumptions. No claim here
that A03 proves package projection (A04) or binary refinement (P13).
