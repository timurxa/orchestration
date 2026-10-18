# A01 module and contract review

**Scope:** independent check of the proposed module boundaries, dependency order, and F* interface/trust policy against `implementation_spec.md` and `implementation_packet.md`. No shared source or architecture file changed.

## Findings

1. **The proposed import direction is coherent and matches the theorem spline.** Keep the first-order path `Kernel -> ManifestCore -> Schema -> GraphResolve -> Bundle`; `GraphCodec` remains an independent `Kernel` consumer. Then join syntax, resolver, exact bundle, and generator admission in `GraphInterpretation`. Keep `GeneratorAdmission` below `GraphBuilder`/`Generation`, and keep `Journal` below Services and semantic provenance. This prevents the main cycles: resolver/bundle, builder/generator, journal/services/controller, and theorem-definition/proof back-edges.

2. **P0 ownership is intentionally split, not duplicated.** `ManifestCore` owns canonical first-order entries/projection and identity laws; `Bundle` owns the exact relation between that projection and executable package tables. `GraphResolve` proves schema-level support without selecting executable closures; `Bundle` then establishes exact package lookup. Do not make the manifest a separately supplied registry table or put bundle lookup back into the resolver.

3. **Keep theorem modules downstream of definitions and witnesses.** `EventAuthority` defines ghost witness shapes; `AdapterProvenanceProof`, `LocalProvenanceProof`, `GraphCommitProof`, `BudgetProof`, `ControllerSafety`, and `Recovery` prove their respective laws later. `ControllerModel` defines transitions/claims but imports no theorem conclusions. This preserves the intended separation of P4, P8, P10, P15, and P16. The current packet's optional `Artifacts` branch is appropriate only for P9 strengthening; packed reference syntax belongs below Journal.

4. **Build order is a partial order; avoid implying unnecessary serial dependencies.** The audit's 21-layer topological order is valid, but some siblings can proceed concurrently: `ManifestCore` with `GraphCodec`; `Durability`, `EventAuthority`, and optional `Artifacts` after their own prerequisites; `GraphCommitProof` with `LocalProvenanceProof`; and `BudgetProof` with `GraphRecovery` after their separate prerequisites. Prefer DAG edges/import dependencies as authority over the numbered layer list. Preserve the packet/DAG sequence where it intentionally gates proof work, even when source modules could compile earlier.

5. **A01 should specify `.fsti` policy, not create interface files yet.** The kernel signatures and exact public API are A02's work; creating skeletal interfaces now would either duplicate the normative signatures or create unimplemented declarations that could be mistaken for axioms/contracts. A01 can define the module/export matrix, interface rules, and audit method. Create each `.fsti` alongside the owning API/proof node once its signature is stable, with its `.fst` implementation and build entry in the same change. The A01 acceptance already says interface bodies belong with their declaration/implementation nodes; read “define public `.fsti` contracts” as defining the intended public-boundary policy and ownership now, not authoring incomplete F* API files.

## Required interface and trust rules

- A `.fsti` is an abstraction boundary, not a proof source. Every project-owned declaration that asserts behavior or a theorem must be discharged by a checked implementation/proof in the matching `.fst`, included in the full build. Keep private helper definitions and proof terms in `.fst`; expose only the stable signatures/laws callers need.
- Abstract parameters are allowed as explicit inputs. For example, a journaler, executor, adapter, codec, pinned registry, or artifact store is a record whose law fields are proof obligations of the supplied value. Prove system theorems parametrically from those fields. Do not replace the record with a global axiom or an assumed theorem.
- No theorem dependency may transitively contain `assume`, `admit`, an axiom standing for a system property, an unchecked external declaration, or a solver-only claim that has not been discharged. Existing `Graph.fst` assumptions/admissions remain excluded and cannot be inherited by import.
- Record unavoidable F*/stdlib/solver/kernel trust separately from project theorem hypotheses. A host fact may be a named conditional premise at the refinement boundary; it cannot silently establish an abstract theorem.
- Full verification must include every project module and paired interface from a clean/cache-disabled build, with strict warnings. Trust audit must inspect the transitive dependency closure, not only grep the new theorem file. The final audit checks forbidden declarations and reports any explicitly approved external boundary; an empty grep alone does not establish the absence of hidden assumptions.

## Minimal amendments recommended for A01 integration

- Keep the module ownership/import table and cycle constraints from `implementation_packet.md` as normative, with the DAG's per-node order controlling implementation sequencing.
- Add an explicit sentence that A01 creates **no `.fsti`/`.fst` stubs**; public interfaces begin with A02 and are paired with verified definitions/proofs in their owning nodes.
- Mark the module graph as a source/proof dependency partial order; the Makefile may use any topological ordering that includes all paired files and does not hide unverified imports.
- Ensure trust review names project axioms, admitted interfaces, external declarations, solver escape hatches, and their transitive use—not merely textual `admit` searches.

No theorem has been discharged by this review. Existing baseline typechecking is not enough while admitted builder theorems remain in the imported source.
