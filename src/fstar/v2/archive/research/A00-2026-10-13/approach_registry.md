# A00 approach registry

| Assignment | Method family | Artifact/evidence | Quality | Distinct contribution | Gap/next action | Worker/status |
|---|---|---|---|---|---|---|
| Source/build map | Direct module-by-module inspection and baseline build probe | `source_inventory.md` | Incorporated | Exact source reuse/refactor map, seven-module verifier result, tool versions | Initial PATH-only failure corrected by successful opam run; continue with A01 contracts | `/root/overview_architecture`, complete |
| Proof/trust gap audit | Adversarial theorem-path and escape-hatch review | `proof_gap_audit.md` | Incorporated | P0–P16 gap map; explicit admissions; syntax-vs-typed decode; resolver bottleneck | Later trust review must remove all `assume`/`admit` from theorem paths | `/root/overview_adversarial`, complete |
| Simplification audit | Independent dependency and duplicate-source-of-truth analysis | `simplification_audit.md` | Incorporated | Acyclic manifest/resolver/bundle, derived views, durable-ref and plan-scope alternatives | Proof experiment aligned with packet layering after independent review | `/root/a00_simplification`, complete |
| Integrated design review | Root synthesis plus independent adversarial consistency pass | `source_refactor_map.md` and review response | Complete | Reconciled source disposition, module boundaries, alternatives, and next proof questions | C0 checkpoints outputs; no A01 work before commit | `/root`, `/root/overview_adversarial`, complete |
