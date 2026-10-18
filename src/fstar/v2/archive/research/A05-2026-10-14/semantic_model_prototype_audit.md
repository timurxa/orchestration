# A05 semantic-model prototype audit

This is scratch-prototype evidence, not integrated A05 source. The checked
files are under `/tmp` and are not part of the project build.

Codec proof evidence is tracked separately in
[`codec_proof_attempts.md`](codec_proof_attempts.md); the earlier framed
codec attempt was not verified and is not evidence for this semantics audit.

## Relational model

`/tmp/A05ManifestRel.fst` verifies with F* cache disabled. It uses an indexed
manifest lookup, heterogeneous argument lists (`hlist`), value/type
denotation relations, and dependent `Sigma`/`Refine` carriers. This is a
promising shape for avoiding casts and avoiding equality between separately
loaded closures. Exact identity lookup selects one package as a function of
the identity.

Audit found material gaps that prevent source integration as-is:

- the scratch key is `nat`, and `present` plus `lookup` is not linked to a
  canonical `registry_manifest` row or the exact pinned bundle projection;
- constructor results are not constrained to their declared parent family;
- `Bound` reads an untyped existential environment, so a typed local-context
  relation is needed before the result can support schema typing;
- `Root`, `Port`, and canonical `Constant` denotations are absent;
- no graph-prefix `LegalEnv`, generated context, or general substitution
  preservation theorem is present.

`/tmp/A05ConstructorTyped.fst` verifies the constructor fix: a constructor
package is indexed by its exact parent family package, supplies a total index
function, and builds a value directly in the family carrier at those indices.
This should be adapted to `schema_identity`, the real AST, and the pinned-row
contract. It does not itself prove manifest-row provenance.

`/tmp/A05SigmaRefineCommute.fst` verifies one closed environment-weakening
example for `Sigma Unit (Refine Unit True)`. It rebuilds the denotation
structurally with no admission. It is evidence for the binder design, not the
required general substitution theorem.

## Typed-context GADT audit — 2026-10-14

`/tmp/A05CarrierTypedAST2.fst` improves `Bound`: `schema_context` pairs each
schema declaration and carrier in one constructor, and a single
`schema_member` witness retrieves the value at that same slot. The module
verifies cache-off and demonstrates Nat, Sigma, and `Refine(_, True)` carrier
shapes. The syntax/carrier telescope is structurally aligned; a separate
carrier-membership witness is unnecessary and should not be reintroduced.

The prototype is **not sound as a general schema interpretation** because its
`predicate_semantics` is caller supplied and unconstrained. The verified
counterexample `/tmp/A05PredicateOracleCounterexample.fst` supplies
`always_true`, derives `SchemaRefine SchemaNat SchemaFalse` as
`{x:nat | true}`, and stores `5` in a supposedly well-formed context. The
schema semantics must instead define `PredDenote` structurally from typed
`ValueDenote` judgments and exact symbol packages, or require a proof-bearing
package law whose conclusion is that exact structural judgment. A bare
function parameter is an unsound oracle.

There is a second proof boundary: `JType` constructors in the prototype can
derive types at contexts without a `JCtx` well-formedness derivation. This can
be safe if the eventual soundness theorem explicitly assumes the matching
context derivation and all semantic judgments remain indexed by the exact
paired context/value environment. It is not safe to claim unconditional
well-formedness or substitution preservation. Either carry context-WF
evidence into each derivation or state and prove the required admissibility
lemma for the judgments used by LegalEnv.

Exact counterexample verifier command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp --odir /tmp/a05-predicate-audit \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  /tmp/A05CarrierTypedAST2.fst \
  /tmp/A05PredicateOracleCounterexample.fst
```

The command verifies, which is the expected result: the counterexample is
well-typed and exposes the missing predicate contract. It is a rejection of
the prototype's soundness claim, not an implementation theorem.

## Exact manifest-row package prototype — 2026-10-14

`/tmp/A05ExactDenotationPackage.fst` verifies family and rule package
interfaces indexed by the canonical manifest and schema identity. Each
package contains selected-row, decoded-expression and law-projection
equalities. Its `SchemaDenotationLaw` field is a derivation of the exact
`JType` judgment for every inhabitant of the package's carrier, rather than an
unconstrained `carrier -> prop` callback. P0 must prove the existing Bundle
lookup returns this exact package object for the identity.

Exact cache-off command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp --odir /tmp/A05exactbuild \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/A05UnifiedTypedAST.fst /tmp/A05ExactDenotationPackage.fst
```

All seven modules and all VCs verify; these scratch files contain no `assume`
or `admit`. Limits: the denotation law covers only `SCEmpty/HNil`; the probe
omits Atom/Family/Constructor/IndexCall rules and retains the predicate-oracle
and context-WF gaps above. It is soundness-only; carrier completeness requires
the structural interpreter to determine the carrier, not a package-selected
arbitrary or vacuous carrier. Generalize the law to typed contexts and bind
the exact proof-bearing package to the existing P0 projection before source
integration.

## Contracts to preserve in source

The schema package map must be indexed by the exact schema identity and linked
to the canonical manifest projection. A05 cannot import the later Bundle or
GraphResolver without creating a cycle; it should define a manifest-indexed
package contract and let A04/P0 prove that the Bundle supplies that exact map.
There must be one selected package per identity, with no second editable
signature table.

`LegalEnv` is an inductive prefix relation. Its base fixes the exact root and
canonical decoded constants. At each prior node it evaluates the declared
input wire and extends with **any** inhabitant of that node's full declared
output family at the reconstructed input. It does not assume a validator
postcondition, observe an execution, or narrow the family. A04 supplies the
pinned work/codec linkage; the A05 model must leave the complete quantifier
available to A06/A07.

Semantic substitution is conditional on a semantic substitution relation:
each source binder value must be represented by a target-side schema value
that denotes that same value. Under `Sigma` and `Refine`, extend this relation
with `Bound 0` for the newly bound candidate and lift the previous mappings.
This is the condition needed for denotation preservation; arbitrary F* values
need not be quoteable in the schema syntax.

The prototype uses `squash` only to place relational facts inside
propositions; it has no `FStar.Classical`, `unsquash`, `assume`, or `admit`.
The final source path still needs a transitive trust audit.

## Next proof work

1. Parameterize denotations by the actual Kernel AST and exact manifest row;
   do not allow a caller-supplied predicate oracle.
2. Add a typed local binder context and root/port/constant semantic lookup,
   with explicit context-WF premises or an admissibility theorem.
3. Tie constructors and index calls to their exact package signatures and
   family result carriers.
4. Define `LegalEnv` for every finite prefix and prove its generated context
   facts, especially refinement facts via capture-avoiding substitution.
5. Prove general value/predicate/type denotation preservation under the
   semantic substitution relation, including `Sigma` and `Refine`.
6. Integrate only after the full configured verifier and source trust audit
   pass.

## Extended sound-nucleus scratch — 2026-10-14

`/tmp/A05SoundNucleus.fst` was extended and reverified cache-off. It retains
the paired AST/value `context_wf` and structural predicate evaluation. The
extension adds Product/Sum/List/Option carrier representations, semantic
values/equality, a pair literal rule, and verifies generic evaluation of
supported `value_denote`/`predicate_denote` judgments plus `value_typed_sound`.
It also checks a concrete locally nameless substitution example traversing
Product/Sum/Refine/Option/List and confirms a substitution under a binder keeps
the nearest `Bound 0` while replacing outer `Bound 1`.

Command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/A05SoundNucleusBuild /tmp/A05SoundNucleus.fst
```

All scratch VCs discharge; only imported ulib warning 271 remains. This is a
limited feasibility result, not the full denotation. `type_accepts` still
rejects List; Kernel's value AST has no Sum/List/Option constructors, so these
exist only at the carrier layer. There is no general theorem relating the
selected `carrier`/`to_sem` interpretation to AST denotation and semantic
acceptance. No source integration or A05 acceptance is claimed. The next
semantic step must align the full Kernel AST with one indexed semantics,
manifest-selected symbol packages, dependent binders, and `LegalEnv`.

## Independent semantic architecture audit — 2026-10-14

An independent review confirms the minimum useful architecture is a single
carrier-indexed family of typed denotations, not independent callbacks or
carrier maps:

- `TyDenote(manifest, Γ, Ξ, T, A)` relates exact type syntax `T` to its
  carrier `A` under paired, well-formed schema/carrier contexts `Γ/Ξ`.
- `ValDenote(manifest, Γ, Ξ, e, A, v)` and
  `PredDenote(manifest, Γ, Ξ, p, proposition)` evaluate values and predicates
  structurally. Equality consumes values already denoted at a common carrier;
  no caller-supplied predicate oracle.
- `Sigma(A,B)` uses a dependent pair whose codomain judgment extends both
  contexts by the exact candidate. `Refine(T,P)` is a subset whose proof
  comes from `PredDenote(P, Ξ⋅candidate)`.
- `Bound` uses one nearest-first witness pairing schema binder types and
  carriers, gated by context well-formedness. Root, port, and constant forms
  are rules in the same value judgment; ports reference only prior LegalEnv
  slots, while constants require the exact codec row and canonical decoding.
- Atom/Family/Constructor/IndexCall cases select the exact manifest row,
  syntax, law token, and package field. Constructor results must be at the
  exact parent family and computed indices. Index-call interpretation is
  total and its equations are the declared exact package laws.
- `LegalEnv` fixes root and constants, then extends each graph prefix with
  every inhabitant of the full declared output family at its reconstructed
  input. External validator postconditions never narrow this quantifier.

The required proof sequence is: context admissibility; soundness for type,
value, and predicate judgments; exact symbol-package linkage; semantic
substitution under a relation mapping each source binder to a target
expression with equal denotation; generated-context facts; prefix induction
for `LegalEnv`; then universal edge soundness. Completeness must be stated
exactly for the declared `SchemaSupported`/manifest calculus and representable
values; it does not mean quoting every arbitrary F* value or reifying every
`Type0`.

Additional audit points: package-selected arbitrary carriers can make laws
vacuous unless the carrier is fixed by structural denotation; identity lookup
alone does not bind the package to the manifest field; indexed constants need
the exact input index; unpaired context judgments cannot justify lookup;
arbitrary F* values need not admit schema quotes. Existing Kernel value syntax
has no Sum/List/Option literals; package constructors may represent declared
data, but the system must not claim unrestricted value quotation. This audit
does not change A05 acceptance or source status; it orders its proof work and
records where soundness/completeness are bounded.

## Exact-row package bridge falsification — 2026-10-14

A scratch bridge `/tmp/A05PackageVacuity.fst` composes the integrated
`selected_family_components_from_same_row` fact with a package whose type is
indexed by the exact `manifest_contract_ref`. It proves that the selected row
wire decodes to the package's schema expression and that the row law token is
the package index. The scratch module and the bridge verify cache-off with
F* 2026.03.24/Z3 4.13.3.

The experiment also falsifies a tempting adequacy argument. The package can
choose carrier `False`; then its denotation law is inhabited by elimination
for every schema expression. Therefore exact token indexing plus soundness of
an arbitrary package law does not establish that the carrier actually
represents the AST. The contract needs structural `TyDenote`/carrier
interpretation, or an equivalently strong completeness/equivalence law. The
actual lookup from a token to that exact proof-bearing package still belongs
to A04/P0 and is not present in the current modules.

No source edits were made from this scratch. It proves a boundary failure,
not A05 semantic adequacy. `LegalEnv` also remains unconnected to graph wire
values, root input, ports, and `Work` output families.
