# A02 Kernel minimal shapes

## Recommendation

Kernel needs first-order syntax only: preserve its current `wire`, node, and
`graph_desc` spine; add compact schema-expression datatypes and opaque typed
artifact refs. Keep denotation, equality derivations, `LegalEnv`, graph typing,
resolver, manifests, and resource-store laws downstream. A01 assigns schema
AST syntax and artifact-ref syntax to Kernel, but `LegalEnv`/denotation and
typing derivations to Schema; ManifestCore owns canonical entries and schema
rules (A01 §“Module ownership and imports”, lines 160–164).

### Schema syntax

Minimal AST needs three layers, since implementation spec §2.2.1 (lines
942–958) fixes `ValueDenote`, `TypeDenote`, `PredDenote` and three judgments:

```fstar
type schema_value (depth:nat) =
  | SVRoot : schema_value depth
  | SVBound : nat -> schema_value depth // require index < depth in smart constructors
  | SVUnit : schema_value depth
  | SVPair : schema_value depth -> schema_value depth -> schema_value depth
  | SVInl : schema_value depth -> schema_value depth
  | SVInr : schema_value depth -> schema_value depth
  | SVList : list (schema_value depth) -> schema_value depth
  | SVNone : schema_value depth
  | SVSome : schema_value depth -> schema_value depth
  | SVConstructor : SchemaIdentity -> list (schema_value depth) -> schema_value depth
  | SVIndexCall : SchemaIdentity -> list (schema_value depth) -> schema_value depth

type schema_type (depth:nat) =
  | STUnit : schema_type depth
  | STProduct : schema_type depth -> schema_type depth -> schema_type depth
  | STSum : schema_type depth -> schema_type depth -> schema_type depth
  | STList : schema_type depth -> schema_type depth
  | STOption : schema_type depth -> schema_type depth
  | STSigma : schema_type depth -> schema_type (depth + 1) -> schema_type depth
  | STFamily : SchemaIdentity -> list (schema_value depth) -> schema_type depth
  | STRefine : schema_type depth -> schema_predicate depth -> schema_type depth

and schema_predicate (depth:nat) =
  | SPTrue : schema_predicate depth
  | SPEqual : schema_value depth -> schema_value depth -> schema_predicate depth
  | SPAnd : schema_predicate depth -> schema_predicate depth -> schema_predicate depth
```

Treat constructors/families/index calls as exact manifest IDs, not callbacks.
Do not add arithmetic or arbitrary F* reflection absent a pinned terminating
sound-and-complete fragment. Required atoms/constructors and exact behavior are
implementation spec §2.2.1 lines 912–950; overview §3 says AST is restricted
workflow syntax, not compiler AST/reflection (lines 169–174). Keep validation,
substitution proofs, and derivation trees out of Kernel. Schema later owns
`LegalEnv`, denotation, normalization/equality, and typing derivation syntax.

Existing Kernel `wire` at lines 68–74 is already the minimal graph wire form:
root, prior-node key, codec ID + bytes constant, pair, projections. Existing
`graph_node` / `graph_desc` lines 76–87 store work ref and wires only. Keep
those first-order records; no closures, runtime values, or proof payloads.
Spec §2.2 lines 512–543 states exact graph shape and topological node list.

### Artifact refs

Required public shapes, in Kernel naming style:

```fstar
type artifact_type_identity
type artifact_store_identity
type artifact_ref (a:Type0)                 // opaque carrier
noeq type packed_artifact_ref =
  | PackArtifactRef : #a:Type0 -> artifact_ref a -> packed_artifact_ref
```

Consumers then use `list packed_artifact_ref`; typed package surface uses
`codec (artifact_ref a)` and resource projection uses
`a -> Tot (list packed_artifact_ref)`. Keep `ArtifactPackage` and its store
contracts outside Kernel. Spec §3 lines 1412–1437 requires opaque typed refs,
heterogeneous packing, exact manifest-selected ref codec, canonical tagged
encoding, and no cast. Lines 1442–1465 give projection/package signatures.

## F* pitfalls

- Spec's `PackedArtifactRef = exists a:Type0. ArtifactRef a` is mathematical
  shorthand. F* `exists` is proposition-sorted; `list` needs a `Type0` value.
  Use a Type-valued constructor carrying implicit `a` and `artifact_ref a`,
  then match by unpacking that constructor. Do not erase `a` to bytes/string.
- Keep `artifact_ref` abstract in paired `.fsti`/`.fst` API if opacity must
  survive clients; A01 `.fsti`, build, and trust policy says every owned
  interface must have one checked paired implementation (lines 210–232).
  Avoid exposing constructor/representation or generic casts.
- Existing source uses lowercase (`bytes`, `codec_identity`, `wire`) while
  spec CamelCase names are schematic. Keep one naming convention and qualify
  module references (`WorkflowV2.Kernel.*`) where sibling modules could
  collide. `type`, `list`, `option`, and `exists` are F* syntax/library names;
  prefer `schema_type` etc., not keyword-like names.
- Types/records holding functions or proof fields already use `noeq` in
  current Kernel (`codec`, `indexed_codec`, `code_ref`, `op_ref`). Keep `noeq`
  for opaque refs/packed packages where structural equality is not intended;
  use explicit canonical encodings/identity laws instead of equality on
  function-bearing records.
- `schema_type`/`schema_value` are syntax, not F* `Type0` denotations. This
  separation prevents accidental arbitrary type equality and keeps Kernel
  acyclic: no Bundle, ManifestCore, Schema, resolver, journal, or host import.

## Root integration decision

The implementation uses the spec's direct locally nameless `Bound(nat)` AST
rather than depth-indexing every expression. This keeps the durable grammar
identical to the specified grammar; `Schema` will prove scope/denotation
judgments over this finite syntax and reject out-of-scope indices. This does
not admit malformed expressions into a typed graph.

`artifact_ref a` is a type-indexed uninterpreted token, not an abstract
representation boundary in this first Kernel. `packed_artifact_ref` is
candidate syntax and can pair an identity with an unrelated carrier. This is
deliberate: it mirrors first-order graph syntax, which can encode unresolved
references. A manifest-selected artifact package must prove the exact
identity/carrier/codec link before canonical encoding or commit; P0/P9 and the
later Artifact module own that proof. No backing object or host handle is
encoded as this token. The boundary must not be described as making arbitrary
tokens published, canonical, or resolvable.
