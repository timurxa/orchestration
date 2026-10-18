# A01 proof/module boundary

**Status:** in progress. **Scope:** architecture and contract boundary; no
theorem is discharged here.

## Question

What is the smallest acyclic F* module/interface architecture that can carry
the full implementation spec's proof spline without hiding assumptions in
`.fsti` files, conflating independent contracts, or creating import cycles?

## Acceptance

- Give an acyclic import graph covering every planned module and P0–P16 owner;
  identify which current modules are retained, split, or replaced.
- Define public `.fsti` boundary policy and separate it from private
  implementation/proof modules. A01 creates no interface stubs; state how a
  full build establishes each future interface against its implementation
  and how bodyless/external declarations appear in the trust ledger.
- Specify module build order and trust audit rules, including transitive
  `assume`/`admit`/axiom checks and explicit proof-bearing contract inputs.
- Preserve proof constraints while fixing the generator ownership order:
  ManifestCore precedes Schema/GraphResolve; GraphResolve does not depend on
  Bundle; the manifest-indexed GeneratorPackage law is defined before Bundle
  and Bundle stores/looks it up exactly; Allocation and GeneratorAdmission
  do not depend on GraphBuilder; Journal does not depend on controller or
  provenance proofs; P4/P8/P15/P16 boundaries stay acyclic.
- Root integrates independent reports into `module_boundary_design.md` and
  updates the active DAG, implementation packet, and state before A02 starts.
- Do not add `assume`/`admit`, weaken theorem acceptance, or claim any P theorem
  completed. A01 may create architecture documentation; interface bodies
  belong with their declaration/implementation nodes.

## Work assignments

| Assignment | Method | Output | Status |
|---|---|---|---|
| Import graph / module ownership | Re-derive dependencies from spec, packet, and current source | `module_graph_audit.md` | complete |
| F* interface and trust boundary | Inspect F* project/interface behavior and proof skill; classify valid interface patterns | `fsti_contract_audit.md` | complete |
| Adversarial minimality review | Try to find cycles, hidden axioms, or needless module splits | `boundary_adversarial_review.md` | complete |
| Generator package boundary | Adversarially check pre-bundle law, P0 reload binding, and A04/A16 order | `generator_boundary_review.md` | complete |
| Module/trust policy review | Independently assess import graph, F* interfaces, and transitive trust rules | `module_contract_review.md` | complete |
