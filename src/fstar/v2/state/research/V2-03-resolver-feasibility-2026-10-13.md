# V2-03 resolver feasibility and missing information

**Status:** independent design audit; implementation decision remains open.

## Finding

The verified graph codec preserves the first-order descriptor: work/codec
identities, node keys, wire constructors, and constant bytes. It does not
preserve `typed_node_sequence` or `wire_typing_witness`. Those witnesses carry
existential `Type0` indices and a proof, for every prior-port environment, that
the selected Work's fixed input type equals the wire's output family.

Exact `durable_work_ref` lookup proves which `Work` package was selected. It
does not produce that equality. In particular, `Type0` has no general
first-order representation or executable equality decider. The codec can
round-trip syntax while the typed resolver remains impossible to derive from
the current interfaces alone. This is a missing representation/evidence
boundary, not a missing runtime value and not proof complexity.

The scope is visible in source:

- `Kernel.fst` serializable `wire` and `graph_node` retain only labels/keys and
  syntax; `Work` has an arbitrary dependent output family.
- `Identity.fst` resolves exact package membership and key equality.
- `Graph.fst` `TypedNodesSnoc` and `wire_typing_witness` express the needed
  all-environments typing facts, but they are proof-side data not recovered by
  `GraphCodec.decode_graph`.
- `graph_wf` currently means existence of `typed_graph_witness`; it does not
  imply there is an executable function that reconstructs that witness.

No general no-go theorem is encoded in F* here. The precise claim is that
arbitrary `Type0` equality is not computable from the data currently serialized
or pinned; a constructive implementation must make adequate type/proof
information available or restrict which witnesses count as recoverable.

## Alternatives

### A. Canonical schema language

Give pinned Work/codec packages a first-order schema expression whose
interpretation is proved equal to their actual F* type. Resolver computes
schemas from root/constants/prior outputs and checks compatibility. Dependent
families require symbolic expressions over the graph input and environment;
non-definitional equalities need canonical certificates or named pinned
lemmas.

- Preserves byte-only graph syntax when schemas are fully determined by the
  pinned manifest and wires.
- Supports arbitrary topology and dependent types expressible in the schema
  language.
- Completeness is relative to that language; arbitrary opaque F* refinements
  are not automatically representable.
- The existing token-manifest draft is insufficient until pointwise family
  equality is proved.

### B. Canonical edge-proof evidence

Store proof-evidence bytes per node and have a pinned verifier reconstruct the
exact typed input wiring. Define graph well-formedness to include successful
validation of each evidence value.

- Preserves arbitrary F* propositions when users can provide an accepted
  certificate.
- Adds graph bytes and a certificate grammar/checker (or proof-term kernel).
- Completeness is relative to the certificate language unless every accepted
  F* proof can be reified and checked.
- A Work-pinned total handler can be the checker, but the handler and evidence
  codec must be pinned in the same manifest.

### C. Work-pinned input resolver, no evidence bytes

Pair each exact Work package with a pure `input_resolver`. The resolver takes
the dependent port context and raw wire and returns either `None` or a typed
`wiring` whose syntax is exactly that wire. The graph builder accepts a node
only through this resolver; recovery invokes the same pinned code. Its result
type makes successful edges sound without executing Work.

- Leaves graph bytes unchanged and works well for API-generated graphs.
- Completeness is only for graphs accepted by the resolver; redefine
  `graph_wf`/builder reachability to require this replayable provenance, or
  separately prove resolver completeness for all current `graph_wf` graphs.
- A general handler cannot infer equality of arbitrary opaque types from a
  runtime key. It must use schema evidence, a certificate, or its own
  constructive proof procedure.
- Current module direction (`Kernel -> Identity -> Graph`) prevents placing a
  handler typed in terms of `Graph.wiring` directly in `Work`. A graph-level
  registry wrapper can pair handlers with exact base Work entries, but its
  combined manifest identity must pin both. Avoid duplicating Work values.

### D. Re-run pure generator during recovery

For generated graphs only, rerun the exact pinned total generator to rebuild
the typed witness and require its canonical encoding to equal committed graph
bytes.

- Avoids a generic syntax-to-type resolver for generated graphs.
- Does not cover arbitrary root graphs, and reruns generation after recovery.
- Changes the current contract that committed descriptors recover directly
  from committed bytes without regeneration. It is an alternative only if
  that contract is deliberately revised.

### E. General F* proof reification

Keep arbitrary `Type0` and arbitrary typed-DAG completeness by serializing
enough proof terms and implementing a sound checker for the corresponding F*
fragment. This most directly preserves the broadest source-level graph
language, but it introduces a proof language, canonical proof encoding, and a
checker/refinement proof. Agentic proof work can prove the checker correct;
it cannot recover a proof that was erased and never represented.

## Recommendation and open decision

Do not claim V2-03 complete from codec round-trip, exact identity lookup, or
the verified chain example. Keep the current strict acceptance until the
representation decision is explicit. The least invasive viable prototype is
the Work-pinned resolver with graph well-formedness restricted to
resolver-certified graphs; the strongest generality route is a certified,
extensible schema/proof language. Neither may silently replace the current
P1/P2 completeness statement.

The required decision is the completeness boundary:

1. preserve arbitrary `Type0` graph edges by adding canonical proof/schema
   evidence;
2. define valid graphs as exactly those accepted by pinned resolvers; or
3. retain arbitrary typed graph semantics and build a proof reification/checker
   layer.

Until that choice is made, V2-03 stays `in_progress`, and the simplifier and
human review gate remain downstream.

### Converged prototype candidate (not selected)

A third independent review recommends a hybrid: keep graph topology and wire
syntax first-order; bind canonical schemas to the exact pinned Work/codec
packages; synthesize each wire's schema symbolically over the typed prefix;
and allow a small canonical equality-certificate language for equalities not
handled by schema conversion. Both schema denotations and certificate checks
must be proved sound in F*. A per-Work resolver may be an extension point, but
it must satisfy the same soundness/completeness contract and be pinned with the
Work entry.

This is the strongest practical candidate for the current API shape, but its
completeness is still relative to the schema and certificate language. It
does not prove that every equality expressible in arbitrary F* `Type0` is
reified. If unrestricted F* equality remains mandatory, the proof checker
must cover that larger proof language; merely writing an F* resolver callback
does not make arbitrary erased proofs recoverable. A precise scoped contract
would return a typed witness on success and prove completeness only for
`resolver_supported` descriptors:

```fstar
val resolve_graph : bundle:PinnedBundle -> x:i -> g:GraphDesc i o x ->
  Tot (option (typed_graph_witness bundle x g))
val resolve_graph_complete : bundle:PinnedBundle -> x:i -> g:GraphDesc i o x ->
  resolver_supported bundle x g -> Lemma (resolve_graph bundle x g <> None)
```

This candidate is recorded for comparison only. It does not amend normative
P1/P2, narrow `graph_wf`, or authorize downstream work.

## Provenance

- Root source audit: full F* check; inspected graph codec, exact registry
  lookup, `typed_node_sequence`, and current `graph_wf` definitions.
- Independent graph representation audit: confirmed no executable resolver
  follows from exact work lookup; recommended a canonical schema language or
  persisted proof evidence.
- Independent resolver audit: proposed a Work-pinned input handler for
  builder-generated/resolver-certified graphs; identified the Graph/Identity
  module cycle and the completeness restriction.
- Follow-up independent representation audit: recommended the schema plus
  validated-certificate hybrid, with the same explicit completeness boundary;
  confirmed callback presence alone cannot recover arbitrary erased equality.
- F* verification on 2026-10-13:
  `opam exec -- make -C src/fstar/v2 verify` passed all seven modules. This
  validates the source theorems currently present, not the absent resolver.
