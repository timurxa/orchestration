# Search workflow for the F* workflow API design

**Status:** workflow design reference. The executable search workflow is [`fstar_pulse_api_design_search.nim`](fstar_pulse_api_design_search.nim). This document describes the search algorithm; it does not choose or implement the F* API. The search itself remains Nim/Vecherinka; the target API and runtime are ordinary F* with normal F* extraction, preferably to OCaml. Pulse, KaRaMeL, and provider-specific model state management are out of scope.

## Objective and approach

The API under study is F* only; the search workflow remains the current Nim/Vecherinka program. Its model processors are search machinery and do not imply that the target API needs LLM state management.

Develop meaningfully different candidate solutions within a fixed work budget. Use bounded beam search and keep one current head per distinct approach. Do not preselect search directions or labels. Mechanisms named in the problem spec are comparison obligations, not required search branches.

Models are typed processors: they frame, propose, develop, compare, or assess values. They never choose the next flow or mutate search state. A deterministic reducer and `so_budget` route use committed typed results and the saved resource snapshot.

## Typed data and durable state

Bootstrap proposal processors see the problem spec and behavior to preserve, but no prior candidate answers or proposed approach list. Bring research reports and existing implementations into grounding and review after the independent proposals return.

```text
StableId = Digest
CriterionId = StableId
ArtifactRef = DurableArtifactId
PrimitiveClaim = { name: Text, contract: Text, library_alternative: Option<Text> }
Criterion = { id: CriterionId, requirement: Text, required: Bool, evidence_kind: Design | Execution | Proof | Analysis }
Finding = { criterion_id: CriterionId, state: Gap | Proposed | SourceSupported | Implemented | Executed | Proved | Refuted, evidence: List<ArtifactRef> }
StructuredProposal = { summary: Text, governing_mechanism: Text, primitive_inventory: List<PrimitiveClaim>, design_artifact: Option<ArtifactRef> }
ProposalSnapshot = { design: Option<StructuredProposal>, findings: List<Finding>, assumptions_and_blockers: List<TypedNote>, evidence: List<ArtifactRef> }
DevelopmentResult = { outcome: Failed | Unfinished | Finished, snapshot: ProposalSnapshot, failure: Option<Failure>, next_target: Option<CriterionId>, new_direction: Option<Direction> }
Direction = { proposal: StructuredProposal, target: CriterionId, difference_from_parent: Text }
ApproachId = StableId
DedupDecision = { incoming_id: StableId, relation: Distinct | SameAs | Unclear, approach_id: Option<ApproachId>, keep_incoming: Bool, evict_approach_id: Option<ApproachId>, rationale: Text }
ApproachHead = { approach_id: ApproachId, candidate_id: StableId, result: ArtifactRef, pending_direction: Option<ArtifactRef> }
DirectionWork = { direction_id: StableId, parent_id: StableId, relation: Distinct | Unclear, direction: Direction }
SearchState = { round: Nat, approaches: List<ApproachHead>, frontier: List<DirectionWork> }
SearchLimits = { beam_width: Nat, exploration_slots: Nat, max_rounds: Nat, max_approaches: Nat, max_frontier: Nat, total_budget: ResourceBound }
```

`DevelopmentResult` is a complete current snapshot, never a patch. `Finished` means its assigned stage target is complete, not that the API problem is solved. `Unfinished` includes a full snapshot and concrete next target. `Failed` retains the last valid snapshot and cause; if a processor fails or returns an invalid schema, a deterministic wrapper builds this result from its input snapshot (or an empty initial snapshot).

Persist the immutable input/limits, processor outputs, full result artifacts, allocation order, and committed transitions in the durable inspectable run store. `SearchState` is only the compact current view; derive approach service counts from the ledger. IDs use run/round/parent/slot, not completion time. Resume reduces committed outputs by allocation ID. Routing is deterministic given saved processor outputs, code/configuration, and budget snapshot; model calls need not be deterministic.

## Search algorithm

1. **Frame once.** Extract typed criteria, required evidence kinds, and prioritized open obligations from the spec. Preserve ordinary-F* `so` code with the full language available inside and outside, dynamic/nested expansion, durable continuation, generic backend substitution, artifact/I/O-state evaluation, proofs, and executable cases. Do not frame Pulse or provider-specific model lifecycle as target requirements. An independent source-grounded audit flags omissions. This is the rubric, not an API proposal.

2. **Discover independently.** Run `B` proposal processors on the same framed task. Each returns one complete result and an open-vocabulary description of its governing mechanism. No approach list or candidate answers appear in these prompts. Compare the batch only after all results return.

3. **Reconcile in one LLM pass.** A small LLM-powered reconciler sees the whole incoming batch and complete typed summaries of live heads and results, including findings, assumptions, blockers, outcomes, and pending targets. It returns one `Distinct`, `SameAs(id)`, or `Unclear` decision per incoming ID, plus whether to keep or replace the incoming result and, when the approach cap requires it, which live head to evict. This lets the processor resolve semantic overlaps and conflicting results from their context. Do not ask it to generate canonical strings or fingerprints. Apply decisions in stable ID order; validate referenced IDs and limits structurally, ignoring malformed choices safely. Preserve transition rationales and every full result in the durable artifact ledger. An unclear candidate retained as provisional gets at most one bounded development attempt.

4. **Choose the beam.** Allocate at most `B` work items per round. Reserve `E` slots for oldest frontier directions, then choose approach heads by least service and stable ID. Fill unused slots from the other lane. Keep the oldest directions when the `F` frontier cap is exceeded. These are scheduling rules only; do not use model-written findings or prose in a deterministic quality ranking.

5. **Develop and reduce.** Develop a direction against the original problem and relevant sources. Develop a head against its full latest snapshot and pending target; if that target is missing, ask the processor to continue the source-grounded rubric audit. A finished result may name an improvement target; with no target it leaves the beam. Do not retry a failed target with the same input. Each allocation returns a complete `DevelopmentResult` and may propose at most one new direction.

   After the batch closes, reconcile results and directions, update heads/frontier, consume selected work (including failed allocations), then increment the round. Only `so_budget` routes, using typed state and the saved resource snapshot; it makes no model call or I/O.

6. **Stop honestly.** Stop at `R` or the total-work bound, or when no eligible action remains. `A` and `F` cap retained approaches and directions; pruning does not itself stop the run. Return full snapshots per retained approach, differences, provenance, failed/unfinished work, dropped directions, unresolved criteria, and stop reason. `CandidateComplete` reflects processor-reported findings and requires every required criterion with its specified evidence kind; independently checked proof/execution artifacts remain necessary to establish those claims. Otherwise report `Incomplete`.

## Flow shape, bounds, and evidence

```text
input -> frame -> fan/lift independent discovery -> dedupe + assess -> approach archive
      -> so_budget(state, saved_resources): select <= B items or stop
      -> fan/lift development or improvement -> LLM reconciliation -> bounded reduce -> loop
```

Use `fan`/`lift` for independent processors and `so_budget` only for bounded data-dependent selection and termination. Freeze `B`, `E`, `R`, `A`, `F`, per-stage admission costs, and total budget in the run manifest; require `B >= 2`, `R, F >= 1`, `A >= 2`, and `1 <= E < B`. Validate bounds structurally, not by prompt. The durable ledger records every allocation and transition. A debug run can substitute scripted typed outputs for proposal, assessment, and deduplication processors to replay identical routing without live services.

## Fit with repository examples

Reuse the problem-kernel example's typed framing, `fan`/`lift`, review, compact state, bounded `so_budget`, and saved budget snapshot. Do not copy its fixed `Approach` enum (`approachConstructive` / `approachCounterexample`): it would preselect search directions. See [`vecherinka_problem_kernel.nim`](vecherinka_problem_kernel.nim) and its [proposal](vecherinka_problem_kernel_proposal.md), the [DSL guide](../docs/vecherinka_dsl_guide.md), and the [budget contract](../docs/vecherinka_budgeting_spec.md). The [problem specification](../docs/fstar_pulse_workflow_api_problem_spec.md) is authoritative. The [migration proposal](../docs/fstar_pulse_migration_proposal.md) and [research report](../docs/fstar_pulse_migration_research_report.md) are pre-pivot evidence: use findings about current API semantics, persistence, artifacts, and recovery, while treating Pulse and provider-specific recommendations as historical. The [SQLite artifact-storage report](../docs/sqlite_artifact_storage_pivot.md) provides additional grounding without prescribing search directions.

The reconciler is a fallible processor; deterministic ID and cap checks do not make its judgments true. Keep rationale visible and do not present model-reported completion as proof. Finite caps can omit promising approaches, so report when they affect retention. This workflow searches for a solution; it does not weaken or claim to discharge the API specification's proof obligations.
