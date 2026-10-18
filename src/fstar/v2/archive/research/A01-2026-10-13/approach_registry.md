# A01 approach registry

| Assignment | Method family | Artifact/evidence | Quality | Distinct contribution | Gap/next action | Worker/status |
|---|---|---|---|---|---|---|
| Import graph / module ownership | Independently derive dependencies from theorem owners and source inventory | `module_graph_audit.md` | Reviewed | Acyclic module graph and move/retain map | Integrated with packet and DAG; corrected generator package owner/order | complete |
| F* interface and trust boundary | Verify `.fsti`/`.fst` rules from installed or official F* materials | `fsti_contract_audit.md` | Reviewed | Safe public interface pattern, build obligations, explicit external axioms | Pair all future interfaces with checked implementations; trust ledger explicit | complete |
| Adversarial minimality review | Search for cycles, duplicate sources of truth, untracked trusted declarations | `boundary_adversarial_review.md` | Reviewed | Found GeneratorMember/Bundle/A04-A16 cycle and ownership overlaps | Resolved by pre-bundle law package, Bundle-owned membership, DAG reorder | complete |
| Generator package boundary | Check pre-bundle law, P0 reload binding, and A04/A16 order | `generator_boundary_review.md` | Reviewed | Confirms cycle repair; avoid callback extensional equality; preserve package association on reload | Integrated in design, packet, spec, DAG | complete |
| Module/trust policy review | Independently assess imports, interfaces, and transitive trust rules | `module_contract_review.md` | Reviewed | Confirms A01 should be docs-only; full paired implementation and trust closure rules | Integrated in design and A01 acceptance | complete |
