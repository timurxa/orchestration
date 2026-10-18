# A03 manifest shape review

## Minimal representation

Use `RegistryManifest = { format_version; entries: list ManifestEntry }`. `ManifestEntry` is one first-order tagged union, one constructor per disjoint identity domain. Each payload stores its identity plus the complete package-selection signature and semantic links. Keep lists/expressions as data; no closures, carrier types, runtime handles, or proof values.

Suggested payloads:

- `Code`: `CodeIdentity`, input codec, output indexed codec, input/result schema, implementation version.
- `Operation`: `OperationIdentity`, request/result codec, request/result schema, validator ID, adapter ID, configuration ID, charge-metric ID, maximum charge.
- `Generator`: `GeneratorIdentity`, input codec/schema, graph-codec ID, result-family schema, allocation-contract ID.
- `Codec`: `CodecIdentity`, value/indexed kind, schema (or indexed input/result schemas), codec-version ID.
- `ArtifactType`: identity, logical schema, reference-codec ID, store ID, interpretation ID, resource-projection-law ID.
- `ArtifactStore`: identity and store-format/version token. `ChargeMetric`: identity and metric-definition/version token.
- `GraphCodec`: identity, input/output schema, canonicalization version.
- `SchemaFamily` / `SchemaRule`: identity, canonical first-order expression/equation, denotation-law ID.
- `Resolver`: identity, accepted schema-language version.
- `RootEntry`: identity, input codec/schema, graph-codec ID, result-family schema, root-constructor version.

Kernel already has first-order IDs for codec, code, operation, generator, graph codec, schema, charge metric, artifact type, artifact store, registry. It lacks separate IDs for validator, adapter, configuration, implementation version if not represented by `code_build`, allocation contract, codec/schema denotation versions or laws, schema family/rule domains, artifact interpretation and resource projection law, resolver, root entry, and graph canonicalization version. Add wrappers at Kernel owner boundary; do not overload unrelated identity domains. Consider explicit input/result schema IDs in signatures: codec IDs alone select codec package but do not encode the spec's schema links.

## Links and single source of truth

Every referenced identity must resolve to exactly one entry of expected tag. Work signature is explicit `(input codec/schema, output codec/schema or graph codec)`; operation/generator extra contract IDs remain references, not copied definitions. Schema AST and version tokens are the canonical definitions. Manifest projection derives each entry from its package table; it is not an independently editable registry. Bundle tables stay the source of executable packages; manifest rows are their canonical projection. No per-work wrapper or duplicate executable identity.

Require one unique ID per tagged domain before sorting. Canonical order: tag, then canonical encoding of identity. Duplicate rejection precedes sorting, so source table order cannot pick winner. Cross-reference closure should state exact-one lookup for every link, including nested schema/codec links.

## Proof boundary

A03 proves first-order identity/tag encoder injectivity, canonical entry/manifest encoding and ordering, duplicate rejection, unique tagged lookup, link closure, and both directions of first-order projection relation. It can prove projection relation's structural exactness without executable bundles.

A04/P0 owns executable package-table projection, package selection/coherence for `noeq` packages, actual codec/schema carrier agreement, code/validator/adapter/generator callback binding, generator admission/allocation laws, exact root package, and restart-stable identity-to-package association. P13 owns concrete binary/extraction refinement; digest collision assumptions, if host chooses digest key, also belong at host boundary. A03 does not establish host binary matches tokens or prove P0 alone.

## Risks / decisions

`code_build` and identity build digests are not sufficient substitutes for explicit implementation/contract version fields unless spec semantics define them as such. Likewise, a generic `SchemaIdentity` cannot establish family-vs-rule uniqueness without tag constructors. Preserve distinction between indexed and value codec entries. Store charge metric definition/version in its own entry; operation's metric link plus bound should not duplicate definition. Do not serialize callback identity as closure bytes: stable token names package, A04 proves binding.
