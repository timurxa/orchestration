# F* workflow API redesign research state

**Status:** Research design complete; implementation specification, typechecking, proof, and host refinement remain future work. This ledger is the durable checkpoint and provenance index. Detailed findings live in [`fstar_workflow_api_research_results/`](fstar_workflow_api_research_results/).

## Objective

Produce an evidence-backed, final API design for the work-node workflow system described in [`fstar_workflow_api_next_research_spec_draft.md`](fstar_workflow_api_next_research_spec_draft.md). The design should be minimal but expressive, ergonomic in F*, compositional, dependent-type capable, resource-aware, durable, and budget-aware. It must encode the document's examples—especially retained input, dependent verified computation, static analysis over files, reusable external adapters, a simple request, and deterministic event scheduling—and generalize to process, network, database, model-context, and similar capabilities.

The proof goal is **expressibility and truth under explicit assumptions**, not cheap or short proofs. Agentic proof-oriented programming is expected to discharge complicated proof engineering. Do not weaken a useful guarantee because proving it is difficult. Distinguish what is proved in F*, what follows from a runtime refinement theorem, what depends on host/adapter assumptions, and what is merely tested.

Adapters must model more than `input bytes -> output bytes`: they may acquire, scope, use, collect, release, and recover live capabilities such as workspaces/file handles, processes, sockets/sessions, transactions/cursors, or remote state. Durable plans store logical descriptions and evidence, not process-local handles. Inline and reusable-library authoring should be two nearly identical packaging forms of the same interface and semantics.

## Scope and constraints

- Investigate the current source and the research spec; preserve traceable source locations and assumptions.
- Keep materially different API/resource/proof formulations alive until compared against the acceptance cases.
- Make decisions only after checking expressiveness, durability, extraction/runtime boundaries, and ergonomics.
- Do not treat proof complexity as a negative score; report impossible claims and trust assumptions precisely.
- Do not modify implementation code, build, or run tests in this research phase unless the user later authorizes implementation/verification. Use read-only source archaeology, formal modeling, and previously recorded test evidence; record commands, results, and limits for any later authorized experiment.
- User requested ongoing assignment/reassignment of subagents. Track worker identity separately from assignments and redirect them at checkpoints.

## Acceptance criteria

1. Compare API forms for identity/retention/projection, sequential and dependent composition, branch/failure behavior, static routing, and codecs.
2. Give explicit dependent-output and/or postcondition signatures, composition laws, and a concrete verified-computation example.
3. Compare at least two resource/adapter architectures that support effectful nodes and live handles, with creation/use/collection/recovery semantics.
4. Explain how file analysis and returned files, network/session operations, database state, and reusable JEV-like adapters fit without making `Blob` a universal kernel primitive.
5. Make inline and library authoring share types, contracts, and semantics; identify their actual packaging difference.
6. State no-rerun, recovery-at-every-cut, adapter safety/progress, budget, codec, artifact, and model-to-runtime properties in quantified/formal form; label assumptions and impossibility boundaries.
7. Recommend a final minimal design and record rejected alternatives with reasons, evidence, counterexamples, and unresolved risks.
8. Have a non-author adversarial reviewer audit the integrated design; address or retain each objection.

## Source and evidence provenance

| Source | Role | Status |
|---|---|---|
| `src/docs/fstar_workflow_api_next_research_spec_draft.md` | Current requirements and proof/acceptance claims | Primary task specification |
| `src/fstar/v0/WorkflowCore.fst` | Current typed workflow combinators and external operation model | Inspected directly; see `current_implementation_map.md` |
| `src/fstar/v0/WorkflowStore.fst` | Durable state, codecs, event/reducer semantics | Inspected directly; see `current_implementation_map.md` |
| `src/fstar/v0/WorkflowExamples.fst` | Current workflow examples and test-oriented usage | Inspected directly; no tests rerun |
| `src/fstar/v0/Runner.ml` | Extracted OCaml JSON snapshot and dummy adapter/event loop | Inspected directly; see `current_implementation_map.md` |
| `src/docs/fstar_typed_plan_workflow_api_outline.md` | Prior problem/requirements source | Read as needed |
| `src/docs/fstar_typed_plan_workflow_api_report.md` | Current implementation report and evidence | Read as needed |
| `src/docs/fstar_pulse_workflow_api_problem_spec.md` | Historical workflow problem framing | Read as needed |
| `src/docs/fstar_workflow_api_research_results/` | Independent investigations, formal models, comparisons, and reviews | Active results directory |

Every substantial result should include source paths/lines or primary citations, assumptions, method, strongest objection, and next question. Label statements as **observed**, **derived**, **assumed**, **conjectured**, or **decision**.

## Approach registry

| Assignment | Method family | Artifact/evidence | Quality | Distinct contribution | Gap/next action | Worker/status |
|---|---|---|---|---|---|---|
| Codebase baseline | Root source archaeology | `current_implementation_map.md` | Source-checked; historical tests only | Ground proposals in actual F* types, store, extraction, and runner | Source observations are complete; tests remain historical evidence | Root / complete |
| API design alternatives | Dependent/dataflow formulations and adversarial review | `api_composition_alternatives.md`, `adversarial_review.md`, `api_surface_candidate.md`, `final_api_review.md`, `final_api_review_resolution.md`, `final_api_provenance_recheck.md` | Semantic signatures remain uncompiled; independent API audit complete | Compare dependent results, evidence persistence, retention, static composition, and analyzer provenance | Typecheck in implementation phase; provenance issue addressed in §§6–7/10 | `/root/api_design_space`, `/root/toolchain_probe`, `/root/api_alternatives` complete |
| Proof semantics | Formal state/trace and theorem decomposition | `durability_proof_semantics.md`, `proof_model_critique.md`, `refined_proof_targets.md`, `final_proof_review.md`, `final_proof_review_resolution.md` | Theorem targets refined; no proof/build run | State quantified recovery/no-rerun/adapter laws and impossibility boundaries | Host storage/adapter refinement remains future proof work | `/root/proof_semantics`, `/root/proof_ledger` complete |
| Resource/adapter architecture | Capability/resource calculus and packaging comparison | `resource_adapter_architectures.md`, `whole_operation_adapter_contract.md`, `final_resource_review_resolution.md` | Whole-operation kernel boundary selected; scoped library optional; final audit complete | Compare live-resource ownership, materialization, publication, and recovery | Resource review prompted explicit report provenance, now integrated | `/root/resource_adapters` complete |
| F* feasibility | Primary-source review of dependent types, ghost evidence, effects, extraction | `fstar_feasibility.md`, `final_api_review.md` | Primary-source review complete; sketches uncompiled | Separate language capability from workflow/runtime claim | No new language-level blocker reported; actual typecheck remains implementation work | `/root/toolchain_probe` complete |
| Synthesis and decision | Cross-check designs against examples, current implementation, proofs, and adversarial reviews | `design_comparison_and_decision.md` | Integrated candidate reviewed and finalized as research design | Select smallest design meeting examples and expressible proof targets | Implementation phase must discharge listed assumptions and typecheck/proofs | Root / complete |

## Final research decisions

- Keep the work-node model and use `Work I O` with input-indexed output families. Put refinement/evidence in the output; expose `Verified` as a convenience alias, not a second kernel semantics.
- Restore `it`/`id`, rename same-input pairing `fork` to `fan`, and provide `keep_input`. Use static context composition (`then_keep`) so downstream nodes receive original input plus intermediate value/evidence; never persist arbitrary continuations.
- Use one whole-operation external adapter node as the kernel resource boundary. It owns resource acquisition/materialization/use/collection/recovery. F* validates raw results and proves local parsing/checking. A scoped capability effect stays optional library research for a concrete multi-step use case.
- Treat `BlobTree` and similar types as domain values interpreted by specific adapters. Kernel storage is generic typed bytes/references and completion state; it does not define universal Blob primitives or persist live handles.
- Define durable completion only at a committed validated-result/artifact record. Memoize every local work-node result if strict no-reinvoke is required; incomplete pure computation may rerun after crash. Long jobs need explicit durable checkpoints.
- Make recovery prefix safety the base theorem. Stronger resumed/uninterrupted equivalence requires backend-state relation/bisimulation and scheduler trace equivalence. Without adapter idempotency or truthful reconciliation, keep `Unknown`.
- Keep `Unknown` as durable run/attempt status while the workflow suspends, never as a fabricated typed result. Automatic retries/polls/reconciliation are finite and budgeted; explicit reconciliation uses the same operation key and a fresh call ID; only evidence-backed `NotApplied` can permit a new attempt.
- Use a per-call budget ledger for dispatch, retry, poll, and reconciliation. The kernel proves admission arithmetic; actual provider spend is a separate evidence-backed claim. Overcharge is recorded and quarantined, never clamped.
- Target the existing single-writer JSON snapshot store for the first host refinement. Require supported durable file/directory sync behavior and one active runner per run. Current ignored sync errors and per-write-only locking do not satisfy that proof yet; SQLite would need its own refinement.
- Bind accepted external outputs to an indexed result codec/checker. Persist validated data or raw response for pinned revalidation; never rely on an erased proof object.
- In static analysis, type parsed findings to accepted report bytes and unverified findings to a successful-parse witness. Materialization and collection remain host refinement obligations.
- Bind analyzer output to a `ReportProvenance` receipt containing source-tree, tool, config, exact operation key, report, and output-manifest digests. F* checks the receipt relation; actual tool execution against those bytes remains an adapter/host refinement or trusted-attestation premise.
- Proof complexity is not a design criterion. Prove every true property under explicit assumptions; keep the host/adapter boundary visible.

## Round log

### Round 0 — Setup

- Created this state ledger and the dedicated results directory.
- Created an active research goal for the full API/resource/proof design investigation.
- Next: independent workstreams inspect alternatives, formal semantics, and resource protocols; root audits the actual source and build/proof entrypoints.

### Round 1 — Baseline and independent proposals

- Inspected current core/store/examples/runner/spec/report and recorded observed behavior versus design implications in `current_implementation_map.md`. No build or tests were run; report test outcomes remain historical evidence.
- Received `api_composition_alternatives.md`, `durability_proof_semantics.md`, and `resource_adapter_architectures.md`.
- Independent critique (`proof_model_critique.md`) rejects unqualified whole-trace recovery equivalence and flags a typed lifecycle interpreter as a possible second workflow DSL. Current best candidate shifts toward a minimal whole-operation durable kernel, with resource-specific scoped/protocol abstractions in ordinary F* libraries only where needed.
- Official F* primary tutorials support dependent types/refinements and effect specifications, but not this workflow's persistence or extracted-runtime simulation theorem. URLs and claim scope are recorded in `current_implementation_map.md`.
- `/root/api_alternatives` completed an adversarial review; `/root/proof_ledger` completed a proof-model critique; `/root/toolchain_probe` completed primary-source F* feasibility notes.
- Round 2 then assigned API, refined-theorem, and whole-operation-contract reports; these have been integrated into the candidate decision.

### Round 2 — Critique and design convergence

- Independent API review recommends dependent `Work<I,O>` with same-input `fan`, a retained-input helper, and context-based static sequencing; `then_keep` is an ergonomic library layer rather than a dynamic continuation.
- Two critiques converge on a whole-operation adapter as the smallest kernel boundary for CLI/network/JEV calls. Keep scoped resource capabilities as an optional ordinary-F* library design only when a concrete workflow must interleave resource operations; do not make a typed lifecycle interpreter mandatory in the kernel.
- F* feasibility review confirms dependent arrows/refinements and user-defined effect specifications are documented language features; durable handles, restartable continuations, extracted host refinement, and resource safety are not automatic consequences.
- Round 2 reports now cover the API surface, precise whole-operation adapter contract, and refined proof targets. All are semantic proposals, not compiled signatures or established runtime theorems.
- Wrote `design_comparison_and_decision.md` as the integrated decision. `/root/toolchain_probe` now audits F* signatures/claims, and `/root/proof_ledger` audits theorem boundaries. Their findings are pending.
- Next: address every final-review objection, check artifact provenance and internal consistency, and update this ledger with final status plus remaining questions.

### Round 3 — integrated-design audit and closure

- `/root/proof_ledger` reviewed P2–P6. The integrated decision now binds resume traces to exact run/plan/input/node identities; gives old/new/uncertain snapshot-cut outcomes; gates artifact visibility behind completion; fences late worker replies; specifies enabled durable timeout actions; and chooses a per-call ledger for dispatch/redelivery/poll/reconciliation. Remaining findings are runtime obligations: actual storage refinement, truthful adapter evidence, durable timeout implementation, and uniqueness/concurrency proofs.
- `/root/toolchain_probe` reviewed the API. Added an indexed accepted-result codec and error payload codecs, clarified `Verified` for any output family, and documented dependent-pair notation as semantic until typechecked.
- `/root/api_design_space` found analyzer provenance was underconstrained. The example now requires accepted raw report evidence and a `Parses` witness for `Parsed`, and a `HasSuccessfulParse` witness for `Unverified`; parse success cannot be claimed for rejected/failed adapter results.
- Selected finite automatic retry/poll/reconciliation; after exhaustion, persist `Unknown`. Explicit later reconciliation is a fresh budgeted call under the same operation key. Selected the existing JSON snapshot path as the first host-refinement target; its ignored sync errors and single-active-run requirement remain future proof/implementation work.
- `/root/resource_adapters` found analyzer result provenance was not explicit. Added `OperationContext` to accepted outcomes and validator input, and `ReportProvenance` checks for source/tool/config/key/report/output digests; the adapter review then found no additional defect. `/root/api_design_space` rechecked the fix and reported none.
- Added final review resolutions to the integrated decision and results index. The research design is complete. No implementation code, F* signatures, build, proof, or tests were changed or run; the listed properties remain proposed proof targets, not established results.

## Remaining implementation-spec questions

Core direction is decided. Remaining questions concern exact encodings and host/runtime obligations, not reasons to weaken the chosen design:

1. Typecheck exact dependent-pair/universe syntax, indexed codecs, equality transports, and terminal error/result combinators.
2. Choose whether completion values live inline, in content-addressed storage, or both; keep the no-rerun theorem independent of this choice.
3. Specify per-operation retry/poll/reconcile limits, timeout values, and the durable timeout worker.
4. Prove code/build identity and migration policy for plans, callbacks, codecs, validators, adapters, and tool binaries. Hash-based identity assumes canonical encoding and collision resistance.
5. Prove JSON snapshot cuts on the supported OS/filesystem profile; unsupported directory sync must fail the commit contract. Ensure one run has one active evaluator.
6. Prove adapter evidence authenticity/truthfulness and idempotency/reconciliation assumptions per backend. Current reducer evidence fields are weaker than this target.
7. Define artifact retention/garbage collection; after missing/corrupt content report `Unavailable/Corrupt` and never silently re-execute.
8. Add a concrete DB cursor case only if needed to justify scoped capabilities; whole-operation adapters suffice for the initial acceptance suite.
