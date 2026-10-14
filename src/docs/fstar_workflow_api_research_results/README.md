# F* workflow API research results

Store independent research artifacts, formal models, counterexamples, source audits, and adversarial reviews here. Keep each artifact focused and include method, provenance, assumptions, strongest objection, and next action. The parent [`research state ledger`](../fstar_workflow_api_research_state.md) tracks assignments, status, decisions, and synthesis.

Research artifacts:

- `api_composition_alternatives.md` — dependent/dataflow API designs and example encodings.
- `durability_proof_semantics.md` — state/trace model and formal no-rerun/recovery/adapter/budget properties.
- `resource_adapter_architectures.md` — live-resource protocols, effectful node options, recovery, and inline/library forms.
- `current_implementation_map.md` — source audit of the F* core, store, dummy runner, historical evidence, and gaps.
- `proof_model_critique.md` — adversarial review of proof semantics, cut protocol, and resource choices.
- `design_comparison_and_decision.md` — comparison matrix, recommended design, rejected alternatives, and unresolved questions.
- `adversarial_review.md` — independent audit of the integrated proposal and issue resolutions.
- `fstar_feasibility.md` — primary-source-based F* feasibility notes for dependent contracts and scoped effects.
- `api_surface_candidate.md` — chosen API candidate with dependent composition and example encodings.
- `refined_proof_targets.md` — corrected cut-state, no-rerun, recovery, budget, and liveness theorem targets.
- `whole_operation_adapter_contract.md` — minimal whole-operation adapter contract and optional scoped-library extension.
- `final_proof_review.md` — first adversarial review of recovery, completion, artifacts, budgets, and adapter progress.
- `final_api_review.md` — F* language/API audit, including indexed output codec requirements.
- `final_proof_review_resolution.md` — audit of how the integrated decision addresses the proof review, with remaining host/runtime obligations.
- `final_api_review_resolution.md` — audit of the revised dependent API; its report-provenance objection is addressed by `OperationContext`, `ReportProvenance`, `AcceptedRaw`, and `HasSuccessfulParse` in the integrated decision.
- `final_resource_review_resolution.md` — final adapter/artifact lifecycle audit; it prompted an explicit report-provenance receipt.
- `final_api_provenance_recheck.md` — follow-up confirmation that operation context, report provenance, parse success, and unverified findings are tied together in the candidate API.
