# A05c typed-value and dependent-argument scratch

## Result

`/tmp/A05JArgsParam.fst` verifies a small context-indexed value judgment with
`JValueNat` and `JValueBound`. `j_value_denote` is total and returns the exact
value selected by the derivation (`n` for a natural literal, `context_lookup`
for a bound variable). A generic argument derivation uses this projection to
select later dependent carriers and is indexed by its exact dependent tuple.
The example covers a natural literal, a bound variable, and an argument whose
type is affected by a previous actual syntax argument.

The representation lesson is to index the argument derivation by both its
carrier telescope and its actual argument tuple. Do not try to recover the
tuple afterward by recursively matching a generic telescope index: the
telescope is `noeq` and contains a dependent function, and F* will not expose
the constructor shape through that index for the required result type. An
explicit tuple index makes each constructor establish its tuple directly and
avoids casts and function extensionality.

## Proof boundary

This is scratch evidence, not an integrated theorem or accepted public API.
Its context lookup is carrier-only. `JValueBound` proves that a value belongs
to a carrier slot, but does not relate that slot to its schema type AST. The
example covers only NatLit and Bound(0), not products, sigma/refinement,
root, port, constants, constructors, index calls, or predicates. It does not
prove canonical type interpretation, package adequacy, equality reflection,
semantic substitution, or `LegalEnv`.

The integrated `WorkflowV2.SchemaJudgments.fst` currently uses a parameterized
value-relation family and a `unit` shape witness; it is only dependent
argument-telescope scaffolding. The scratch result indicates how to replace
that placeholder once the paired dependent AST/carrier context relation is
proved. Until then A05c remains active.

## Verifier evidence

Scratch path: `/tmp/A05JArgsParam.fst`; build directory:
`/tmp/A05JArgsParamBuild`. Command passed with exit 0 and all VCs discharged:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src \
  --include /tmp/A05JArgsParamBuild \
  --odir /tmp/A05JArgsParamBuild \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
  /tmp/A05JArgsParam.fst
```

`/tmp/fstar-a05c-universe/BoundSyntax.fst` is an independent verified
prototype for a dependent carrier telescope and prior-bound lookup at
`vec 4`; it does not connect each AST binder to its carrier. The corresponding
cache-off command is recorded in the originating agent result in this run.

The follow-up `/tmp/fstar-a05c-universe/ContextJValue.fst` pairs a
newest-first AST context with a dependent carrier/value environment. It
structurally proves that `SchemaBound 0` yields `V : vec 4` and
`SchemaBound 1` yields `4 : nat`, after proving the indexed Vec type denotes
`vec 4`. Its tiny `j_type` relation covers unit/bool/nat/int, product, sum,
list, option, and the example indexed Vec. Its `j_value` relation covers
bound, unit/bool/nat/int, and product forms. It does not establish that each
context entry's carrier inhabits the denotation of its AST declaration; the
paired lookup only ensures both sides select the same de Bruijn position. It
also omits Sigma/Refine, predicates, package-selected families/rules,
root/port/constants, and sum/list/option value syntax. Exact command passed
for `Kernel` and `ContextJValue`, all VCs discharged:

```sh
cd /Users/alex/areas/productive/orchestration/src/fstar/v2
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src --include /tmp/fstar-a05c-universe \
  --odir /tmp/fstar-a05c-universe \
  src/WorkflowV2.Kernel.fst \
  /tmp/fstar-a05c-universe/ContextJValue.fst
```

An alternative `/tmp/A05SchemaArgValues.fst` uses a GADT spine for argument
tuples and proves recursive extraction from the derivation. This verifies,
but converting its spine back to the package's `schema_arguments_denote`
`dtuple2` alias fails at the same opaque dependent-telescope boundary. That
approach would require changing package callbacks to consume the GADT. The
integrated source instead indexes its derivation by the exact `dtuple2` value
and needs no extraction; it preserves the existing package interface. The
GADT prototype itself verified with this command (all imported modules and
scratch VCs discharged):

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp/fstar-v2-check --include /tmp \
  --odir /tmp/A05SchemaArgValuesBuild \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
  /tmp/A05SchemaArgValues.fst
```

## Paired typed-context follow-up

Two further cache-off scratch proofs retain the declaration type witness:

- `/tmp/fstar-a05c-universe/ContextJValuePaired.fst` defines a paired context
  whose entries store prior-prefix `j_type` and `j_context_value` proofs.
  Lookup at the same de Bruijn index returns the declaration-prefix type
  witness and reconstructs the corresponding full-context `j_bound` path.
  Its example has context `[Vec Bound(0); Nat]`; lookup at index 1 proves the
  earlier value is `4 : nat`. The Vec value rule is hardcoded to one closed
  constructor `V` at `vec_id`; this is not package-selected interpretation.
- `/tmp/fstar-a05c-paired-context/ContextSigma.fst` additionally verifies
  `Sigma Nat (Vec Bound(0))` at carrier `dtuple2 nat (fun n -> vec n)` and a
  context lookup for `Nat` / `Vec n`. Its Sigma and Vec rules are specialized
  to this example.

Paired lookup is not yet a general `JValue` typing theorem in the full
context: a dependent declaration's type witness is at its declaring prefix,
so general use beneath later binders needs the weakening/substitution bridge
scheduled in A05e. The examples do not cover general Sigma/Refine, predicates,
root/port/constants, or selected family/rule packages. Both remain scratch
only. Exact commands and acceptance limits are in `node_summaries.md` and
`run_log.md`.

Neither scratch file is included in the project build or counted as A05c
acceptance. Their purpose is to guide the integrated proof without weakening
the DAG obligations.

## Structural Sigma relation and proposition boundary

`/tmp/fstar-a05c-generic/SigmaRecursiveDtuple.fst` verifies the Nat/Sigma
fragment using structurally recursive functions
`j_type ... : Tot Type` and `j_value ... : Tot Type`. Its Sigma clause selects
`a : Type0` and `b : a -> GTot Type0`, identifies the carrier with the
existing `dtuple2 a b`, proves the domain relation, and proves the codomain
relation for every `x:a` under both the extended schema context and runtime
environment. The value clause aligns `SchemaPairValue` with `Mkdtuple2 x y`
and recursively checks both sides. The exact cache-off command passed all VCs:

```sh
opam exec -- fstar.exe --cache_off \
  --include src/fstar/v2/src \
  --include /tmp/fstar-a05c-universe \
  --include /tmp/fstar-a05c-generic \
  --odir /tmp/fstar-a05c-generic \
  /tmp/fstar-a05c-generic/SigmaRecursiveDtuple.fst
```

This is evidence for a proof shape, not an integrated or complete semantic
judgment. It covers only Nat and Sigma; it imports the paired context module,
does not prove arbitrary context declaration/carrier alignment or weakening,
and says nothing about predicate/refinement or manifest-selected callbacks.
An inductive constructor carrying the recursive codomain judgment under
`forall x` failed with F* Error 67 (universe inequalities), whether the
carrier was `dtuple2` or a custom Sigma datatype. The same generic recursive
function succeeds with `dtuple2`, so changing the public carrier is not
needed. A separate attempt to put proof evidence in a `Type0` carrier failed
with Error 34; runtime carriers/values and semantic evidence must stay
separate.

Universe probes under `/tmp` distinguish type-valued derivation evidence from
F* propositions. `/tmp/UniverseEvidenceGood.fst` verifies a `Type0` JValue
derivation, a JPredicate derivation indexed by the same semantic value, a
soundness lemma extracting equality, and a native subset refinement. The
negative `/tmp/UniverseEvidenceBad.fst` fails because a `Type0` judgment
cannot itself be assigned to `prop` (`Expected type Prims.prop got type
Type0`). `/tmp/UniverseLetRecGood.fst` shows a `Tot Type` recursive family
can be supplied as a derivation witness, but that does not make it a logical
proposition. Exact commands:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include /tmp/universe-good-build --odir /tmp/universe-good-build \
  /tmp/UniverseEvidenceGood.fst
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include /tmp/universe-letrec-build --odir /tmp/universe-letrec-build \
  /tmp/UniverseLetRecGood.fst
```

Both passed with all VCs discharged. The negative probe was run with the same
cache-off flags and failed at the intended assignment. The integration
implication is precise: predicate denotation used by native
`{x:a | predicate x}` must have sort `prop`; a JValue derivation is not that
predicate. `SchemaEqual` must use exact same-carrier typed operands and a
soundness bridge that extracts equality. `SchemaRefine` must extend the
context with its candidate and use the resulting proposition-valued
predicate. This is a design constraint for A05c, not a resolved A05c theorem.

## Canonical carrier-plus-shape package — 2026-10-14

The direct recursive `TypeDenote : expr -> Tot Type0` experiment did not
provide a safe way for `JValue` to eliminate a dependent Sigma carrier: the
recursive denotation remained opaque at the needed pair type, and separately
reconstructed GADT witnesses were not equal (nor should the design rely on
function extensionality). A more promising representation returns the
canonical carrier together with a sealed, constructor-indexed witness of its
shape. `TypeDenote` is the carrier projection, while typed judgments consume
the exact package returned by that interpreter invocation. This avoids
reconstructing the dependent codomain witness and does not require a theorem
equating two separately computed functions.

Verified fragment: `/tmp/A05cCanonicalVecWitness.fst` defines a canonical
`(carrier, carrier_witness)` result for Nat, `Vec n`, and `Sigma Nat (Vec
Bound(0))`, then indexes `JValue` by that exact witness. A Sigma value
`Mkdtuple2 n xs` typechecks using the same canonical `WSigma` witness. The
scratch also confirms that `(n:nat & vec n)` is not definitionally identical
to `dtuple2 nat vec`; explicit conversions in both directions verify. The
chosen result carrier stays `dtuple2 nat vec`. Exact cache-off command:

```sh
opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
  --odir /tmp /tmp/A05cCanonicalVecWitness.fst
```

Root reran it: exit 0; the module verified and all VCs discharged. This is a
hardcoded fragment, not a recursive interpreter for the Kernel AST, not a
context-indexed denotation, and not package-aware. An attempted standalone
carrier projection from the canonical function result is opaque under a
second call; production judgments should receive and reuse the exact result
package rather than recompute it. Hide the witness constructors at the
`.fsti` boundary, otherwise callers could choose an alternate carrier.

`/tmp/A05cTypedSigmaDenotationPair.fst` separately verifies a dependent
Sigma shape and the concrete inhabitant `Mkdtuple2 4 (V #4)` when the GADT
uses F*'s native dependent-pair notation. Directly substituting `dtuple2`
into that GADT result changes the indexed carrier and is rejected, despite
ordinary function-level conversions. The implementation must pick one exact
carrier representation per public schema form; the canonical package/value
fragment above demonstrates the existing `dtuple2` route.

Historical candidate: a hidden package stored both a carrier and a shape
witness. The later shape-only representation below supersedes it: the package
is the exact shape witness and the carrier is computed from that witness, so
there is no redundant carrier field or equality proof. All judgments still
consume the same exact package. Remaining work is the full schema AST and
typed context, exact package-selected family/rule carriers, shared-carrier
typing for unannotated equality operands, and proposition-valued
`PredDenote` / native Refine soundness.

## Predicate evidence GADT — 2026-10-14

`/tmp/A05PredicateEvidenceGADTVerified.fst` verifies a way to avoid combining
separately squashed predicates: `predicate_evidence rho p` is a Type-valued
GADT indexed by the real `schema_predicate_expr`; `PAnd` contains both raw
recursive evidence terms, and `PEqual` contains an `equal_witness` whose two
typed operands share the exact carrier `a` and whose equality is constructively
represented as `squash (Prims.equals x y)`. Define
`PredDenote rho p = squash (predicate_evidence rho p)` once at the outer
boundary. `SchemaAnd(True, Equal(n,n))` then has a direct evidence constructor
and its single outer squash verifies. This avoids the failed approach of
proving a conjunction from separately truncated subproofs. The evidence
construction uses no `Classical.exists_intro` and no arbitrary callback.
This fragment carries native F* equality only; it does not yet consume the
exact manifest-selected codec or prove the codec-equality-reflection path
required by the A05c DAG acceptance.

Exact independently rerun command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05-predicate-evidence-gadt-verified-build \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  /tmp/A05PredicateEvidenceGADTVerified.fst
```

Exit 0; both modules verified and all VCs discharged. Warning 271 is from
F*'s `FStar.UInt` theory-pattern annotation. The scratch also contains a
direct recursive `type_denote`; using it for a native `SchemaRefine` subset
still fails because the projected recursive result remains opaque, even when
the exact predicate is supplied. This is consistent with the canonical
carrier-plus-shape package, but the combination has not yet been verified for
Refine. A separate attempt to bridge an indexed value judgment to an
existential uses `FStar.Classical.exists_intro`; it is optional and must not
be an implementation requirement without an audited need. The verified GADT
fragment does not establish arbitrary predicate semantic soundness, context
typing, exact package interpretation, or full-AST coverage.

## Canonical package Refine fragment — 2026-10-14

`/tmp/A05CanonicalPackageRefine.fst` verifies the previously missing small
case: native `SchemaRefine` can be built and eliminated if JValue consumes the
same canonical package as the base judgment. The schema shape is indexed by
the exact AST. `ShapeRefine` carries the base shape; `shape_denote` produces
the native subset `{x:base | pred_denote ...}`. `JRefine` stores both the base
`JValue` and constructive predicate evidence, and uses those exact terms to
build the subset inhabitant. Pattern matching a refined JValue recovers its
base JValue. The example is Nat with reflexive equality `7 = 7`; it uses no
admission, Classical choice, or function extensionality.

Exact cache-off command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05-canonical-package-refine-build \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  /tmp/A05CanonicalPackageRefine.fst
```

Exit 0; both modules verified and all VCs discharged. This proves only the
small Nat/Refine package connection. The equality evidence uses native
`Prims.equals` at an exact Nat carrier. It does not use the manifest-selected
codec/index or establish equality reflection, arbitrary predicate
soundness, a context-indexed interpreter, package adequacy, or full-AST
coverage. The direct recursive `TypeDenote` projection remains rejected; this
success specifically reuses one exact package.

## Hidden package interface experiment — 2026-10-14

F* 2026.03.24 accepts a constructor-hidden package *type family* in `.fsti`:
`val package : schema_type_expr -> Type0` (or an equivalent universe-1
signature). The `.fst` may implement the family as a private `noeq` record
containing the carrier and shape witness. A judgment can be indexed by that
exact package and its carrier projection. Two scratch checks passed:

- `/tmp/TestCanon.fsti` and `.fst` use the real Kernel `schema_type_expr`,
  abstract `package` family, private `noeq` implementation, carrier
  projection, and package-indexed judgment. Command:
  `opam exec -- fstar.exe --cache_off --warn_error @285 --include
  src/fstar/v2/src --odir /tmp /tmp/TestCanon.fst`. Exit 0; all VCs
  discharged. This is the Nat shape fragment.
- `/tmp/A05cSealedPackage.fsti`/`.fst` expose the abstract type family plus
  `canonical`, `carrier`, and a carrier law, with private `package_impl`.
  The client `/tmp/A05cSealedClient.fst` imports the interface and uses only
  those exports; it also verifies with all VCs discharged. Commands:

  ```sh
  opam exec -- fstar.exe --cache_off --warn_error @285 --odir /tmp \
    /tmp/A05cSealedPackage.fsti /tmp/A05cSealedPackage.fst
  opam exec -- fstar.exe --cache_off --warn_error @285 --include /tmp \
    --odir /tmp /tmp/A05cSealedClient.fst
  ```

This distinguishes the viable AST-indexed abstract type-family alias from an
unindexed term-level opaque handle: the latter loses the AST/carrier
relationship and cannot express the required exact judgment index. It
establishes constructor hiding for a fragment, not yet for a package indexed
by the full dependent context. That context-indexed signature, including
Sigma and Refine, still needs verification before source integration.

## Declaration-prefix Bound lookup fragment — 2026-10-14

`/tmp/A05cPrefixEnv.fst` verifies a paired schema/carrier context shape for
Nat and Unit, with a nearest-first member path. It proves that `SchemaBound 0`
selects the `SchemaNat : nat` slot. Exact command:

```sh
opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
  --include src/fstar/v2/src --odir /tmp /tmp/A05cPrefixEnv.fst
```

Exit 0; all VCs discharged. The paired slot uses the same de Bruijn member
index on each side. This is not yet an actual runtime-environment lookup
relation: selected-value evidence carries its own value instead of projecting
from one environment object. It covers no dependent weakening, Sigma/Refine,
Root, Port, Constant, or package-backed values. A05e/A05f still own those
proofs.

## Shape witness package candidate and context failure — 2026-10-14

The required invariant is one sealed canonical package: it is indexed by the
exact context and AST, controls the carrier and shape, and is reused by every
judgment. A shape-only package makes `package Γ t` an abstract type family
whose internal representation is `schema_shape Γ t`; its carrier is
`package_carrier p = shape_denote p`. This removes a duplicate carrier field
and equality proof. A dependent existential with the carrier as the witness's
type index could satisfy the same invariant. Shape-only is a candidate, not
yet the integrated choice: a locally modeled dependent-`hlist` Refine attempt
below fails because the carrier projection is too opaque at subset
introduction. Do not switch to an independent carrier plus an unrelated
witness/equality to work around it.

`/tmp/A05cShape.fsti`/`.fst`/`A05cShapeClient.fst` verify constructor hiding
and client-visible Sigma/Refine value builders. The toy context is `nat`, and
the toy type AST has only Nat, Sigma, and Refine tags; the dependent Sigma
carrier is `dtuple2 nat vec`, and Refine is the native subset
`x:nat{x == 7}`. The exported `sigma_value`/`refine_value` functions produce
terms at the opaque projected carriers; exported JValue helpers construct
checked evidence. The client compiles while using only these signature
exports. Exact two-stage commands:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include /tmp --odir /tmp/a05c_shape_build6 \
  /tmp/A05cShape.fsti /tmp/A05cShape.fst
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include /tmp/a05c_shape_build6 --odir /tmp/a05c_shape_build6 \
  /tmp/A05cShapeClient.fst
```

Both pass with all VCs discharged. The package shape is indexed by its toy
AST/context and is not selected by callers. The fragment does not establish
that the same representation works for the real `schema_type_expr`, actual
dependent context telescope, recursive AST interpretation, package-selected
values, or general JValue soundness.

Independent interface work in `/tmp/a05c-interface/sigma/S.fsti` and
`S.fst` confirms an abstract `val package : ty -> Type u#1` can be implemented
by an alias to a private noeq package record; a private Sigma JValue GADT and
native Refine package also verify. This is a *type family*, not an unindexed
term-level `eqtype` handle. A public client cannot assume that an abstract
`carrier (make_sigma)` reduces to `dtuple2` or raw `nat`; expose canonical
value constructors, checked JValue builders, carrier equality laws, or
eliminators needed by clients. Do not make clients rely on hidden definitional
reductions. The package API design is viable, but full context-indexed value
and proof interfaces remain open.

An earlier carrier-indexed record constrained to the smaller package
universe hit F* Error 197 / Error 67. Do not generalize this to all
carrier-indexed witnesses: the dependent existential below raises the
package family to `Type u#1` and verifies. The direct `TypeDenote` route and
unindexed handle remain rejected.

### Actual Kernel `hlist` context probe — 2026-10-14

`/tmp/A05CanonicalPackageRefine2.fst` attempts a package shape indexed by the
actual Kernel `schema_type_expr` and a locally modeled dependent carrier
context `hlist rho` (it does not import `SchemaSemantics.hlist`). Its
`ShapeRefine` stores the base shape; `shape_denote` is the
native subset `{x:base | pred_denote ...}`. Unlike the toy context, the exact
package is a projection from a context-indexed canonical package. The proof
of subset introduction fails before the JValue proof: cache-off F* reports
Error 189 because it cannot establish that
`package_carrier HNil refine7_package` has the expected native subset type.
The reproducing command is:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05c-refine2-build \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  /tmp/A05CanonicalPackageRefine2.fst
```

This is an opacity/elimination problem in this encoding, not a counterexample
to Refine or to the one-package invariant. The production
`SchemaSemantics.hlist` has not yet been tested in this example.

Next compare, at this same context and AST, a dependent existential
`(carrier:Type0 & shape rho t carrier)` whose carrier is definitionally tied
to the witness, plus an indexed `.fsti` client exposing the necessary
builders/eliminators. Keep explicit whether clients need to unfold the
carrier; they must not depend on a hidden reduction. Do not count the failed
probe as A05c acceptance evidence.

### Dependent existential with production `hlist` — 2026-10-14

`/tmp/a05actual-interface/A05ActualContext.fst` imports the production
`WorkflowV2.SchemaSemantics.hlist` and the Kernel AST. Its shape is indexed by
context, schema type, and carrier: `shape rho t a`. The package is the
dependent existential `a:Type0 & shape rho t a`; the carrier projection is
the existential's first component, while the proof-bearing shape is indexed
by that exact carrier. This is not an independent carrier plus equality
proof. The package family must live at `Type u#1`, with carrier at `Type0`.

The interface and implementation verify with all VCs:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --odir /tmp/a05actual-interface \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/a05actual-interface/A05ActualContext.fsti \
  /tmp/a05actual-interface/A05ActualContext.fst
```

It builds Nat and `Sigma Nat Nat`, constructs pairs, projects the first
component, and proves the projection result. A client with only the public
`.fsti` available also verifies, all VCs discharged:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp/a05actual-client \
  --odir /tmp/a05actual-client /tmp/a05actual-client/Client.fst
```

The production-context Sigma codomain is still Nat, not dependent on the
first component. `/tmp/A05cContextShape.fst` separately verifies a
`SchemaSigma SchemaNat (SchemaFamily fid [SchemaBound 0])` value at
`dtuple2 nat (fun n -> vec n)`, using a locally modeled context and a
structural `JPair` with the same codomain witness. Root reran this scratch
cache-off; all VCs discharged. The dependent codomain still needs to be
ported to production context and the public interface.

### Sealed JValue interface and actual-context Sigma/Refine fragment

`/tmp/a05actual-interface/A05ActualJValue.fst` extends the production-context
existential shape with private Nat, dependent `JPair`, and
`SchemaRefine ... SchemaTrue` constructors. `JPair` takes the exact
domain/codomain shape witnesses; its codomain witness is indexed under
`HCons x rho`. `JRefineTrue` carries a base JValue at the same exact shape.
The implementation passes cache-off with all VCs:

```sh
opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
  --include src/fstar/v2/src --include /tmp/a05actual-interface \
  --odir /tmp/a05actual-interface \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/a05actual-interface/A05ActualJValue.fsti \
  /tmp/a05actual-interface/A05ActualJValue.fst
```

The public `.fsti` hides both shape and the inductive JValue. It exports
`package_jvalue` as an abstract type-family function implemented by a `let`
alias to the private GADT, plus carrier smart constructors, JValue builders,
eliminators, and a projection theorem. Do not expose the inductive as an
abstract `val ... -> Type`: F* reports Error 197 because a function-valued
abstract type family does not match the inductive declaration. Likewise,
because `package_carrier` is opaque, clients cannot index results directly
at raw `Mkdtuple2 n m` or `n`. Export `sigma_nat_nat_value` and
`nat_refine_true_value` returning the opaque carriers, then index the JValue
builders at those exact functions.

The isolated client has only the `.fsti` in its include path. It constructs
Sigma and True-refinement values, extracts the pair projection and underlying
refined value, and uses the projection theorem. It verifies cache-off with
all VCs:

```sh
opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
  --include src/fstar/v2/src --include /tmp/a05actual-jvalue-client \
  --odir /tmp/a05actual-jvalue-client \
  /tmp/a05actual-jvalue-client/JValueClient.fst
```

Root independently reran implementation and client successfully. This proves
that a practical opaque interface can expose proof-relevant constructors and
eliminators. Refine is only `SchemaTrue`; no equality predicate, full
predicate semantics, production-context Bound/Port/Constant, package-selected
family/rule, full-AST JValue soundness, or dependent VecBound0 codomain is
covered by this interface fragment.

### Production-context dependent refinement and AST evaluation — 2026-10-14

`/tmp/A05cActualContextExists.fst` adds a separate fragment over the actual
`WorkflowV2.SchemaSemantics.hlist`. It indexes a shape witness by context,
Kernel type AST, and exact carrier. A Sigma carrier is
`dtuple2 nat (fun n -> x:nat{x == n})`; its codomain shape lives under
`HCons n rho`. The AST refinement compares `SchemaBound 0` with
`SchemaBound 1`, so the example makes a dependent predicate over the pair's
first component and an outer context variable.

The scratch defines a small evaluator for this exact value/predicate subset
and proves that an inhabitant of the selected refinement carrier makes the
AST predicate evaluate to `Some true`. Cache-off command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05c-exists-build \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/A05cActualContextExists.fst
```

Root reran it: all six dependencies and the scratch module verify; all VCs
discharged. This is evidence that production-context dependent Sigma and a
nontrivial bound-variable refinement are expressible. It is not the generic
`JPredicate` evaluator: the evaluator handles only Nat bound/literal values
and equality in this example, and the JValue rule is specialized to this
Sigma. It does not prove all AST constructors, package-selected constructors,
or the general `JValue`/`JPredicate` soundness theorem.

### Production-context dependent family codomain — 2026-10-14

`/tmp/A05cActualVecSigma.fst` imports the production Kernel and
`SchemaSemantics.hlist`. It verifies a Sigma with AST
`SchemaSigma SchemaNat (SchemaFamily family_id [SchemaBound 0])` and carrier
`dtuple2 nat (fun n -> vec n)`. The codomain shape is indexed under
`HCons n rho` at `vec n`, and a structural JValue constructor checks the
pair's second component against that exact dependent carrier.

Cache-off command, independently rerun by root:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05c-actual-vecsigma-root \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/A05cActualVecSigma.fst
```

All six dependencies and the scratch module verified; all VCs discharged.
The example's `family_id` and `vec` interpretation are hardcoded in the
scratch shape constructor. It does not select `schema_family_package`, prove
the package's indexed codec is used, or establish package adequacy. It proves
that production-context dependent Sigma/Vec wiring is expressible, not the
generic family rule or A05c soundness.

### Builtin shape and value fragment — 2026-10-14

`/tmp/A05cSimpleShapes.fst` uses the actual Kernel AST and production
`WorkflowV2.SchemaSemantics.hlist`. The shape interpretation covers Unit,
Bool, Nat, Int, Product (`dtuple2`), Sum (`either`), List, and Option. Its
JValue constructors cover Unit/Bool/Nat/Int literals, product pairs, and
Fst/Snd projection. Cache-off command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --odir /tmp/a05c-simple-shapes-build \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/A05cSimpleShapes.fst
```

The independent run exited 0 with all VCs discharged. This is a tractable
builtin structural fragment, but not full AST coverage. Kernel syntax has no
direct list/option/sum value constructor; those forms need selected rule
packages. Bound needs a context tied to schema declarations and weakening;
Root/Port require graph environments; Constant needs selected codec decoding.
The scratch has no sealed public interface, package adequacy, selected
constructor/index-call semantics, codec-reflection integration, or general
soundness. Do not count it as A05c completion.

### Exact package codec injectivity — 2026-10-14

Independent scratch `/tmp/A05EqualManifestPackage.fst` proves that canonical
encoding equality implies native value equality at one exact
manifest-selected package and index, using the package's existing
`schema_indexed_codec_encode_injective` theorem (roundtrip-derived). A plain
package has the analogous `schema_plain_codec_encode_injective` result. The
JValue fragment `/tmp/A05EqualSharedPackage.fst` carries both operands at one
shared package/index and proves encoded-byte equality soundness. All VCs pass
cache-off. The manifest-package command is:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05-equal-manifest-build \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
  /tmp/A05EqualManifestPackage.fst
```

This proves reflection only after one exact package and index are fixed. The
general equality judgment must select one package/index and reuse it for
both operand derivations and the codec; independently selected package
existentials do not establish shared carrier equality. It does not prove
AST-to-package adequacy or the full A05c equality semantics.

### Shared-package equality and registry-member codecs — 2026-10-14

`/tmp/A05PredicateProbe.fst` imports production `Identity`/`SchemaSemantics`
and the abstract `A05ActualJValue.fsti`. It proves proposition-valued
equality reflection for values sharing one exact `package rho t` and its
opaque `package_carrier`. A plain codec is required to be a member of the
shared `global_codec_registry`; its `roundtrip` theorem yields injectivity.
The indexed-codec analogue fixes one shared index and invokes
`schema_indexed_codec_encode_injective`.

Root reran cache-off with split queries; all VCs discharged:

```sh
opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
  --include src/fstar/v2/src --include /tmp/a05actual-interface \
  --odir /tmp/a05-predicate-root \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/a05actual-interface/A05ActualJValue.fsti \
  /tmp/A05PredicateProbe.fst
```

The proof fixes one package/carrier for both equality operands, so it does not
infer equality between independently selected existential packages. Critical
gap: this registry-member codec is not yet tied to the exact manifest-backed
`schema_family_package`, its AST denotation, or that package's indexed codec.
A05c must construct that relation (or prove the exact carrier/index
correspondence) before this becomes its `JPredicate` equality case. The
scratch does not prove AST `SchemaEqual` elaboration or general predicate
soundness.

### Exact family-package codec and shared existential — 2026-10-14

`/tmp/A05cFamilyPackageCodec.fst` imports the production
`schema_family_package` and proves equality reflection directly from its own
`family_codec`, at one `family` package and exact `indices`. It also checks
that `with_selected_family` can obtain one package from
`packages.family_at identity` and pass that same dependent package to a
continuation. This avoids a second codec lookup or independently selected
package per equality operand.

Root reran cache-off with split queries; all VCs discharged:

```sh
opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05c-family-codec-root \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
  /tmp/A05cFamilyPackageCodec.fst
```

This proves the codec-reflection lemma needed by family equality without an
arbitrary registry-member codec. It still assumes the exact family package
and index are already selected. It does not elaborate `SchemaFamily id args`
into that package/index, derive a type package from the AST, or connect both
`SchemaEqual` operands to that same existential. Those are the remaining A05c
integration obligations; this scratch is not the generic JPredicate proof.

### Production-context Sigma / Vec / refinement product — 2026-10-14

`/tmp/A05cActualVecRefineProduct.fst` combines three earlier fragments under
the production `WorkflowV2.SchemaSemantics.hlist`: a dependent Sigma over
`nat`; a family application at `SchemaBound 0`, represented as `vec n`; and
the refinement `{x:nat | x == n}` whose AST compares `SchemaBound 0` with
`SchemaBound 1`. Its carrier is a nested `dtuple2`; structural shape and
JValue constructors establish the Sigma, Product, family-fragment, and
Refine cases. Cache-off root command:

```sh
opam exec -- fstar.exe --cache_off --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05c-product-build \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  /tmp/A05cActualVecRefineProduct.fst
```

All seven modules verified; all VCs discharged. This is one combined
production-context example, not a general interpretation: family identity
and `vec n` semantics are hardcoded; no `schema_family_package` is selected,
no indexed codec is threaded, and predicate evaluation covers this bound
equality only. It demonstrates expressibility of the dependent shape, not
exact package selection, generic predicate soundness, or A05c acceptance.

### Positivity-safe refinement and family binder alignment — 2026-10-14

Two proof-shape details are now sharper.

1. A direct mutual `JValue`/`JPredicate` encoding fails F* strict positivity
   when the proposition used as the native refinement carrier is itself
   defined from the `JPredicate` GADT, because that proposition occurs in a
   `JValue` carrier/index while `JPredicate.Equal` recursively contains
   `JValue`. Keep the native predicate denotation (`pred_eval : ... -> prop`)
   independent of the evidence GADTs. A positivity-safe fragment,
   `/tmp/A05cBuiltinRefineCore.fst`, has an AST/context/carrier-indexed shape,
   production `hlist`, a `JValue` GADT, a proposition-valued `jpredicate`,
   and native subset refinement for `SchemaRefine base SchemaTrue`. Root
   independently verified its six production dependencies plus the scratch
   with cache off and split queries; all seven modules passed and all VCs
   discharged. It is only an architecture probe: predicate denotation handles
   `True` only; there is no context declaration alignment, family/rule package,
   equality evaluator, full value AST, or semantic soundness theorem.
2. The family signature alignment law should be a recursive package-level
   witness, not a proof each graph author supplies at each use. The scratch
   `/tmp/A05cFamilyTelescopeLaw.fst` defines `family_signature_alignment`:
   each signature binder has a `JType` derivation at the current prefix, and
   every later binder is checked under the prefix extended with an arbitrary
   value of that exact carrier. It constructs a one-argument family index
   `Mkdtuple2 n ()` from `SchemaBound 0` in the production `hlist`, using the
   existing `schema_argument_derivation`. Root reran the dependencies and
   scratch cache-off; all nine modules passed and all VCs discharged (the
   pre-existing SchemaCodec Warning 349 was reported). This is a Nat toy,
   not a constructed manifest-selected package or a complete adequacy
   wrapper.

The direct package-index attempt without a binder alignment witness fails at
the expected dependent-type boundary: the AST argument's derived carrier does
not unify with the package telescope's carrier. The resolution is the existing
A05d law boundary: store `family_signature_alignment` in the adequacy witness
for the exact base package map; A05c then constructs each call's argument
derivation internally, selects one exact family package/index, and reuses that
same pair for its denotation, indexed codec, and both equality operands. This
is package-level semantic adequacy, not a per-edge proof or per-use API field.

`/tmp/A05cPredicateMutual.fst` now verifies the positivity-safe GADT pair and
the `predicate_evidence_sound` theorem for Nat literal equality and
conjunction. Its equality constructor requires both operands to have the same
`SchemaNat` carrier, and the proof pattern-matches their `JVNat` evidence.
The Refine constructor consumes both the evidence derivation and the proven
`pred_eval` proposition, and uses an explicit subset-introduction term rather
than treating a raw Nat as a value of the subset. The fragment also proves
codec injectivity with the production `schema_plain_codec_encode_injective`
and a selected plain codec carrying membership in the real global codec
registry. Root's exact cache-off command and result are recorded in
`run_log.md`. The evaluator still handles Nat literals only; this is not
generic AST semantics or A05c completion. The source
`WorkflowV2.SchemaJudgments.fst` remains the placeholder scaffold.


### Exact package call-shape and acyclic law boundary — 2026-10-14

`/tmp/A05cExactFamilyAlignment.fst` imports `SchemaPackages` and
`SchemaJudgments`. Its `JFamily` constructor selects one
`schema_family_package` with `select_family_for_type`, returns that package's
`family_denotation arguments`, and requires a `schema_argument_derivation` at
the exact dependent telescope. A Sigma-context example types
`SchemaBound 0` as Nat and constructs `Mkdtuple2 n ()` at the exact carrier.
Root independently verified all nine modules and all VCs using:

```sh
opam exec -- fstar.exe --cache_off --split_queries always --warn_error @285 \
  --include src/fstar/v2/src --include /tmp \
  --odir /tmp/a05c-exact-family-root \
  src/fstar/v2/src/WorkflowV2.Kernel.fst \
  src/fstar/v2/src/WorkflowV2.Identity.fst \
  src/fstar/v2/src/WorkflowV2.SchemaCodec.fst \
  src/fstar/v2/src/WorkflowV2.SchemaScope.fst \
  src/fstar/v2/src/WorkflowV2.ManifestCore.fst \
  src/fstar/v2/src/WorkflowV2.SchemaSemantics.fst \
  src/fstar/v2/src/WorkflowV2.SchemaPackages.fst \
  src/fstar/v2/src/WorkflowV2.SchemaJudgments.fst \
  /tmp/A05cExactFamilyAlignment.fst
```

This demonstrates exact package selection and the intended dependent judgment
indices, but not automatic construction: `JFamily` still takes the
call-site argument derivation. A05g must construct that evidence from A05d's
package-level alignment field and A05e's semantic substitution. The same
alignment obligation applies to constructor and index-call argument
signatures; constructor result-index/inhabitance and index-call result/codec
laws must also be consumed before their judgments close.

An import-order audit found that A05c cannot import A05d's proof because
A05d depends on A05c. The canonical DAG now separates the law type/interface
in A05c, the proof-bearing exact-map adequacy wrapper in A05d, semantic
substitution in A05e, and closed package-backed call judgments in A05g, before
A05f `LegalEnv`. The wrapper's law fields are proved contracts supplied once
for the pinned package map; raw package fields and tokens alone cannot imply
them. This corrects the earlier scratch note's proposed dependency while
preserving theorem strength and the no-per-use-proof API.

### Carrier lookup and candidate typed-context shape — 2026-10-14

`/tmp/A05cContextLookup.fst` was independently verified by root with the
production Kernel and SchemaSemantics imports. It indexes `Bound n` by a
`context_member` into an `hlist` of carriers and returns that exact lookup
value. It also covers Root/Port/Constant through one base record, Pair, and
same-carrier equality/conjunction evidence. Exact command and output are in
`run_log.md`.

This is weaker than a typed schema context: the base record chooses arbitrary
Root/Port/Constant carriers and values, and the context stores no AST
declaration or `JType` witness. It proves neither declared-type alignment nor
graph edge/codec/root-schema correctness. Sigma/Refine, selected packages,
and generic semantic soundness are absent.

Candidate next shape: a context GADT extension stores the declared AST type,
its carrier, a value, and a `JType` witness in the prior context. A bound
lookup then returns the exact type/carrier/value triple. This sketch has not
been encoded or checked, and mutual positivity/termination with JType/JValue/
JPredicate remains open. It does not alter A05c acceptance or the DAG.
