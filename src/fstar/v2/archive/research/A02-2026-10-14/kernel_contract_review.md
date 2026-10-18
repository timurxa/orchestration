# A02 Kernel contract review

Read-only adversarial review of the current `WorkflowV2.Kernel.fst` diff against `implementation_spec.md` and A02 task brief. No tests or verifier run, per request.

## Finding

- **Medium — artifact refs are not opaque at the Kernel API boundary, and packed identity is unlinked to the phantom carrier.** [`WorkflowV2.Kernel.fst`](../../current_implementation/src/WorkflowV2.Kernel.fst#L159) exposes `artifact_ref` as a public record containing `bytes`; callers can construct/read arbitrary tokens. `PackedArtifactRef` then accepts an independently supplied `artifact_type_identity` and `artifact_ref a` with no type-level or proof link between that identity and `a` ([lines 164–170](../../current_implementation/src/WorkflowV2.Kernel.fst#L164)). This leaves package lookup/codec validation to downstream consumers, but current constructors allow mismatched pairs to be formed and potentially serialized. Spec requires opaque typed refs and canonical tagged encoding through the exact pinned artifact package; A02 brief says keep refs opaque and host handles outside Kernel. Make the representation/constructor abstract, or explicitly require downstream package-produced packing and validate identity-to-carrier coherence before any encoding or use. If abstraction is intentionally deferred, document this as an unchecked construction boundary rather than calling the token opaque.

## Checks with no finding

- **Schema grammar:** AST constructors match the specified restricted `Ty`, `Value`, and `Pred` grammar: atoms/base types/product/sum/list/option/Sigma/family/refine; bound/root/port/constant/literals/pair/projections/constructor/index call; true/false/equality/and. No callback, proof payload, arithmetic, or extra reduction form. `SchemaBound nat` and unindexed recursive nodes permit malformed scope, but comment assigns scope/denotation checks to `WorkflowV2.Schema`, as A02 intends. `SchemaSigma` second component's nearest-binder convention is stated.
- **Charge metric threading:** `run_budget` pins `run_charge_metric`; `op_ref` carries `operation_charge_metric`; every generator call takes `metric`. Naturals remain dimensionless in Kernel, with identity coherence appropriately deferred to pinned membership/authorization. No second metric appears inside allocation.
- **External operation boundary:** metric addition did not turn remote execution into a pure callback or change arbitrary-byte reply validation. Dependent result codec and validator remain indexed by exact input.
- **Graph syntax:** existing graph/wire syntax remains first-order; schema AST adds no executable callback or serialized proof.
