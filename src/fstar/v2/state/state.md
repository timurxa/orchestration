# F* v2 proof-work state

**Active objective:** build and machine-check the full abstract workflow system
specified in [`../implementation_spec.md`](../implementation_spec.md),
including its contracts, operational semantics, abstract theorem results, and
generic P13 refinement-transfer theorem. Concrete host-specific P13 instances
remain later work. The result will let later implementations inherit system
guarantees by proving their components refine these contracts.

**Active DAG:** [`work_dag.md`](work_dag.md). It is the authoritative future
work graph. Every node A00–H5 is `not_started`; this turn rewrote the plan only
and did not execute any node.

## Intention and boundaries

The abstract system provides total pure local work, nondeterministic external
operations, and pure generation of arbitrary finite typed node DAGs. The
canonical journal is durable state; replay recovers its exact committed
prefix. The abstract executor may run independent ready local/generator nodes
concurrently, the adapter may keep distinct calls in flight, and the journaler
remains serial. The proofs cover static dependent edge compatibility,
provenance, authorization, all permitted schedules, every crash cut, reuse of
committed work, and conditional progress.

The plan is for the abstract verified system and a generic concrete-refinement
interface/theorem. It does not include a SQLite/filesystem journaler, a real
CLI/network adapter, an extracted runner, or a concrete scheduler instance.
Those implementations will have a later DAG and will need to prove their
service instances satisfy the contracts here.

Proofs are required, not a burden to evade. No system theorem may rely on
`assume`/`admit`; contract inputs are explicit records carrying laws. Proof
examples support expressibility but do not replace generic theorems or run as
a test-only substitute.

The graph typing boundary is the manifest-pinned `SchemaSupported` language.
Its schema AST is an F* datatype encoding of the workflow's own restricted
schema DSL, not the F* compiler AST or arbitrary `Type0` reflection. Edge
equality is proved from declared types and static graph constraints for every
legal environment; runtime outputs never rescue an ill-typed edge.

## Normative and planning documents

- [`../implementation_spec.md`](../implementation_spec.md): normative API,
  abstract execution, durability, recovery, and P0–P16 theorem contracts.
- [`../key_correctness_theorems.md`](../key_correctness_theorems.md): theorem
  explanations, especially universal dependent-edge correctness and recovered
  semantic graph correctness.
- [`../implementation_packet.md`](../implementation_packet.md): proposed
  source-module ownership, proof order, signatures, and acceptance checklist;
  subordinate to the spec and active DAG.
- [`work_dag.md`](work_dag.md): all future implementation/proof work and
  review gates.
- [`node_summaries.md`](node_summaries.md): historical S2 planning records;
  new A00–H5 summaries are added only after a node actually starts.
- [`run_log.md`](run_log.md): append-only history, including this
  plan-only transition.
- [`research/registry.md`](research/registry.md): previous design provenance
  and the current DAG planning audits.
- [`legacy_v2_work_dag.md`](legacy_v2_work_dag.md): old V2 DAG retained for
  historical provenance only; it cannot authorize work.

## Current source baseline

The existing seven `.fst` modules are partial source evidence, not P0–P16
proofs. `Graph.fst` contains admitted builder laws, `GraphCodec.fst` proves
syntax encoding rather than typed reconstruction, and `Journal.fst` defines
event vocabulary without replay or durable-store semantics. The generator
chain is an example, not generic builder or generator proof. See the
[read-only planning audit](research/implementation_dag_2026-10-13/source_audit.md)
for file/line evidence. This inspection informed the DAG but did not start
A00 or claim its future acceptance.

## State protocol

Only an explicit user instruction starts execution. Before starting a node,
record it in `run_log.md`; on completion, record artifact and verification
evidence in `node_summaries.md`, then update the node status here and in
`work_dag.md`. Human gates pause until explicit review/resume. Keep table,
diagram, summary, state and log consistent. A plan, source resemblance, or
contract declaration is not proof completion.

**Current execution status:** no A00–H5 node started or completed; no F* code
changed; no F* verification or tests run.
