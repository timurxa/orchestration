# A05 semantic architecture checkpoint — 2026-10-14

This records proof evidence and the current A05 direction. Scratch modules are
research only; no scratch theorem is credited as an integrated A05 result.

## Verified evidence

- `SchemaCodec.fst` proves suffix-preserving decode, public roundtrip,
  encoder injectivity, and trailing-byte rejection for value, predicate, and
  type syntax. `SchemaScope.fst` proves locally nameless scope preservation,
  lifting, substitution scope, identity/composition, and binder cases for
  `Sigma` and `Refine`. The full configured build passed after integration.
- `SchemaSemantics.fst` now proves plain and same-index indexed codec
  injectivity from codec roundtrip. This converts equality of canonical bytes
  to equality of actual values only after both terms are statically typed at
  the same exact carrier/index.
- `/tmp/A05InterpretationGADT.fst` verifies structural carrier witnesses for
  all current type constructors, including dependent `Sigma` and native
  refinement carriers. Its `jtype` is indexed by a witness, avoiding the
  failed direct recursive-`TypeDenote` conversion at `Sigma`.
- `/tmp/A05CanonicalInterpretation.fst` verifies a structurally recursive
  canonical witness builder, including the dependent `Sigma` case. This is
  only a prototype: it does not yet prove semantic soundness, typed-value
  completeness, or exact package adequacy.
- `/tmp/A05SoundTypedContext.fst` verifies paired AST/carrier lookup and
  cutoff-zero term weakening. It does not yet prove arbitrary-depth semantic
  type weakening or typed substitution.
- `/tmp/A05ActualValueSubst.fst` and `/tmp/A05TypedASTSemantics2.fst` verify
  useful dependent substitution recursions, including `Sigma` and `Refine`,
  but neither proves each substituted binding inhabits its substituted
  declaration type.
- Exact codec-identity lemmas in the source are checked in the full 11-module
  build. Row projection currently proves that a selected family row supplies
  its syntax and law token together; it does not resolve that token to the
  actual package/carrier.

## Rejected shortcuts

- A carrier-only context does not establish that a `Bound` value has the
  declared schema type.
- A free `atom_view`/`family_view` callback can identify distinct values and
  is unsound for `SchemaEqual` without equality reflection.
- A carrier-indexed GADT by itself allows multiple interpretation witnesses
  for the same AST. It needs one canonical package-selected witness, or a
  proved uniqueness theorem. The latter reaches dependent-family equality.
- The attempted direct `jtype : TypeDenote(t) -> Type` fails F* conversion at
  the `Sigma` constructor because recursive `TypeDenote` does not unfold to
  the expected dependent-pair carrier there.
- `FStar.FunctionalExtensionality` is marked “MAIN AXIOM”; raw equality of
  functions is not proved by its API. The restricted-function scratch does
  verify, but A05 will not rely on this external axiom route.
- A token equality or a soundness law alone can be vacuous for an empty
  carrier. The package must expose its exact carrier and a structural
  denotation witness tied to the selected canonical row.

## Current direction and remaining proof boundary

Use one canonical denotation witness selected for each exact manifest package,
schema expression, and semantic environment. Every `JValue`, `JType`,
`JPredicate`, local-context, graph-context, and `LegalEnv` derivation must
reuse that selected witness. Package constructors/lookup must tie the exact
AST, complete law token, carrier, codecs, typed argument telescope, and
operation semantics together. No arbitrary callback may choose a carrier or
rewrite equality. Package laws are explicit proof fields; A05 proves generic
theorems from them, while A04/P0 later proves the runtime bundle returns these
same packages.

Still to prove in source:

1. A canonical type interpreter and exact Atom/Family/Constructor/IndexCall
   package records/selection, with no alternate source of carrier meaning.
2. Typed value and predicate judgments for every AST constructor. `Equal`
   requires both operands at one selected exact type and codec index.
   `Refine` remains a native proof-bearing F* refinement.
3. A local context pairing nearest-first schema declarations with exact
   dependent carriers and values. Prove arbitrary-depth type/value weakening
   and semantic substitution under `Sigma` and `Refine`; no binder slot is
   accepted from its carrier alone.
4. Exact root, canonical constants, and full-family prior ports in a graph
   `LegalEnv`. Prove each wire/type/predicate judgment sound for every legal
   prefix environment and preserve the universal external-output family.
5. Full configured verification plus source/trust audit before A05 is
   complete. No dependent node starts before that gate.

The proof-stage dependencies and acceptance tests are now explicit in
`state/work_dag.md`; A05 remains in progress.

## Independent review and staged proof order — 2026-10-14

Three independent reviews confirmed that one canonical interpretation with
hidden constructors is preferable to proving uniqueness of arbitrary
interpretation witnesses. The raw witness approach permits callers to choose
unrelated carriers and dependent Sigma codomains; the uniqueness attempt also
reaches `FStar.FunctionalExtensionality`, whose interface documents an axiom.
Do not use that route.

The reviews identified a dependency cycle if package adequacy laws are
required before typed judgments exist. The DAG now orders the work as
`SchemaPackages` interface (A05b) → canonical denotation/typed judgments
(A05c) → package adequacy and bounded completeness (A05d) → semantic
weakening/substitution (A05e) → `LegalEnv` (A05f). Package interface data
provides exact typed telescopes and symbol signatures; A05d proves those
selected packages satisfy the semantic judgments. A04/P0, later, proves the
runtime Bundle projects the exact same package objects. This avoids importing
Bundle into A05 and creating a module cycle.

The current manifest has separate Family and Rule owner identities. Their rows
carry canonical schema syntax and a `DenotationLawContract` identity; the
current `SchemaSemantics` projection parses that syntax as a schema type AST.
Kernel applications carry `list schema_value_expr`, while the existing AST
has no encoded argument telescope or finite equation list. One reviewer
proposed a new first-order declaration AST; another confirmed this is needed
only if those declarations must be serialized separately.

**Representation decision:** the exact owner identity selects one typed
proof-bearing package from the pinned bundle. The selected package contains
its finite first-order argument telescope, signature/equation declarations,
carrier operations, and proof fields. Its denotation-law token must equal the
exact token projected by the selected owner row. Do not look up by raw token.
The `SchemaRulePackage` is a typed sum (Constructor or IndexCall), and an AST
constructor must match the selected variant. A04/P0 proves the exact package
projection and reload stability; later P13 binds that contract to a host
implementation. This is the existing spec's package-projection boundary,
not an added signature table. The finite equations remain exactly pinned and
proved, so this changes their representation rather than their theorem
strength. The implementation spec and A06 acceptance now state explicitly
that A06 proves the equations in these exact manifest-selected packages. No
manifest wire-format change is planned.

This choice is conditional on implementing the package field as the single
source of telescope/equation data and proving its owner-row projection; if a
F* package interface cannot express that exact relation or if reload
stability cannot cover it, stop before downstream work and revise the DAG.

Typed heterogeneous arguments should be an inductive relation over a
first-order dependent type telescope, with each argument value checked at
that slot's canonical carrier and the tail checked in the context extended by
that exact value. The prototype `/tmp/A05ManifestRel.fst` is a useful shape
but is not sufficient: it uses `nat` keys, static `list Type0` signatures,
untyped contexts, and lacks canonical row linkage. Constructor packages
must produce values directly in the exact parent Family carrier at computed
indices; IndexCall packages must be total and return the package-declared
indexed result. No cast or arbitrary callback is introduced.

An unresolved termination condition also emerged: package signatures contain
schema types that need not be syntactic subterms of the use-site AST. The
package contract must make signature traversal structurally finite and prevent
cyclic package expansion from becoming evaluator recursion. Initial typed
judgments may carry exact finite telescope witnesses as input data and recurse
only on AST argument subterms; if that cannot support the required
completeness, define a well-founded package-dependency rank and prove it.

The cache-off full configured baseline was rerun after the staged DAG update:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify \
  BUILD_DIR=/tmp/fstar-v2-a05-stage-baseline \
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'
```

Exit 0. All 11 configured modules and VCs pass under F* 2026.03.24 / Z3
4.13.3; only existing `GraphCodec.nodes_decode_encoding` warning 328 remains.
This confirms the baseline, not new schema semantic obligations. No A06 or
other dependent DAG node has started.

## Package interface source checkpoint — 2026-10-14

The first checked A05b source interface is in `WorkflowV2.SchemaPackages`.
Its carrier telescope is indexed by AST arity; each package's indexed codec
is a single object with membership in the shared codec registry; and the
Constructor/IndexCall sum plus AST matcher checks tag, owner identity, and
argument count. `SchemaAtom` matches only an empty declared telescope.
Constructor application is routed through exact `family_at` lookup and
returns the selected parent package with the value. No additional manifest
field or serialized signature table was introduced.

This resolves the *interface shape*, not semantic adequacy. The audit confirms
these are still proof obligations: each AST argument type must denote the
corresponding dependent carrier; constructor result-index syntax must denote
the indices produced by the selected parent package; IndexCall equations
must be typed and sound; the codec registry membership must be bound to its
manifest codec row by P0; and the exact owner-law token must be shown to
govern the package's actual denotation. A05c defines judgments; A05d and P0
prove these adequacy/projection relations. A05b remains active until the
interface and required source review are closed.

The complete 12-module cache-off verifier passed after this source increment
with `--split_queries always --warn_error @285`; all VCs discharged, with
only the existing GraphCodec warning 328. This is not proof of those deferred
semantic properties.
The source/state increment is preserved in commit
`e70c0ce01dfb8006c6386cb39a559023bd99d547`.
