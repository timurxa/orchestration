# A02 kernel signatures and foundations

**Status:** complete, started after A01 commit `34e1021`. Implement the
kernel-level F* API and prove its foundational laws; do not claim P0–P16
complete.

## Intent

Create the small typed vocabulary required by later modules: identity types,
proof-bearing codecs, dependent local/external/generator signatures, work
forms, first-order graph and wire syntax, schema-expression syntax, artifact
reference syntax, run charge metric, and allocation input. This is the
foundation for the abstract durable graph system in
[`../../../implementation_spec.md`](../../schema_era_2026-10-14/implementation_spec.md), not a
replacement workflow API in the abstract.

## Acceptance

- Read the current `WorkflowV2.Kernel`, all importing modules, the normative
  type signatures, and the accepted A01 boundary before editing.
- Define all kernel data and signatures without `assume`, `admit`, unchecked
  external vals, or duplicate sources of truth. Every type/effect choice must
  preserve the three work cases: total pure local F* code, fallible and
  potentially nondeterministic external calls, and total pure graph
  generation.
- Preserve dependent result families (`i -> Type0`) and codecs indexed by the
  exact input. External replies remain arbitrary bytes interpreted by an
  explicit validator; no purity/determinism claim about a remote operation.
- Keep graph syntax first-order and executable callbacks outside journal
  syntax. `GraphDesc` must support finite DAG topology, constants, fan-out,
  joins, and dependent input/output indices without storing proof terms.
- Keep `GeneratorRef` as the callback signature only. A16 later attaches the
  universal `GeneratorPackage manifest` admission proof; Bundle lookup must
  supply exact package values, never compare duplicate closures.
- Treat file/network/database/blob handles as opaque typed artifact
  references with adapter/store interpretations; do not make them primitive
  in-memory blobs or add host-specific I/O to Kernel.
- Expose stable signatures through `.fsti` only when immediately paired with
  one checked `.fst`; update the project build list so interface and body are
  both checked. If source reorganization breaks historical modules, preserve
  a coherent verifier target and document which old partial files are being
  retired; do not make stale admitted code part of new theorem closures.
- Prove the codec record laws/any generic codec combinator laws claimed by
  this layer. Run the complete F* verifier for the resulting configured
  project and record the command/tool versions/results. Do not substitute
  examples or tests for proofs.
- Keep state files consistent. A02 completion is not C1; C1 waits for
  ManifestCore, schema/resolver, Allocation, GeneratorAdmission, and P0.

## Research assignments and integrated findings

| Assignment | Method | Output | Status |
|---|---|---|---|
| Existing kernel/import compatibility | Read-only map of current declarations, use sites, and safe migration choices | `kernel_compatibility.md` | complete |
| Codec/signature proof exploration | Compare minimal codec and dependent signature shapes against spec and F* behavior | `kernel_signature_review.md` | complete |
| Adversarial API review | Find hidden determinism, closure equality, serialization, and dependent-index gaps | `kernel_adversarial_review.md` | complete |
| Minimal schema/artifact signature review | Compare minimal Kernel declarations with normative schema and artifact contracts | `kernel_minimal_shapes.md` | complete |
| Kernel contract review | Check implemented schema grammar, metric flow, and artifact typing | `kernel_contract_review.md` | complete |
| Change and trust review | Check compatibility, call sites, build, and admission scope | `change_review.md` | complete |

Root owns `WorkflowV2.Kernel` and shared state; reviewers do not edit source.

Integrated findings to retain in the implementation:

- Preserve current first-order graph/wire constructors and existing identity
  labels during this Kernel step; they have many codec, graph, journal, and
  example consumers. Later DAG nodes migrate these consumers deliberately.
- Keep `codec` and `indexed_codec` as proof-bearing records indexed by the
  exact dependent input. Keep external work as arbitrary reply bytes plus a
  pure validator returning `option (output x)`; do not model the remote effect
  as an F* function or claim determinism.
- Thread one `ChargeMetricIdentity` through `RunBudget`, `OpRef`, and every
  generator invocation. Metric equality across those boundaries is later
  proved from pinned package membership, not inferred from equal naturals.
- Add schema expression and typed artifact-reference vocabulary only. Schema
  interpretation/resolution belongs to Schema/GraphResolve; artifact-store
  behavior and host handles belong to ArtifactStore. Do not add an arbitrary
  resolver callback or an in-memory Blob primitive.
- Exact executable-package lookup returns the selected package together with
  membership evidence at Bundle; Kernel must not compare callback closures or
  create a second lookup table.
- Existing lookup only proves uniqueness of full durable work refs; manifest
  uniqueness must separately reject duplicate tagged work identities and
  later prove codec/schema links (P0).
- The Kernel's `artifact_ref a` is an uninterpreted typed token, while
  `packed_artifact_ref` is candidate syntax that can pair a runtime identity
  with an unrelated phantom carrier. This is not a published resource or a
  canonical packed reference: ArtifactPackage/P0/P9 must prove the exact
  identity/carrier/codec link before encoding or commit. Host handles and
  backing-object meaning remain outside Kernel.

## A02 implementation and verification result

Implemented first-order schema syntax exactly for the specified `Ty`,
`Value`, and `Pred` cases; stable identities for schemas, metrics, artifact
types, and stores; typed artifact token/packing syntax; and the run-wide metric
field on budgets, operations, and generator calls. Updated all legacy generator
call sites and admission signatures. No generic codec combinator or P theorem
was claimed; codec records require checked roundtrip and canonicality proofs
from each supplied package.

Full configured verifier command:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify
```

Result: success, all seven Makefile modules verified (`WorkflowV2.Kernel`,
`GraphCodec`, `Identity`, `Graph`, `GenerationExample`, `ChainProof`, and
`Journal`) with F* 2026.03.24 and Z3 4.13.3. The two pre-existing warnings
(stdlib UInt pattern and unused recursive GraphCodec lemma) remain. Kernel
adds no `assume`, `admit`, or unchecked declaration. This does not remove
legacy admissions in `Graph.fst`, establish any P0–P16 system theorem, or make
the old seven-module closure a trusted final system.
