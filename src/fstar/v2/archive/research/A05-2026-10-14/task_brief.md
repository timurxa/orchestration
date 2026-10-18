# A05 — Restricted schema syntax and semantics

**Status:** A05a and A05b complete; A05c in progress. The canonical stage plan
is in [`../../work_dag.md`](../../schema_era_2026-10-14/state/work_dag.md).

## Objective

Turn the Kernel schema AST into a canonical, scoped, semantically interpreted
first-order language for A06 equality and A07 graph resolution. Follow
[`../../implementation_spec.md`](../../schema_era_2026-10-14/implementation_spec.md) §2.2.1 and
[`../../key_correctness_theorems.md`](../../schema_era_2026-10-14/key_correctness_theorems.md).
Schema completeness is exactly for the declared `SchemaSupported` language
and its representable values; it is not arbitrary `Type0` reification.

## Required proof stages

1. **A05a — Codec/scope (complete).** For every type/value/predicate/list AST
   constructor, prove the existing unframed encoding's suffix/public
   roundtrip, injectivity, and malformed/trailing rejection. Prove
   nearest-first locally nameless scope, lifting and capture-avoiding syntax
   substitution laws for `Sigma` and `Refine`. This stage is syntactic only.
2. **A05b — Package interface (complete).** Select one exact package from the
   canonical manifest owner identity/row and prove its complete law-token
   coherence. Define typed heterogeneous argument telescopes, exact
   carriers/codecs/indexed families, and exact constructor result families for
   Atom, Family, Constructor, and IndexCall. The F* carrier telescope is
   indexed by the AST declaration arity. `SchemaAtom` matches only an empty
   telescope; `SchemaFamily` arguments match the same declared arity, including
   zero. A package's codec field is the one codec object used by that package
   and carries membership in the shared global codec registry; P0 binds that
   registry to canonical manifest codec rows. No second registry, arbitrary
   carrier/predicate oracle, freely chosen interpretation witness, or
   token-only law. The exact package owns its first-order telescope and
   equation data; the token is a checked projection field, never a lookup key.
   Family/Rule owner identity selects a package whose type-level variant
   distinguishes Constructor and IndexCall. Constructor interpretation uses
   the exact parent returned by the package map. This is base package data,
   not semantic adequacy: scope, equal arity, codec membership, and token
   projection do not prove callback/schema laws. A05c/d must prove
   binder-by-binder AST/carrier typing, constructor result-index denotation,
   and equation adequacy. A04/P0
   later proves the executable bundle returns these exact package objects;
   A05 must not import Bundle or GraphResolver.
3. **A05c — Canonical denotation and judgments (active).** Define one structurally
   selected interpretation of each schema type/value/predicate, then typed
   judgments over it. Use paired AST/carrier/value contexts and explicit
   context well-formedness. `Bound` uses one paired slot witness; Root, prior
   Port, and Constant are exact cases. Equality requires same-carrier,
   same-index typed values and the checked codec equality-reflection law.
   Sigma is dependent; Refine is a native subset with structurally derived
   evidence. Cover every Kernel AST constructor or reconcile a narrower
   `SchemaSupported` boundary with the spec before proceeding. Enforce exact
   package matchers and map lookups at interpretation; state no callback
   soundness theorem unconditionally before A05d.
4. **A05d — Package adequacy.** Define a proof-indexed
   `AdequateSchemaPackages` wrapper over the same exact base map. Its fields
   prove each AST binder matches its dependent carrier; family/result
   denotation; constructor computed-index and inhabitance agreement; index-call
   result typing and equation soundness; and codec/schema/index coherence.
   Prove the generic consequences and require this wrapper for every later
   semantic consumer and A04/P0. A law token only identifies the manifest
   field; it is not evidence. Package meaning must be canonical from selected
   data; an empty carrier cannot satisfy an unrelated vacuous predicate. Prove
   only the bounded completeness/quotation statement for `SchemaSupported`.
5. **A05e — Semantic weakening/substitution.** Prove arbitrary-cutoff
   weakening and semantic substitution for types, values, predicates, and
   well-formed contexts. State substitution as a relation mapping each source
   binding to a target expression with the same denotation. Lift outer
   declarations at each nested Sigma/Refine cutoff. Prove judgment and
   denotation preservation; syntax-only substitution is insufficient.
6. **A05f — `LegalEnv`.** Define the base environment from the exact root and
   canonical constants, then extend each topological prefix with every value
   in the full declared output family at its reconstructed input. Prove
   paired-context well-formedness and the required wire/value/type/predicate
   facts for every prefix. Validators and observations do not narrow this
   universal set.
7. **A05 integration.** Integrate acyclic modules; run the configured
   cache-off verifier; audit the transitive A05 proof path for admissions,
   unchecked declarations, external axioms, vacuous contracts, and duplicate
   sources of semantic meaning. A06/A07/P0 claims are outside this node.

Each theorem must have a checked F* proof; no `assume`, `admit`, unchecked
declaration, sampled execution, or test substitutes for a proof. Conditional
host/package laws must be explicit proof-bearing inputs. Full configured
verification is required at coherent source checkpoints and at A05 rollup.

## Design constraints

- `SchemaBound 0` is the nearest value binder. `Sigma(A,B)` adds it only in
  `B`; `Refine(T,P)` adds it only in `P`.
- External outputs range over their full declared family in `LegalEnv`; a
  validator postcondition cannot rescue an otherwise ill-typed edge.
- No package closure, code pointer, proof term, runtime value, or artifact
  handle is serialized in the manifest. Exact identities and canonical
  schema bytes are the durable syntax.
- A05 defines the package interface and semantic model, not the Bundle's
  runtime projection. A04/P0 later proves that projection against the exact
  package object used by execution.
- The selected package contains first-order telescope/signature/equation
  declarations and their proof fields. The owner row's denotation-law token
  is checked against that package; P0 binds the exact package object and its
  reload-stable selection. A06 consumes precisely the finite equations in
  that package. This is the current representation choice; adding serialized
  declaration bytes would need a justified format change and a proof that
  they project to the same package data.

## Evidence and provenance

The integrated codec proof is commit
`115fd0bf057f403c32ceeeba57c615b1385de381`; codec equality reflection is
`a3fea7abe26af6478c9f4d4b6d2b66154103a814`; scope proofs are in `0ace03d` and
`1cc76f4`. The full configured cache-off baseline passed on 2026-10-14 with
F* 2026.03.24 / Z3 4.13.3 using:

```sh
opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify \
  BUILD_DIR=/tmp/fstar-v2-a05-stage-baseline \
  FSTAR_FLAGS='--cache_off --split_queries always --warn_error @285'
```

All 11 modules and VCs passed; the existing `GraphCodec.nodes_decode_encoding`
warning 328 remains. This build compiles legacy admitted modules but does not
make them part of A05's proof path.

Scratch semantic prototypes are recorded in
[`semantic_model_prototype_audit.md`](semantic_model_prototype_audit.md) and
[`semantic_architecture_checkpoint.md`](semantic_architecture_checkpoint.md).
They inform proof shape only and are not integrated evidence. In particular,
the direct `TypeDenote` GADT conversion and arbitrary-witness uniqueness
approach are rejected; the current direction is an exact package-selected
canonical interpretation with hidden constructors and no function
extensionality.

The first integrated A05c source increment is only argument-telescope
scaffolding. It proves earlier-argument substitution and dependent tuple
alignment, and enforces exact base-map matcher/lookup selection. It passes the
13-module full cache-off verifier, but still uses a parameterized placeholder
value relation in its example. It does not count toward the required canonical
interpretation or judgment completeness; A05c remains active.
This verified source scaffold is committed as `9ba432b`.
