# Implementation DAG planning brief — 2026-10-13

## Question and acceptance criteria

Replace the prior specification-planning DAG with a granular future work DAG
that will produce the fully proved abstract F* workflow system defined by
`../../implementation_spec.md`. The DAG must account for every applicable
P0–P16 theorem and proof-bearing contract, start with a read-only audit of the
existing v2 source, preserve an acyclic proof/module order, and insert human
review/stop nodes after independently reviewable contract layers. The current
task writes the plan only: no new DAG node is run, and no `.fst`/`.fsti` source,
F* verification, or tests are changed or executed.

## Normative inputs

- `../../implementation_spec.md`: normative semantics and theorem contracts.
- `../../key_correctness_theorems.md`: theorem intent, especially universal
  dependent-edge typing and recovered semantic graph correctness.
- `../../implementation_packet.md`: proposed acyclic module ownership and
  proof ordering, subordinate to the spec.
- `../work_dag.md`, `../state.md`, `../node_summaries.md`, and `../run_log.md`:
  previous S2 specification-planning workflow, now superseded as the active
  workflow by the user's request for proof implementation planning.
- `../../src/WorkflowV2.*.fst`: existing partial source to inventory. It is
  not the target implementation and its present verification status is not a
  claim that P0–P16 are proved.

## Constraints and interpretations

- Build the abstract system and prove its theorems from explicit, proof-bearing
  contract records. Do not plan `assume`/`admit` as theorem shortcuts.
- Keep concrete host implementations (filesystem/SQLite, process execution,
  network, extraction/runtime pool) outside this DAG. Define the contracts and
  abstract controller so future concrete implementations can prove refinement.
  A generic refinement-composition theorem may be in scope; a host instance is
  not.
- Include total pure local Work, nondeterministic external adapter calls,
  arbitrary finite runtime-generated DAGs, canonical serial journal/replay,
  exact crash-cut recovery, and concurrency of independent local/generator
  execution plus multiple in-flight adapter calls. Journal append is serial.
- Graph soundness must establish universal all-legal-environment dependent
  edge compatibility from declared schema/signature constraints. A producer
  with output `vector n` cannot wire to fixed `vector 3` when `n` is unconstrained.
- “Schema AST” means the workflow's own finite, manifest-pinned schema
  expression language encoded as F* datatypes, with a proved denotation and
  equality/checking calculus. It does **not** mean parsing or serializing the
  F* compiler's AST, and does not claim completeness for arbitrary erased
  `Type0` equality.
- Examples are proof-bearing constructions, not a test suite substituting for
  theorems. The DAG should make compiler verification part of later execution
  acceptance, but this planning turn will not run it.

## Initial source observation

The current v2 directory contains seven `.fst` modules (`Kernel`, `Identity`,
`Graph`, `GraphCodec`, `Journal`, `GenerationExample`, `ChainProof`). They are
partial: source comments explicitly defer replay semantics, the graph codec
only covers syntax roundtrip, the graph layer contains admitted obligations,
and the journal currently defines vocabulary rather than replay/transition
authority. The packet proposes a more factored module architecture and maps
P0–P16; independent source and theorem audits are pending before final DAG
integration.

## Research assignments and evidence

1. Existing-source and build-boundary audit:
   [`source_audit.md`](source_audit.md), complete.
2. Independent theorem dependency/DAG derivation:
   [`theorem_dag_audit.md`](theorem_dag_audit.md), complete.
3. Adversarial missing-obligation/review-gate audit:
   [`adversarial_dag_review.md`](adversarial_dag_review.md), complete.

All were read-only analyses; workers did not execute the DAG or modify F*
source. Root reconciled their findings into `../work_dag.md`. In particular,
allocation and universal generator-admission contracts are ordered before
builder completeness so `GraphBuilder` can consume `GeneratorMember` without
an import cycle; the P4 append proof consumes a successful append token and
does not wait on P10's crash-cut theorem.

## Decision status

The DAG is designed, not executed. Every node in the replacement DAG remains
`not_started`. The former S2 nodes and their outcomes remain history; they do
not count as implementation or proof completion for this new DAG.
