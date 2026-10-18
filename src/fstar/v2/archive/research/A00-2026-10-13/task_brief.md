# A00 source and build inventory

**Status:** complete. **Boundary:** read-only with respect to F* source.

## Question

How does the current `src/fstar/v2/src` baseline map to active DAG nodes A00–C6
and theorem targets P0–P16? Identify reusable source, declarations or proofs
that must be replaced, missing proof obligations, build/tool facts, likely
module-cycle risks, and safe refactor boundaries.

## Acceptance

- Inspect all current `WorkflowV2.*.fst` files, the Makefile, normative
  `implementation_spec.md`, `key_correctness_theorems.md`, and
  `implementation_packet.md`.
- Cite exact files and line ranges for source and proof claims. Distinguish
  checked proof bodies, declarations/contracts, `assume`/`admit`, and
  unverified or example-only artifacts.
- Record configured F*/Z3 versions and the full project verification command;
  run the baseline check if the environment supports it and label failures.
- Map existing artifacts to DAG owners; identify missing P0–P16 paths, import
  cycles, duplicated sources of truth, and candidates for simpler module
  ownership.
- Do not edit F* code or weaken theorem acceptance. Root integrates worker
  reports and owns DAG/state edits.

## Work assignments

| Assignment | Method | Output | Status |
|---|---|---|---|
| Source/build map | File-by-file inspection and baseline build probe | `source_inventory.md` | complete |
| Proof/trust gap audit | Adversarial theorem-path and escape-hatch review | `proof_gap_audit.md` | complete |
| Simplification audit | Independent module-boundary and duplicate-state review | `simplification_audit.md` | complete |

## Integrated result

Root reconciled the three independent reports into
[`source_refactor_map.md`](source_refactor_map.md). The full seven-module F*
check passed under the recorded opam toolchain. Existing admissions remain
explicit trust gaps. C0 checkpoints these artifacts; A01 has not started.
