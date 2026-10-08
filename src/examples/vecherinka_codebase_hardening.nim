## Compare bottom-up behavior specifications with an explicit hardening spec,
## then plan, apply, and review the smallest supported changes.

{.experimental: "callOperator".}

import std/[os, paths]
import ../api/vecherinka

const
  initial_budget = 120.0
  source_root_name = "codebase"
  max_revision_passes = 2

type
  HardeningInput = tuple[codebase: BlobTree, specification: Blob]

  ActionSpec = object
    id: string
    source_refs: seq[string]
    preconditions: seq[string]
    state_changes: seq[string]
    postconditions: seq[string]
    failures: seq[string]

  SystemSpec = object
    id: string
    actions: seq[ActionSpec]
    invariants: seq[string]
    complete: bool
    unknowns: seq[string]

  Formalization = object
    systems: seq[SystemSpec]
    complete: bool
    gaps: seq[string]

  Finding = object
    id: string
    system_ids: seq[string]
    evidence_refs: seq[string]
    observed_behavior: string
    required_behavior: string
    impact: string
    confidence: string

  Findings = object
    items: seq[Finding]
    complete: bool
    unresolved: seq[string]

  ChangeDecision = enum
    cdApply,
    cdRecommend

  ChangeProposal = object
    finding_ids: seq[string]
    decision: ChangeDecision
    files: seq[string]
    rationale: string
    acceptance_conditions: seq[string]
    unresolved: seq[string]

  ChangePlan = object
    proposals: seq[ChangeProposal]
    complete: bool

  Execution = object
    candidate: BlobTree
    changed_files: seq[string]
    applied_findings: seq[string]
    deferred_findings: seq[string]
    summary: string

  ReviewStatus = enum
    rsSupported,
    rsRejected,
    rsUnknown

  ReviewCheck = object
    finding_id: string
    status: ReviewStatus
    evidence_refs: seq[string]
    explanation: string

  Review = object
    checks: seq[ReviewCheck]
    complete: bool
    unknowns: seq[string]

  ReviewCycle = tuple[
    input: HardeningInput,
    formalization: Formalization,
    findings: Findings,
    plan: ChangePlan,
    execution: Execution,
    revision: int]

  ReviewedCycle = tuple[
    input: HardeningInput,
    formalization: Formalization,
    findings: Findings,
    plan: ChangePlan,
    execution: Execution,
    review: Review,
    revision: int]

  HardeningOutput = object
    candidate: BlobTree
    report: Blob

const
  formalize_profile = luna.high
  reconcile_profile = luna.high
  plan_profile = luna.high
  rewrite_profile = luna.xhigh
  review_profile = luna.xhigh
  report_profile = luna.medium

proc has_rejected(review: Review): bool =
  for check in review.checks:
    if check.status == rsRejected:
      return true

proc increment_revision(revision: int): int =
  revision + 1

proc make_reviewed_cycle(pair: (ReviewCycle, Review)): ReviewedCycle =
  let (cycle, review) = pair
  (input: cycle.input, formalization: cycle.formalization,
    findings: cycle.findings, plan: cycle.plan, execution: cycle.execution,
    review: review, revision: cycle.revision)

proc make_review_cycle(
    input: (HardeningInput, Formalization, Findings, ChangePlan, Execution),
    revision: int): ReviewCycle =
  (input: input[0], formalization: input[1], findings: input[2],
    plan: input[3], execution: input[4], revision: revision)

proc make_revision_cycle(
    input: (HardeningInput, Formalization, Findings, ChangePlan, Execution,
      int)): ReviewCycle =
  (input: input[0], formalization: input[1], findings: input[2],
    plan: input[3], execution: input[4], revision: input[5])

const hardening_prompts = AgentPromptTemplates(
  developer_instructions: checked_prompt(
    """Perform only the assigned typed task. Use the supplied codebase and
hardening specification; do not browse, delegate, or execute code. Keep claims
tied to source references, preserve uncertainty, and submit exactly the
declared result through finish_work."""),
  goal: checked_prompt(
    "Harden only the supplied scope to the degree stated in its hardening specification."),
  turn_prompt: checked_prompt(
    """$task

Read the exact typed inputs from vecherinka_model_input_materialization.txt in
$working_dir. Blob and BlobTree inputs are materialized there. Treat source
paths as relative to the codebase root named `codebase`, not to the temporary
workspace. For Blob or BlobTree outputs, create only the requested output under
$working_dir and return a workspace-relative path. Do not claim tests or proof
that were not performed. Submit once through finish_work.

$input""",
    "task", "input", "working_dir"),
  finish_work_description: checked_prompt(
    "Submit the complete result for this bounded task using its declared schema."))

vecherinka(solve_codebase_hardening, hardening_prompts):
  > formalize HardeningInput ~> Formalization:
    formalize_profile[HardeningInput, Formalization](
      "Read the hardening specification first and formalize current behavior " &
      "bottom up for every system and action in its scope. Trace leaf " &
      "operations through callers to externally visible behavior. Record " &
      "preconditions, state changes, postconditions, failures, invariants, " &
      "and exact source references. Describe implementation behavior only; " &
      "do not infer intent or propose fixes. Mark incomplete scope and list " &
      "unknowns instead of guessing. The full source snapshot and the " &
      "separate hardening-spec file are both supplied as typed inputs.")

  > reconcile (HardeningInput, Formalization) ~> Findings:
    reconcile_profile[(HardeningInput, Formalization), Findings](
      "Compare the formalized behavior with the hardening specification and " &
      "the surrounding codebase. Identify only evidence-backed defects, " &
      "specification mismatches, cross-system conflicts, and missing " &
      "invariants within scope. Assimilate duplicate or dependent findings " &
      "while preserving distinct evidence and consequences. Keep uncertain " &
      "intent explicit in unresolved; do not guess a correction. If the " &
      "formalization omitted material scope, set complete=false.")

  > propose (HardeningInput, Formalization, Findings) ~> ChangePlan:
    plan_profile[(HardeningInput, Formalization, Findings), ChangePlan](
      "Propose the smallest structural or local changes that reach the " &
      "hardening degree in the supplied specification. Use cdApply only when " &
      "the required behavior is clear and acceptance conditions are " &
      "evidence-based; otherwise use cdRecommend. Preserve compatible " &
      "behavior, state affected files and concrete acceptance conditions, " &
      "and keep unresolved decisions explicit. Do not write code. Set " &
      "complete=false if the findings or plan omit material scope.")

  > rewrite (HardeningInput, ChangePlan) ~> Execution:
    rewrite_profile[(HardeningInput, ChangePlan), Execution](
      "Apply only cdApply proposals supported by the hardening specification. " &
      "Return the complete candidate codebase, preserving every file outside " &
      "the authorized changes. If the plan is incomplete, apply no edits and " &
      "return the source snapshot unchanged. Do not run code or claim tests. " &
      "List changed files, applied and deferred finding ids, and a concise " &
      "summary. Leave unsafe or underspecified proposals unapplied.")

  > review_candidate (HardeningInput, Formalization, Findings, ChangePlan,
      Execution) ~> Review:
    review_profile[(HardeningInput, Formalization, Findings, ChangePlan,
      Execution), Review](
      "Review the candidate against the hardening specification, every " &
      "formalized behavior, finding, and acceptance condition. Check that " &
      "untargeted behavior is preserved and no new contradiction is added. " &
      "For each finding classify the candidate as rsSupported, rsRejected, " &
      "or rsUnknown and cite evidence. Treat unrun checks and absent proof as " &
      "unknown. Mark incomplete review and list its gaps; do not claim formal " &
      "proof or test success from inspection.")

  > revise_candidate (HardeningInput, Formalization, Findings, ChangePlan,
      Execution, Review) ~> Execution:
    rewrite_profile[(HardeningInput, Formalization, Findings, ChangePlan,
      Execution, Review), Execution](
      "Repair only the rsRejected checks in this review. Use the hardening " &
      "specification, original behavior, and acceptance conditions as the " &
      "limits for repair. Preserve unknown checks without guessing and do not " &
      "expand scope. Return a complete revised candidate and cumulative " &
      "changed, applied, and deferred lists. Do not run code or claim tests.")

  > report ReviewedCycle ~> Blob:
    report_profile[ReviewedCycle, Blob](
      "Write hardening-report.md from the supplied structured results. " &
      "Summarize the requested scope and degree, observed behavior, " &
      "assimilated findings, proposals, applied changes, candidate review, " &
      "unresolved decisions, revision pass count, and coverage limits. The " &
      "workflow allows at most " & $max_revision_passes & " repair passes. " &
      "Separate evidence from " &
      "inference. State that static review is not formal proof and list unrun " &
      "checks as unverified. Do not infer details absent from the typed data.")

  > with_reconciliation (HardeningInput, Formalization) ~>
      (HardeningInput, Formalization, Findings):
    fan(
      it((HardeningInput, Formalization))[0],
      it((HardeningInput, Formalization))[1],
      reconcile)

  > with_plan (HardeningInput, Formalization, Findings) ~>
      (HardeningInput, Formalization, Findings, ChangePlan):
    fan(
      it((HardeningInput, Formalization, Findings))[0],
      it((HardeningInput, Formalization, Findings))[1],
      it((HardeningInput, Formalization, Findings))[2],
      propose)

  > with_execution (HardeningInput, Formalization, Findings, ChangePlan) ~>
      (HardeningInput, Formalization, Findings, ChangePlan, Execution):
    fan(
      it((HardeningInput, Formalization, Findings, ChangePlan))[0],
      it((HardeningInput, Formalization, Findings, ChangePlan))[1],
      it((HardeningInput, Formalization, Findings, ChangePlan))[2],
      it((HardeningInput, Formalization, Findings, ChangePlan))[3],
      fan(
        it((HardeningInput, Formalization, Findings, ChangePlan))[0],
        it((HardeningInput, Formalization, Findings, ChangePlan))[3]) >>>
        rewrite)

  > review_once ReviewCycle ~> ReviewedCycle:
    fan(
      it(ReviewCycle),
      fan(
        it(ReviewCycle)[0], it(ReviewCycle)[1], it(ReviewCycle)[2],
        it(ReviewCycle)[3], it(ReviewCycle)[4]) >>> review_candidate) >>>
      attach_review

  > attach_review (ReviewCycle, Review) ~> ReviewedCycle:
    so((ReviewCycle, Review), ReviewedCycle, input) do:
      pure(make_reviewed_cycle(input))

  > next_revision int ~> int:
    so(int, int, input) do:
      pure(increment_revision(input))

  > revise_execution ReviewedCycle ~> Execution:
    fan(
      it(ReviewedCycle)[0], it(ReviewedCycle)[1], it(ReviewedCycle)[2],
      it(ReviewedCycle)[3], it(ReviewedCycle)[4], it(ReviewedCycle)[5]) >>>
      revise_candidate

  > revise_cycle ReviewedCycle ~> ReviewCycle:
    fan(
      it(ReviewedCycle)[0], it(ReviewedCycle)[1], it(ReviewedCycle)[2],
      it(ReviewedCycle)[3], revise_execution,
      it(ReviewedCycle)[6] >>> next_revision) >>> pack_review_cycle

  > pack_review_cycle (HardeningInput, Formalization, Findings, ChangePlan,
      Execution, int) ~> ReviewCycle:
    so((HardeningInput, Formalization, Findings, ChangePlan, Execution, int),
        ReviewCycle, input) do:
      pure(make_revision_cycle(input))

  > route_review ReviewedCycle ~> ReviewedCycle:
    so(ReviewedCycle, ReviewedCycle, input) do:
      if has_rejected(input[5]) and input[6] < max_revision_passes:
        input >>> revise_cycle >>> review_once >>> route_review_again
      else:
        pure(input)

  > route_review_again ReviewedCycle ~> ReviewedCycle:
    so(ReviewedCycle, ReviewedCycle, input) do:
      if has_rejected(input[5]) and input[6] < max_revision_passes:
        input >>> revise_cycle >>> review_once
      else:
        pure(input)

  > start_review (HardeningInput, Formalization, Findings, ChangePlan,
      Execution) ~> ReviewedCycle:
    so((HardeningInput, Formalization, Findings, ChangePlan, Execution),
        ReviewedCycle, input) do:
      make_review_cycle(input, 0) >>> review_once >>> route_review

  > package_output (BlobTree, Blob) ~> HardeningOutput:
    so((BlobTree, Blob), HardeningOutput, input) do:
      pure(HardeningOutput(candidate: input[0], report: input[1]))

  > package_result ReviewedCycle ~> HardeningOutput:
    fan(
      it(ReviewedCycle)[4][candidate],
      report) >>> package_output

  > hardening_entry HardeningInput ~> HardeningOutput {.entry.}:
    fan(it(HardeningInput), formalize) >>>
      with_reconciliation >>> with_plan >>> with_execution >>> start_review >>>
      package_result

proc materialize_output(output: HardeningOutput; output_dir: Path) =
  if not dirExists($output_dir):
    createDir($output_dir)
  let candidate_dir = output_dir / Path("candidate")
  let report_path = output_dir / Path("hardening-report.md")
  if fileExists($report_path) or dirExists($report_path) or
      symlinkExists($report_path) or dirExists($candidate_dir) or
      fileExists($candidate_dir) or symlinkExists($candidate_dir):
    raise newException(IOError, "output already exists: " & $output_dir)
  materializeBlobTree(output.candidate, candidate_dir)
  materializeBlob(output.report, report_path)

proc absolute_argument(value, name: string): Path =
  if not isAbsolute(value):
    quit(name & " must be an absolute path: " & value, 2)
  Path(absolutePath(value))

when isMainModule:
  if paramCount() != 4:
    quit("Usage: vecherinka_codebase_hardening " &
      "SOURCE_DIR HARDENING_SPEC_FILE OUTPUT_DIR DATABASE_PATH", 2)

  var codebase = blobTreeFromDirectory(
    absolute_argument(paramStr(1), "SOURCE_DIR"))
  codebase.suggestedFilename = source_root_name
  let specification = blobFromFile(
    absolute_argument(paramStr(2), "HARDENING_SPEC_FILE"))
  let input: HardeningInput = (codebase, specification)
  let output_dir = absolute_argument(paramStr(3), "OUTPUT_DIR")
  let database_path = absolute_argument(paramStr(4), "DATABASE_PATH")
  let database_parent = parentDir($database_path)
  if database_parent.len > 0:
    createDir(database_parent)
  echo "SQLite database: ", database_path
  let output = solve_codebase_hardening(input, initial_budget,
    hardening_prompts, database_path = database_path)
  materialize_output(output, output_dir)
  echo "Candidate codebase: ", output_dir / Path("candidate")
  echo "Hardening report: ", output_dir / Path("hardening-report.md")
