# Spec refresh research — 2026-10-13

Read-only investigations informing the implementation-spec and S2 DAG refresh.
These reports did not execute DAG nodes or edit F* source.

The later S2 execution began with a separate source/evidence audit. Its
integrated result is in
[S2-00-evidence-ledger.md](../S2-execution-2026-10-13/S2-00-evidence-ledger.md);
it records historical source proof evidence and current open obligations.

## Findings integrated into the spec

- The former P0-P14 prose conflated replay-checkable journal shape with
  computation provenance. The revised spec separates replay WF from ghost
  AuthorizedTrace/SemWF, then composes both with journaler crash-prefix laws.
- The graph rule now fixes each Work input carrier A_k and output family B_k.
  Direct producer-to-consumer edges require B_p(input_p(rho)) = A_k for every
  legal environment. No observed result, external reply, or per-edge proof
  payload may establish the equality.
- A journaler is serial; independent ready local/generator computations may
  run concurrently; each adapter submission carries one intent, and multiple
  distinct calls may remain in flight with out-of-order keyed outcomes.
  Appends reauthorize against the current head.
- Durable CallIntent alone cannot make a retried physical dispatch safe.
  Adapter must deduplicate/query the stable key or prove operation-specific
  idempotence/reconciliation. Non-idempotent blind retries are excluded.
- Abstract executor safety (P15), concrete runtime refinement (P13), and
  recovered semantic graph correctness (P16) are separate theorem targets.
- The theorem dependency table is acyclic: P4/P6/P7 establish transition and
  operation laws without depending on aggregate accounting; P8 composes the
  ledger laws from replay and those transitions.
- GraphResolver is the selected abstract boundary: it is pinned by the exact
  manifest, derives transient universal typing from static syntax/signatures,
  emits no durable edge proof, and is reused by builder/decode/recovery.
  Its exact type language/completeness remains an S2 decision. No arbitrary
  erased F* Type0 equality is presumed reifiable.

## Alternatives considered

| Route | Value | Limitation / status |
|---|---|---|
| Typed constructor AST | Static builder typing; natural API authoring form. | Erases witness at serialization; needs a resolver on recovery. |
| Schema/type-expression checker | Canonical byte-only graph resolution; symbolic universal checking. | Complete only for represented schema/family language; arbitrary opaque F* families need encoding. |
| Proof certificate or reflection | Checker can validate graph-specific universal equalities. | Serialized edge proofs conflict with current requirement. Reflection works only for reified fragment. |
| Pinned GraphResolver | No per-edge proof bytes; exact typed result recreatable from static graph syntax and pinned definitions. | Completeness must be explicit; callback cannot inspect results or silently accept a trivial subset. |

The active S2-01/S2-03 nodes must settle the exact supported type language,
prove builder/resolver equivalence, and preserve arbitrary finite topology.
If no constructive resolver can satisfy the intended completeness, stop with
a precise impossibility boundary and present alternatives for human review.

## Reports

- [spec_audit.md](spec_audit.md): theorem-by-theorem comparison against
  key_correctness_theorems.md and current source.
- [edge_design_review.md](edge_design_review.md): typed AST, schema checker,
  proof reflection, and pinned resolver comparison; arbitrary Type0 boundary.
- [architecture_review.md](architecture_review.md): crash cuts, serial append,
  concurrency, external retry safety, uniqueness, stale-head reauthorization,
  and fairness counterexamples.
- [dag_audit.md](dag_audit.md): source evidence inventory and proposed
  spec-only active DAG; preserved legacy implementation status rationale.

All agent outputs remain research evidence. Root integration and explicit
acceptance criteria determine normative claims.
