## Turn a proposal, required changes, and intention into a formal Typst
## specification plus a separate mismatch and gap audit.

{.experimental: "callOperator".}

import std/[os, paths]
import ../api/vecherinka

const
  max_items = 8
  max_findings_per_review = 4
  max_source_ref_chars = 80
  max_finding_chars = 240
  initial_budget = 17.5

type
  FormalizerInput = object
    proposal: Blob
    required_changes: Blob
    intention: Blob

  FindingKind = enum
    fkObligation, fkClause, fkConflict, fkGap, fkMismatch, fkDefect

  FindingAction = enum
    faFormalize, faRepair, faReport

  Finding = object
    kind: FindingKind
    action: FindingAction
    source_ref: string
    text: string

  Inventory = object
    items: seq[Finding]
    complete: bool

  Candidate = object
    formalization: Blob

  Review = object
    findings: seq[Finding]
    complete: bool

  ReviewState = object
    candidate: Candidate
    inventory: Inventory
    findings: seq[Finding]
    review_complete: bool

  AuditInput = object
    inventory: Inventory
    candidate: Candidate

  AuditBranches = tuple[
    context: tuple[source: FormalizerInput, audit: AuditInput],
    coverage: Review,
    intention: Review,
    rigor: Review,
    typst: Review]

  OutputInput = tuple[
    source: FormalizerInput,
    state: ReviewState]

  FormalizerOutput = object
    formalization: Blob
    audit: Blob

const
  inventory_profile = luna.medium
  item_profile = luna.medium
  synthesis_profile = luna.high
  coverage_profile = luna.high
  intention_profile = luna.high
  rigor_profile = luna.xhigh
  typst_profile = luna.medium
  repair_profile = luna.xhigh
  output_profile = luna.medium

proc has_repair(findings: openArray[Finding]): bool =
  for finding in findings:
    if finding.action == faRepair:
      return true

proc bounded_inventory(inventory: Inventory): Inventory =
  result = inventory
  if result.items.len > max_items:
    result.items.setLen(max_items)
    result.complete = false
  for item in result.items.mitems:
    if item.source_ref.len > max_source_ref_chars:
      item.source_ref.setLen(max_source_ref_chars)
      result.complete = false
    if item.text.len > max_finding_chars:
      item.text.setLen(max_finding_chars)
      result.complete = false

proc append_review(findings: var seq[Finding]; review: Review;
    review_complete: var bool) =
  if review.findings.len > max_findings_per_review:
    review_complete = false
  for index, finding in review.findings:
    if index >= max_findings_per_review:
      break
    var bounded = finding
    if bounded.source_ref.len > max_source_ref_chars:
      bounded.source_ref.setLen(max_source_ref_chars)
      review_complete = false
    if bounded.text.len > max_finding_chars:
      bounded.text.setLen(max_finding_chars)
      review_complete = false
    findings.add(bounded)

proc merge_reviews(reviews: AuditBranches): ReviewState =
  result.candidate = reviews.context.audit.candidate
  result.inventory = reviews.context.audit.inventory
  result.review_complete = reviews.context.audit.inventory.complete and
    reviews.coverage.complete and
    reviews.intention.complete and reviews.rigor.complete and
    reviews.typst.complete
  append_review(result.findings, reviews.coverage, result.review_complete)
  append_review(result.findings, reviews.intention, result.review_complete)
  append_review(result.findings, reviews.rigor, result.review_complete)
  append_review(result.findings, reviews.typst, result.review_complete)

const formalizer_prompts = AgentPromptTemplates(
  developer_instructions: checked_prompt(
    "Complete only the assigned bounded workflow step. Submit through finish_work exactly once. Use supplied files and local workspace operations only; do not browse, use network services, delegate, or inspect unrelated files. If finish_work reports a schema error, correct only the rejected result."),
  goal: checked_prompt(
    "Complete the assigned step within its stated scope and submit its typed result through finish_work."),
  turn_prompt: checked_prompt(
    "$task\n\nUse the exact typed values in vecherinka_model_input_materialization.txt in $working_dir. Read only input files relevant to this step. For Blob outputs, create only the requested regular file in $working_dir and return its workspace-relative filename. Never return absolute paths or paths containing parent traversal. Runtime support files are in $runtime_dir. Do not browse, delegate, or explore unrelated files. Keep output within the requested field and length limits. Call finish_work once when complete.\n\n$input",
    "task", "input", "working_dir", "runtime_dir"),
  finish_work_description: checked_prompt(
    "Submit the complete result for this step using the declared schema. Call once; if validation rejects it, correct the specified fields."))

vecherinka(solve_formalizer, formalizer_prompts):
  > inventory FormalizerInput ~> Inventory:
    inventory_profile[FormalizerInput, Inventory](
      "Inspect the proposal, required_changes, and intention. Extract every " &
      "independently actionable obligation, conflict, and specification gap. " &
      "Return at most 8 source-linked items. Group related items only when " &
      "one formal clause can satisfy them without losing a requirement. Each " &
      "source_ref is a short filename plus heading or section, at most 80 " &
      "characters; each text is at most 240 characters. Set " &
      "obligation.action=faFormalize. Set " &
      "conflicts and gaps to faReport. Set complete=true only if all relevant " &
      "obligations, conflicts, and gaps fit in the returned items; otherwise " &
      "set complete=false and identify the omitted scope in a gap item. Do not " &
      "write a draft or solve the obligations.")

  > keep_input FormalizerInput ~> FormalizerInput:
    so(FormalizerInput, FormalizerInput, input) do:
      pure(input)

  > inspect_input FormalizerInput ~> (FormalizerInput, Inventory):
    fan(keep_input, inventory)

  > formalize_item Finding ~> Finding:
    so(Finding, Finding, item) do:
      if item.action == faFormalize:
        item >>> item_profile[Finding, Finding](
          "Formalize only this obligation as one concise Typst clause. Keep " &
          "the source_ref unchanged. Define introduced terms or use terms " &
          "defined by the source. Prefer rigorous notation to prose; add one " &
          "short intuition sentence for a large equation. Do not resolve " &
          "unrelated issues, add requirements, or create extra files. Return " &
          "kind=fkClause, action=faReport, and the clause in text.")
      else:
        pure(item)

  > extract_items (FormalizerInput, Inventory) ~> seq[Finding]:
    so((FormalizerInput, Inventory), seq[Finding], input) do:
      pure(input[1].items)

  > formalize_items seq[Finding] ~> seq[Finding]:
    lift(seq[here])[formalize_item]

  > assemble (FormalizerInput, seq[Finding]) ~> Candidate:
    synthesis_profile[(FormalizerInput, seq[Finding]), Candidate](
      "Using the three original files and supplied source-linked items, write " &
      "the modified proposal as one standalone Typst file named " &
      "formalization.typ. Apply every unambiguous required change, preserve " &
      "compatible proposal content and intention, and keep conflicts or " &
      "underspecified choices explicit. Define every term. Prefer rigorous " &
      "math to prose and include brief intuition for large equations. Be " &
      "concise, targeting at most 3000 words unless the inputs require more. " &
      "Do not drop assumptions or obligations. Use no external " &
      "facts. Return the Blob by its workspace-relative filename.")

  > keep_inventory_input (FormalizerInput, Inventory) ~> FormalizerInput:
    so((FormalizerInput, Inventory), FormalizerInput, input) do:
      pure(input[0])

  > formalize_inventory (FormalizerInput, Inventory) ~> Candidate:
    fan(keep_inventory_input, extract_items >>> formalize_items) >>> assemble

  > over_limit (FormalizerInput, Inventory) ~> FormalizerOutput:
    output_profile[(FormalizerInput, Inventory), FormalizerOutput](
      "The typed inventory is incomplete or exceeds its 8-item limit. Do not " &
      "pretend to formalize all requirements. Create formalization.typ as a " &
      "short Typst notice that a complete formalization was not produced. " &
      "Create formalization-audit.typ listing the supplied scope limit and " &
      "inventory gaps. Keep both files concise and return both as Blobs.")

  > choose_scope (FormalizerInput, Inventory) ~> FormalizerOutput:
    so((FormalizerInput, Inventory), FormalizerOutput, input) do:
      let (source, raw_inventory) = input
      let found = bounded_inventory(raw_inventory)
      if found.complete and found.items.len <= max_items:
        (source, found) >>> prepare_review >>> review_candidate >>> route_review
      else:
        (source, found) >>> over_limit

  > keep_formalizer_source (FormalizerInput, Inventory, Candidate) ~>
      FormalizerInput:
    so((FormalizerInput, Inventory, Candidate), FormalizerInput, input) do:
      pure(input[0])

  > prepare_review (FormalizerInput, Inventory) ~>
      (FormalizerInput, Inventory, Candidate):
    fan(keep_inventory_input, keep_inventory, formalize_inventory)

  > keep_inventory (FormalizerInput, Inventory) ~> Inventory:
    so((FormalizerInput, Inventory), Inventory, input) do:
      pure(input[1])

  > make_audit_input (FormalizerInput, Inventory, Candidate) ~> AuditInput:
    so((FormalizerInput, Inventory, Candidate), AuditInput, input) do:
      pure(AuditInput(inventory: input[1], candidate: input[2]))

  > keep_audit_context (FormalizerInput, Inventory, Candidate) ~>
      (FormalizerInput, AuditInput):
    fan(keep_formalizer_source, make_audit_input)

  > review_intention AuditInput ~> Review:
    intention_profile[AuditInput, Review](
      "Compare the Candidate only with Inventory items sourced from intention. " &
      "Report supported mismatches and open decisions. Return at most 4 " &
      "source-linked findings, each at most 240 characters, grouping related " &
      "issues. Use faRepair only when the inventory determines a compatible " &
      "correction; otherwise use faReport. Set complete=false if findings " &
      "cannot be represented without loss. Do not rewrite the candidate.")

  > review_rigor AuditInput ~> Review:
    rigor_profile[AuditInput, Review](
      "Check only formal rigor in Candidate against the supplied inventory: " &
      "definitions, assumptions, quantifiers, " &
      "notation, derivations, boundary cases, and intuition for large " &
      "equations. Return at most 4 source-linked findings, each at most 240 " &
      "characters, grouping related issues. Mark faRepair only for corrections " &
      "determined by the inventory; otherwise mark faReport and kind=fkGap. " &
      "Set complete=false if findings cannot be represented without loss. Do " &
      "not rewrite the candidate.")

  > review_typst AuditInput ~> Review:
    typst_profile[AuditInput, Review](
      "Check only that the candidate is a concise, standalone Typst source " &
      "file with the requested specification content. Identify obvious " &
      "unbalanced delimiters or malformed Typst constructs. Do not claim that " &
      "you compiled it. Return at most 4 findings, each at most 240 characters; " &
      "use faRepair only for a clear correction, and set complete=false if " &
      "findings were truncated.")

  > check_coverage (FormalizerInput, Inventory, Candidate) ~> Review:
    coverage_profile[(FormalizerInput, Inventory, Candidate), Review](
      "Compare all source files directly with the candidate and compact " &
      "inventory. Verify that each independently actionable requirement and " &
      "required change appears in the inventory and has an explicit clause " &
      "with traceability in the candidate. Do not trust inventory completeness " &
      "without checking the source. Return at most 4 source-linked findings, " &
      "each at most 240 characters, grouping related items. Use faRepair only " &
      "when the files determine the correction; otherwise faReport. Set " &
      "complete=false if findings cannot be represented without loss. Do not " &
      "rewrite the candidate.")

  > check_intention (FormalizerInput, Inventory, Candidate) ~> Review:
    make_audit_input >>> review_intention

  > check_rigor (FormalizerInput, Inventory, Candidate) ~> Review:
    make_audit_input >>> review_rigor

  > check_typst (FormalizerInput, Inventory, Candidate) ~> Review:
    make_audit_input >>> review_typst

  > merge_reviews ((FormalizerInput, AuditInput), Review, Review, Review, Review) ~>
      (FormalizerInput, ReviewState):
    so(((FormalizerInput, AuditInput), Review, Review, Review, Review),
        (FormalizerInput, ReviewState), input) do:
      let (context, coverage, intention, rigor, typst) = input
      let merged = merge_reviews((context, coverage, intention, rigor, typst))
      pure((context[0], merged))

  > review_candidate (FormalizerInput, Inventory, Candidate) ~>
      (FormalizerInput, ReviewState):
    fan(keep_audit_context, check_coverage, check_intention,
        check_rigor, check_typst) >>>
      merge_reviews

  > repair_candidate (FormalizerInput, ReviewState) ~> Candidate:
    repair_profile[(FormalizerInput, ReviewState), Candidate](
      "Repair the candidate only for faRepair findings. Re-read the supplied " &
      "proposal, required_changes, and intention. Do not follow faReport items " &
      "as requirements; preserve them for the audit. Make one bounded repair " &
      "pass, target at most 3000 words unless required for completeness, keep " &
      "the document standalone Typst, and add no external facts. Return " &
      "formalization.typ as a Blob.")

  > keep_review_input (FormalizerInput, ReviewState) ~> FormalizerInput:
    so((FormalizerInput, ReviewState), FormalizerInput, input) do:
      pure(input[0])

  > keep_review_inventory (FormalizerInput, ReviewState) ~> Inventory:
    so((FormalizerInput, ReviewState), Inventory, input) do:
      pure(input[1].inventory)

  > repair_and_review (FormalizerInput, ReviewState) ~> (FormalizerInput, ReviewState):
    fan(keep_review_input, keep_review_inventory, repair_candidate) >>>
      review_candidate

  > keep_formalization OutputInput ~> Blob:
    so(OutputInput, Blob, input) do:
      pure(input.state.candidate.formalization)

  > report_state OutputInput ~> ReviewState:
    so(OutputInput, ReviewState, input) do:
      pure(input.state)

  > write_audit ReviewState ~> Blob:
    output_profile[ReviewState, Blob](
      "Write only formalization-audit.typ as a standalone Typst document. " &
      "Use the compact inventory, final findings, and final candidate to list " &
      "supported intention mismatches, specification gaps, unresolved " &
      "required changes, and source-to-section traceability. If review_complete " &
      "is false, state that the bounded review may be incomplete. Distinguish " &
      "evidence from uncertainty. Say none identified only if no applicable " &
      "finding remains. Keep the audit under 1000 words. Add no requirements " &
      "or external facts. Return the file as a Blob.")

  > package_output (Blob, Blob) ~> FormalizerOutput:
    so((Blob, Blob), FormalizerOutput, input) do:
      let (formalization, audit) = input
      pure(FormalizerOutput(formalization: formalization, audit: audit))

  > write_outputs OutputInput ~> FormalizerOutput:
    fan(keep_formalization, report_state >>> write_audit) >>> package_output

  > normalize_output_input (FormalizerInput, ReviewState) ~> OutputInput:
    so((FormalizerInput, ReviewState), OutputInput, input) do:
      let (source, state) = input
      pure((source: source, state: state))

  > route_review (FormalizerInput, ReviewState) ~> FormalizerOutput:
    so((FormalizerInput, ReviewState), FormalizerOutput, input) do:
      let (source, state) = input
      if has_repair(state.findings):
        input >>> repair_and_review >>> normalize_output_input >>> write_outputs
      else:
        (source, state) >>> normalize_output_input >>> write_outputs

  > formalizer_entry FormalizerInput ~> FormalizerOutput {.entry.}:
    inspect_input >>> choose_scope

proc materialize_outputs(output: FormalizerOutput; output_dir: Path) =
  if not dirExists($output_dir):
    createDir($output_dir)
  let formalization_path = output_dir / Path("formalization.typ")
  let audit_path = output_dir / Path("formalization-audit.typ")
  for path in [formalization_path, audit_path]:
    if fileExists($path) or dirExists($path) or symlinkExists($path):
      raise newException(IOError, "output already exists: " & $path)
  materializeBlob(output.formalization, formalization_path)
  materializeBlob(output.audit, audit_path)

proc load_input(paths: array[3, string]): FormalizerInput =
  FormalizerInput(
    proposal: blobFromFile(Path(paths[0])),
    required_changes: blobFromFile(Path(paths[1])),
    intention: blobFromFile(Path(paths[2])))

proc usage(program: string) =
  quit("Usage:\n" &
    "  " & program & " PROPOSAL CHANGES INTENTION OUTPUT_DIR DATABASE_PATH\n" &
    "  " & program & " --resume DATABASE_PATH OUTPUT_DIR", 2)

when isMainModule:
  var output: FormalizerOutput
  var output_dir: Path
  if paramCount() == 3 and paramStr(1) == "--resume":
    let database_path = Path(paramStr(2))
    output_dir = Path(paramStr(3))
    echo "SQLite database: ", database_path
    output = resume_solve_formalizer(database_path, formalizer_prompts,
      finish_work_retry_limit = 4)
  elif paramCount() == 5:
    let source = load_input([paramStr(1), paramStr(2), paramStr(3)])
    output_dir = Path(paramStr(4))
    let database_path = Path(paramStr(5))
    let database_parent = parentDir($database_path)
    if database_parent.len > 0:
      createDir(database_parent)
    echo "SQLite database: ", database_path
    output = solve_formalizer(source, initial_budget,
      formalizer_prompts, database_path = database_path,
      finish_work_retry_limit = 4)
  else:
    usage(getAppFilename())

  materialize_outputs(output, output_dir)
  echo "Formalization: ", output_dir / Path("formalization.typ")
  echo "Audit: ", output_dir / Path("formalization-audit.typ")
