# Approach registry: system overview guide

| Assignment | Method family | Artifact/evidence | Quality | Distinct contribution | Gap/next action | Worker/status |
|---|---|---|---|---|---|---|
| Design lineage | Compare predecessor problem spec, typed-plan outline/report, next research draft, current spec and packet | [lineage.md](lineage.md) | Strong; distinguishes each document's authority | Found no single predecessor called “the original spec”; identified `so`/GraphDesc and durable `Unknown` as material changes | Preserve caveats in guide; no design decision inferred | `/root/overview_lineage`, complete |
| Architecture and theorem map | Trace normative definitions to packet modules and current F* files | [architecture.md](architecture.md) | Strong; separates target contracts from existing source | Summarizes API, journal lifecycle, concurrency, theorem families, and source gaps | Independent final pass on guide | `/root/overview_architecture`, complete |
| Adversarial guide review | Search for status overclaims, ambiguity, source/spec conflation, and missing qualifications | [adversarial_review.md](adversarial_review.md), [final_review.md](final_review.md) | Strong; found status conflict plus three precise wording issues; all were incorporated | No remaining issue reported; final guide links resolve | `/root/overview_adversarial`, complete |

## Integration decisions

- Treat `implementation_spec.md` as the normative v2 abstract contract and
  `implementation_packet.md` as subordinate source/proof planning.
- Explain the predecessor lineage explicitly because “original implementation
  spec” does not name a unique file in the current tree.
- State that P0–P16 are targets, source is partial, and A00–H5 is planned but
  unstarted. Mention stale S2 status wording in older status documents.
- Preserve two open compatibility questions: whether schema-resolved
  GraphDesc generation meets the original `so` requirement, and why v2 drops
  the earlier durable `Unknown` adapter state.
- Write the deliverable as Markdown inside `src/fstar/v2`; no code, tests, or
  DAG execution are authorized by this task.
