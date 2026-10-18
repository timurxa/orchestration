# A02 kernel signature review

Read-only review of `implementation_spec.md`, current `WorkflowV2.Kernel`,
importers (`Identity`, `Graph`, `GraphCodec`, `GenerationExample`, `Journal`),
and A01 boundary notes. No source changes or new verification claim.

## Shape comparison

- `codec a` and `indexed_codec i o` in `Kernel.fst:90-108` closely match the
  normative `Codec`/`IndexedCodec` records (`implementation_spec.md:110-127`).
  `noeq` is appropriate: records contain functions and law witnesses, so
  package equality must not depend on function extensionality. The laws state
  roundtrip and decode-canonicality at exact `x`; these suffice for canonical
  replay reasoning, but not registry coherence by themselves.
- `code_ref`, `op_ref`, and `generator_ref` preserve `i -> Type0` families;
  `Work` has the three requested constructors and only indexes executable
  callbacks outside graph syntax (`Kernel.fst:110-138,167-189`). `op_ref`
  exposes only a pure total validator for raw reply bytes, not a pure remote
  operation, so remote nondeterminism is not accidentally ruled out. However,
  current `op_ref` omits the spec's `charge_metric`; generator callback also
  omits the spec's `ChargeMetricIdentity` parameter (`implementation_spec.md:
  305-311,654-665`). These are signature mismatches, not harmless details:
  downstream admission cannot state metric-sensitive operation/generator
  contracts from current refs without another source.
- `graph_desc`/`wire` are appropriately first-order and parameterized by exact
  root input. `ConstantWire` stores codec identity plus bytes; `OutputWire`
  permits fan-out and pair projections. The output family is phantom in
  descriptor fields: output typing and finite-DAG validity must come entirely
  from resolver/schema proofs, never from `graph_codec` roundtrip alone.
  `GraphCodec` currently proves syntax roundtrip/canonicality only.
- Kernel has no schema-expression grammar/package yet. The normative fixed
  `Ty`/`Value`/`Pred` grammar and resolver contracts (`implementation_spec.md:
  798-827, 914-927`) must be added in an acyclic module; do not make arbitrary
  `Type0` equality or a callback resolver the admission rule.
- Artifact boundary is currently incompatible with the target: `Journal.fst`
  stores concrete `artifact_ref` fields including `artifact_location:bytes`
  (`Journal.fst:39-44`); no opaque `ArtifactRef a` / existential
  `PackedArtifactRef` exists. Spec explicitly requires opaque typed refs,
  package-selected reference codec/store interpretation, and no primitive
  blob/path/handle (`implementation_spec.md:1409-1467`). Do not reuse that
  journal record as kernel artifact authority.

## Main proof and identity risks

1. **Package identity is not callback equality.** Current `Identity.fst`
   correctly uses `noeq` packed packages and returns membership evidence with
   lookup (`Identity.fst:84-90,108-138,185-218`). Keep this pattern. But its
   work table proves uniqueness only for the *full* `durable_work_ref`
   (`Identity.fst:92-105`), not uniqueness of each tagged work identity.
   Thus same `CodeIdentity` could appear twice with different codec links and
   produce two different durable refs. Manifest construction must reject
   duplicate tagged IDs independently, and exact lookup must return the one
   stored package; never compare closures.
2. **References do not yet resolve to the pinned codec entries.** A `CodeRef`
   can carry input/output codec values whose IDs are unconstrained relative to
   `global_codec_registry`. Existing uniqueness and resolver lemmas establish
   at-most-one package per `CodecIdentity`, but not work-to-codec membership,
   carrier/schema coherence, or manifest projection. Those are required P0
   package-link proofs, not consequences of codec roundtrip laws.
3. **Generator totality is weaker than generator admission.** `Tot` makes
   callback pure/terminating at F* level; it does not prove generated graph is
   schema-supported or child allocations are within parent budgets. The
   `generated_graph` parent index is only an index, not a validity proof.
   Correct later API attaches universal law to exact pinned callback (A16),
   including metric and every input/allocation; a sample result is insufficient.
   Restart determinism also depends on exact package/build identity and stable
   F* semantics. `generator_ref_id` currently has no link to callback/build;
   P0 projection and host P13 refinement must carry this boundary explicitly.
4. **Simple IDs and bytes are not yet canonical durable identity.** Kernel
   represents IDs as ordinary name/version/digest records, `digest = bytes`,
   and `bytes = list nat` (`Kernel.fst:7-8,10-48`). No canonical encoding,
   octet bound, injective manifest embedding, or digest collision premise is
   present here. The spec requires full identity/canonical manifest
   projection and treats digest equality as insufficient absent a host premise
   (`implementation_spec.md:148-169`).
5. **Graph syntax validity is separate.** `graph_roundtrip` can hold for
   descriptors with duplicate keys, forward/missing edges, unknown work IDs,
   invalid constants, or an output wire of wrong schema. This is acceptable
   only if names remain precise and every use of decoded graphs follows
   resolver `graph_wf` before execution/commit. Do not promote GraphCodec's
   byte laws into graph-validity claims.

## Verification/environment

No F* executable found on current `PATH`. Repository records F* 2026.03.24 /
Z3 4.13.3 as prior environment evidence, while the Makefile does not pin either
tool. No verification was run for this review. Current source has no `.fsti`
pair; preserve A01 rule that every introduced interface is checked with its
paired implementation and included in full build.
