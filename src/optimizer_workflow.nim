{.experimental: "callOperator".}

import std/[macros, os, paths]
import api/vecherinka

const
  case_count = 4
  analysis_profile = luna.medium
  change_profile = luna.high
  optimizer_pools = [(name: "default", weight: 1.0)]

type
  CodeState* = object
    original*: Location
    patch_text*: string

  OptimizerInput* = object
    task*: string
    original*: Location

  ScheduleCase* = object
    name*: string
    payload*: string
    difficulty_reason*: string

  Counterexample = object
    case_name: string
    original_output: string
    candidate_output: string
    explanation: string
    requirement: string

  LoopState = object
    task: string
    current: CodeState
    requirements: seq[string]
    iteration: int

  AnalysisBatch = object
    state: LoopState
    cases: seq[ScheduleCase]

  BenchmarkResult = object
    case_name: string
    valid: bool
    canonical_output: string
    metric: int
    evidence: string

  BenchmarkBatch = object
    analysis: AnalysisBatch
    results: seq[BenchmarkResult]

  RootCauseInput = object
    task: string
    code: CodeState
    benchmark: BenchmarkResult
    requirements: seq[string]

  RootCause = object
    case_name: string
    cause: string
    evidence: string
    requirement: string

  RepairState = object
    task: string
    baseline: CodeState
    cases: seq[ScheduleCase]
    roots: seq[RootCause]
    requirements: seq[string]
    iteration: int
    counterexamples: seq[Counterexample]

  Proposal = object
    summary: string
    changes: seq[string]

  CandidateDraft = object
    patch_artifact: Location

  Candidate = object
    repair: RepairState
    code: CodeState

  CaseVerification = object
    case_name: string
    correct: bool
    no_regression: bool
    improved: bool
    counterexamples: seq[Counterexample]
    requirements: seq[string]

  VerificationSummary = object
    candidate: Candidate
    correct: bool
    no_regression: bool
    improved: bool
    counterexamples: seq[Counterexample]
    requirements: seq[string]

  RepairOutcome = object
    task: string
    exhausted: bool
    code: CodeState
    requirements: seq[string]
    iteration: int
    counterexamples: seq[Counterexample]

  OptimizerResult* = object
    ## Unified diff text itself, not a filename or Location.
    final_patch_text*: string
    iterations*: int
    exhausted*: bool
    counterexamples*: seq[Counterexample]

proc medium_cost(): Budget =
  profile_cost(analysis_profile.model, analysis_profile.effort)

proc change_cost(): Budget =
  profile_cost(change_profile.model, change_profile.effort)

proc can_afford(
    remaining: Budget;
    first_calls: int; first_cost: Budget;
    second_calls: int; second_cost: Budget
): bool =
  ## Mirror runtime admission order; aggregate float multiplication can round
  ## differently from sequential ledger subtraction at an exact boundary.
  var available = remaining
  for _ in 0 ..< first_calls:
    if first_cost > available:
      return false
    available -= first_cost
  for _ in 0 ..< second_calls:
    if second_cost > available:
      return false
    available -= second_cost
  true

proc exhausted_result(state: LoopState): OptimizerResult =
  OptimizerResult(
    final_patch_text: state.current.patch_text,
    iterations: state.iteration,
    exhausted: true,
    counterexamples: @[])

proc append_requirements(
    existing: seq[string]; additions: seq[string]
): seq[string] =
  result = existing
  for addition in additions:
    if addition.len == 0:
      continue
    var duplicate = false
    for prior in result:
      if prior == addition:
        duplicate = true
        break
    if not duplicate:
      result.add(addition)

expandMacros: vecherinka(optimize_autoscheduler, pools = optimizer_pools):
  > initialize OptimizerInput ~> LoopState:
    so(OptimizerInput, LoopState, input) do:
      pure(LoopState(
        task: input.task,
        current: CodeState(original: input.original, patch_text: ""),
        requirements: @[],
        iteration: 0))

  > create_difficult_cases LoopState ~> seq[ScheduleCase]:
    analysis_profile[LoopState, seq[ScheduleCase]](
      "Inspect current code and create exactly four reproducible difficult " &
      "schedule cases. Return each payload as complete compact JSON text in the " &
      "payload string field. Do not return a filename, Location, or create a " &
      "payload file. Each case must expose a likely solver bottleneck. Do not " &
      "modify source. Any solver or harness run must use exactly one worker " &
      "and one CPU core.")

  > keep_loop_state LoopState ~> LoopState:
    so(LoopState, LoopState, input) do:
      pure(input)

  > analyze_cases LoopState ~> AnalysisBatch:
    fan(create_difficult_cases, keep_loop_state) >>> merge_analysis

  > merge_analysis (seq[ScheduleCase], LoopState) ~> AnalysisBatch:
    so((seq[ScheduleCase], LoopState), AnalysisBatch, input) do:
      if input[0].len != case_count:
        raise newException(ValueError, "case generator returned wrong case count")
      pure(AnalysisBatch(state: input[1], cases: input[0]))

  > prepare_benchmark AnalysisBatch ~> seq[(AnalysisBatch, ScheduleCase)]:
    so(AnalysisBatch, seq[(AnalysisBatch, ScheduleCase)], input) do:
      if input.cases.len != case_count:
        raise newException(ValueError, "case generator returned wrong case count")
      var items: seq[(AnalysisBatch, ScheduleCase)] = @[]
      for test_case in input.cases:
        items.add((input, test_case))
      pure(items)

  > benchmark_case (AnalysisBatch, ScheduleCase) ~> BenchmarkResult:
    analysis_profile[(AnalysisBatch, ScheduleCase), BenchmarkResult](
      "Apply current patch to a fresh copy of original source. Run the fixed " &
      "benchmark harness on this schedule case. Return validity, canonical " &
      "output, integer performance metric, and concise evidence. Do not propose " &
      "fixes. Use exactly one solver worker and one CPU core.")

  > run_benchmarks AnalysisBatch ~> seq[BenchmarkResult]:
    prepare_benchmark >>> lift(seq[here])[benchmark_case]

  > keep_analysis AnalysisBatch ~> AnalysisBatch:
    so(AnalysisBatch, AnalysisBatch, input) do:
      pure(input)

  > benchmark_all AnalysisBatch ~> BenchmarkBatch:
    fan(run_benchmarks, keep_analysis) >>>
      merge_benchmark

  > merge_benchmark (seq[BenchmarkResult], AnalysisBatch) ~> BenchmarkBatch:
    so((seq[BenchmarkResult], AnalysisBatch), BenchmarkBatch, input) do:
      pure(BenchmarkBatch(analysis: input[1], results: input[0]))

  > make_root_cause_inputs BenchmarkBatch ~> seq[RootCauseInput]:
    so(BenchmarkBatch, seq[RootCauseInput], input) do:
      var items: seq[RootCauseInput] = @[]
      for benchmark in input.results:
        items.add(RootCauseInput(
          task: input.analysis.state.task,
          code: input.analysis.state.current,
          benchmark: benchmark,
          requirements: input.analysis.state.requirements))
      pure(items)

  > find_root_cause RootCauseInput ~> RootCause:
    analysis_profile[RootCauseInput, RootCause](
      "Find one evidence-backed root cause for this benchmark result. " &
      "Explain purpose of relevant code, identify unnecessary solver work, " &
      "and state one concrete proof-preserving requirement for a fix. Any " &
      "reproduction must use exactly one solver worker and one CPU core.")

  > run_root_causes BenchmarkBatch ~> seq[RootCause]:
    make_root_cause_inputs >>> lift(seq[here])[find_root_cause]

  > keep_benchmark BenchmarkBatch ~> BenchmarkBatch:
    so(BenchmarkBatch, BenchmarkBatch, input) do:
      pure(input)

  > find_root_causes BenchmarkBatch ~> RepairState:
    fan(run_root_causes, keep_benchmark) >>> merge_repair_state

  > merge_repair_state (seq[RootCause], BenchmarkBatch) ~> RepairState:
    so((seq[RootCause], BenchmarkBatch), RepairState, input) do:
      pure(RepairState(
        task: input[1].analysis.state.task,
        baseline: input[1].analysis.state.current,
        cases: input[1].analysis.cases,
        roots: input[0],
        requirements: input[1].analysis.state.requirements,
        iteration: input[1].analysis.state.iteration,
        counterexamples: @[]))

  > propose_solution RepairState ~> Proposal:
    change_profile[RepairState, Proposal](
      "Understand purpose before changing code. Propose the smallest concrete " &
      "solver simplification satisfying all requirements and root causes. " &
      "Preserve exact output, constraints, public behavior, and the mandatory " &
      "single-worker, single-core solver setting.")

  > keep_repair RepairState ~> RepairState:
    so(RepairState, RepairState, input) do:
      pure(input)

  > propose_with_repair RepairState ~> (Proposal, RepairState):
    fan(propose_solution, keep_repair)

  > implement_solution (Proposal, RepairState) ~> CandidateDraft:
    change_profile[(Proposal, RepairState), CandidateDraft](
      "Implement proposal in a fresh copy of original source after applying " &
      "current baseline patch. Preserve all invariants. Do not edit harness. " &
      "Write one unified diff from original source to candidate as candidate.patch. " &
      "Return patch_artifact as a relative Location naming candidate.patch; " &
      "do not put diff text in that field. Keep solver execution restricted to " &
      "one worker and one CPU core.")

  > keep_proposal_repair (Proposal, RepairState) ~> RepairState:
    so((Proposal, RepairState), RepairState, input) do:
      pure(input[1])

  > implement_with_repair (Proposal, RepairState) ~> (CandidateDraft, RepairState):
    fan(implement_solution, keep_proposal_repair)

  > read_candidate (CandidateDraft, RepairState) ~> Candidate:
    so((CandidateDraft, RepairState), Candidate, input, runtime_dir, working_dir) do:
      # CandidateDraft.patch_artifact is already canonical runtime-relative
      # after model-output materialization. Validate producer working_dir there
      # during materialization; resolve the stored Location from runtime_dir.
      let patch_path = runtime_dir / Path(cast[string](input[0].patch_artifact))
      if not fileExists($patch_path):
        raise newException(IOError, "candidate.patch missing")
      pure(Candidate(
        repair: input[1],
        code: CodeState(
          original: input[1].baseline.original,
          patch_text: readFile($patch_path))))

  > make_candidate RepairState ~> Candidate:
    propose_with_repair >>> implement_with_repair >>> read_candidate

  > prepare_verification Candidate ~> seq[(Candidate, ScheduleCase)]:
    so(Candidate, seq[(Candidate, ScheduleCase)], input) do:
      var items: seq[(Candidate, ScheduleCase)] = @[]
      for test_case in input.repair.cases:
        items.add((input, test_case))
      pure(items)

  > verify_case (Candidate, ScheduleCase) ~> CaseVerification:
    analysis_profile[(Candidate, ScheduleCase), CaseVerification](
      "Compare immutable original, pre-optimization baseline, and candidate " &
      "on exactly this case. Run deterministic correctness and performance " &
      "checks with exactly one solver worker and one CPU core. Candidate must " &
      "match original output exactly and not regress. " &
      "If incorrect, minimize and report concrete counterexample plus requirement.")

  > verify_cases Candidate ~> seq[CaseVerification]:
    prepare_verification >>> lift(seq[here])[verify_case]

  > keep_candidate Candidate ~> Candidate:
    so(Candidate, Candidate, input) do:
      pure(input)

  > run_verification Candidate ~> (seq[CaseVerification], Candidate):
    fan(verify_cases, keep_candidate)

  > summarize_verification (seq[CaseVerification], Candidate) ~> VerificationSummary:
    so((seq[CaseVerification], Candidate), VerificationSummary, input) do:
      var correct = true
      var no_regression = true
      var improved = false
      var counterexamples: seq[Counterexample] = @[]
      var requirements: seq[string] = @[]
      for verification in input[0]:
        correct = correct and verification.correct
        no_regression = no_regression and verification.no_regression
        improved = improved or verification.improved
        counterexamples.add(verification.counterexamples)
        requirements = append_requirements(requirements, verification.requirements)
      pure(VerificationSummary(
        candidate: input[1],
        correct: correct,
        no_regression: no_regression,
        improved: improved,
        counterexamples: counterexamples,
        requirements: requirements))

  > route_repair VerificationSummary ~> RepairOutcome:
    so(VerificationSummary, RepairOutcome, input) do:
      if input.correct and input.no_regression and input.improved:
        pure(RepairOutcome(
          task: input.candidate.repair.task,
          exhausted: false,
          code: input.candidate.code,
          requirements: input.candidate.repair.requirements,
          iteration: input.candidate.repair.iteration + 1,
          counterexamples: @[]))
      else:
        let next_requirements = append_requirements(
          input.candidate.repair.requirements, input.requirements)
        var all_requirements = next_requirements
        for counterexample in input.counterexamples:
          all_requirements = append_requirements(
            all_requirements, @[counterexample.requirement])
        var retry = input.candidate.repair
        retry.requirements = all_requirements
        retry.counterexamples = input.counterexamples
        retry >>> repair_loop

  > repair_loop RepairState ~> RepairOutcome:
    so_budget(RepairState, RepairOutcome, input, budget) do:
      if can_afford(
          budget.global_remaining, 2, change_cost(), case_count, medium_cost()):
        input >>> make_candidate >>>
          run_verification >>>
          summarize_verification >>> route_repair
      else:
        pure(RepairOutcome(
          task: input.task,
          exhausted: true,
          code: input.baseline,
          requirements: input.requirements,
          iteration: input.iteration,
          counterexamples: input.counterexamples))

  > continue_outer RepairOutcome ~> OptimizerResult:
    so(RepairOutcome, OptimizerResult, input) do:
      if input.exhausted:
        pure(OptimizerResult(
          final_patch_text: input.code.patch_text,
          iterations: input.iteration,
          exhausted: true,
          counterexamples: input.counterexamples))
      else:
        LoopState(
          task: input.task,
          current: input.code,
          requirements: input.requirements,
          iteration: input.iteration) >>> optimize_loop

  > optimize_loop LoopState ~> OptimizerResult:
    so_budget(LoopState, OptimizerResult, input, budget) do:
      if can_afford(
          budget.global_remaining, 1 + 3 * case_count, medium_cost(),
          2, change_cost()):
        input >>> analyze_cases >>> benchmark_all >>>
          find_root_causes >>> repair_loop >>>
          continue_outer
      else:
        pure(exhausted_result(input))

  > entry OptimizerInput ~> OptimizerResult {.entry.}:
    initialize >>> optimize_loop

proc run_optimizer*(input: OptimizerInput; initial_budget: Budget;
    logger: StructuredLogger = nil): OptimizerResult =
  optimize_autoscheduler(input, initial_budget, logger = logger)
