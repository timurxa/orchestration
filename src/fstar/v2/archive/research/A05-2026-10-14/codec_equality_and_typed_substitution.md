# A05 codec equality and typed substitution — 2026-10-14

This is a proof-work checkpoint for A05, not A05 completion. The schema codec
laws are already integrated. This note records the next semantic facts and
their limits.

## Exact-codec equality bridge

`WorkflowV2.SchemaSemantics.fst` now proves two generic lemmas:

- `schema_plain_codec_encode_injective`: equal encodings under one `codec`
  imply equal values.
- `schema_indexed_codec_encode_injective`: equal encodings under the same
  `indexed_codec` and exact same index imply equal indexed values.

Both follow constructively from the codec's `decode(encode x) = Some x` law.
No host equality decision, arbitrary observation callback, or unchecked
solver result is needed. The indexed condition is essential: bytes for outputs
at different indices do not establish a shared carrier.

The source module verifies in the full configured build:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify \
  BUILD_DIR=/tmp/fstar-v2-a05-codec-eq-rerun \
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'
```

Exit 0; all eleven configured modules verified and all VCs discharged with
F* 2026.03.24 / Z3 4.13.3. Existing warning 328 remains in `GraphCodec`.
The source commit hash is recorded in `run_log.md` and the A05 summary.

## Consequence for `SchemaEqual`

The earlier scratch `semantic_type` design used arbitrary `atom_view`,
`family_view`, and symbol observation callbacks. Such callbacks can map two
distinct values to the same observation, so equality of observations is not
sound for `SchemaEqual` unless equality reflection is proved. Do not integrate
that design as-is.

The exact codec can supply an equality-reflecting representation. Once both
operands have a checked value-typing derivation at the same semantic type and
exact index, equality of their canonical bytes yields equality of the actual
F* values by the new lemmas. `SchemaEqual` therefore needs typed denotation
evidence for both operands; an untyped `option observed_value` evaluator must
not choose a carrier or codec at runtime. Atom/family packages must expose the
exact codec at their actual type/index, and A04/P0 must bind that package and
codec to the selected manifest row and Work signature.

For `Sigma`, the second component's codec is indexed by the exact first
component. For `Refine`, the intended carrier remains the F* subset/refinement
at the candidate, not a raw `(candidate, proof)` pair. Decoding a refined
value requires a sound, complete predicate decision procedure that rebuilds
the proof; equality cases use same-type codec injectivity. Any proof-erased
encoding also needs equality at the refined carrier to respect proof
irrelevance, not just a projection from an arbitrary noeq subset wrapper.

## Substitution proof exploration

Verified scratch modules show useful, but not yet integrable, proof shapes:

- `/tmp/A05ActualValueSubst.fst` proves value, predicate, and type
  substitution preservation for relational denotations. Sigma and Refine
  extend the relation with the actual candidate and preserve exact values;
  this avoids function extensionality. Its carrier-only `hlist` does not
  connect each `Bound` carrier to its declared schema type.
- `/tmp/A05TypedASTSemantics2.fst` adds a schema-AST-indexed binder context
  and verifies the substitution recursion over Sigma/Refine. It still lacks
  proof that every target binder value inhabits the denotation of the
  capture-avoiding substituted declaration. It is not a sound typed-context
  theorem yet.
- `/tmp/A05SemanticsBool/WorkflowV2.SchemaSemantics.fst` proves the binder
  cases by explicit finite Boolean enumeration. This demonstrates that
  pointwise dependent-family reasoning need not require function
  extensionality; it is only a finite abstraction, not the actual semantics.
- `/tmp/A05SplitJTypeRefine.fst` verifies structural membership for
  Product/Sum/List/Option/Sigma and a native refinement carrier. Its
  package mapping and value syntax remain incomplete. The separate
  `all_typed` list judgment avoids the mutual-inductive universe failure of
  the first List attempt.

## Remaining A05 obligations

1. Define typed local and graph environments so each `Bound`, `Root`, and
   `Port` lookup uses the declared schema and exact carrier/value together.
2. Give `SchemaValue`, `SchemaPredicate`, and `SchemaType` one coherent
   denotation. Equality operands must share a statically established type and
   its exact codec/index; no callback may collapse distinct values.
3. Specify exact Atom/Family/Constructor/IndexCall package meanings and prove
   their row/token linkage. Constructor results and index calls must have the
   declared carrier and use the exact selected codecs.
4. Prove semantic substitution under a relation that also transports each
   declaration type to its capture-avoiding substituted type. Extend the
   relation under Sigma and Refine with the same candidate value.
5. Connect root, canonical constants, and prior ports to the actual graph
   environment; derive full-family LegalEnv prefix facts without narrowing
   external outputs.

No semantic prototype in this note closes the package adequacy or typed
`LegalEnv` obligations. A05 remains `in_progress`; no dependent DAG node has
started.
