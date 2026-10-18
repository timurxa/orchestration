# A05 package-law boundary review

## Decision

Close A05b as the base package-data interface and require a later
`AdequateSchemaPackages` wrapper, indexed by the exact same base package map,
before any semantic consumer uses those packages. Keep A05c before A05d because
the adequacy propositions are stated over A05c's typed judgments. A05c may
interpret the base package data, but claims depending on package callbacks or
schema equations remain conditional until the wrapper is supplied.

## Evidence from source

`WorkflowV2.SchemaPackages.fst` selects exact manifest owner rows and projects
their AST expression and `DenotationLawContract` token. It defines dependent
carrier telescopes, an exact codec object with shared-registry membership,
constructor/index-call variants, match predicates, and a helper that obtains
the constructor parent through `family_at`. The full cache-off verifier passed
for all 12 configured modules (see `run_log.md`; source commit
`e70c0ce01dfb8006c6386cb39a559023bd99d547`).

These are structural/package-selection properties only. In particular, they
do not prove that an AST binder denotes the corresponding carrier, that a
constructor's declared result indices equal the computed indices, that an
index-call result has its declared schema type, that equations preserve
meaning, or that the selected codec denotes the same schema. Codec membership
and token equality identify objects; neither establishes these semantic laws.

## Alternatives considered

1. **Trust the token or package identity as the law.** Rejected: manifest
   identity does not imply callback or denotation correctness.
2. **Put unindexed arbitrary callbacks directly in A05c and prove unconditional
   judgment soundness.** Rejected: a callback may inhabit unrelated carriers,
   making soundness false.
3. **Define an exact-map adequacy wrapper after judgments.** Selected: A05c
   defines canonical interpretation and judgments; A05d supplies checked
   binder/result/equation/codec laws indexed by the same package map and proves
   their consequences. P0 stores/reloads that exact package map with its
   witness and binds the row token to the exact law field. No duplicate table,
   token lookup, or global assumption is introduced.

## Required follow-through

- A05c enforces family/rule matcher predicates and exact selected-package
  lookup. Constructor interpretation uses only the parent returned by
  `family_at`, never an arbitrary same-identity package.
- A05d creates the proof-indexed adequacy wrapper and states law fields for
  binder-to-carrier alignment, family denotation, constructor result-index and
  inhabitance agreement, index-call result typing, exact equation soundness,
  and codec/schema/index coherence.
- A05e/A05f, A06/A07, and A04/P0 consume only adequate packages. The contract
  token is a checked identity projection, not semantic evidence.
- Completeness remains bounded to `SchemaSupported` and the stated quotation/
  representation boundary; no universal `Type0` reification claim is made.

The source and DAG remain unchanged by this review artifact. The interface
stage is complete; A05c is now the active source node.
