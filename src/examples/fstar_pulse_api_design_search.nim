## Bounded, resumable search for an F* workflow API design.
## Run from the repository root; see --help for the CLI.

{.experimental: "callOperator".}
import std/[math, os, paths, strutils]
import ../api/vecherinka

type
  EvidenceKind = enum
    evidenceDesign, evidenceAnalysis, evidenceImplementation,
    evidenceExecution, evidenceProof
  EvidenceState = enum
    evidenceGap, evidenceProposed, evidenceSupported, evidenceImplemented,
    evidenceExecuted, evidenceProved, evidenceRefuted
  WorkOutcome = enum
    workFailed, workUnfinished, workFinished
  Relation = enum
    relationDistinct, relationSameAs, relationUnclear
  IncomingKind = enum
    incomingCandidate, incomingDirection
  SearchStatus = enum
    searchCandidateComplete, searchIncomplete

  SearchInput = object
    problem: Blob
    sources: BlobTree
    beamWidth, explorationSlots, maxRounds, maxApproaches, maxFrontier: int
    maxCalls: int

  Criterion = object
    id, requirement: string
    required: bool
    evidence: EvidenceKind
  Frame = object
    scope: string
    criteria: seq[Criterion]
  Proposal = object
    mechanism, summary: string
    primitives: seq[string]
  Finding = object
    criterionId: string
    state: EvidenceState
    evidence: seq[string]
  Snapshot = object
    proposal: Proposal
    findings: seq[Finding]
    assumptions, blockers: seq[string]
  Development = object
    outcome: WorkOutcome
    snapshot: Snapshot
    nextTarget, newDirectionTarget, newDirection, failure: string
  DiscoveryInput = object
    problem: Blob
    frame: Frame
    slot: int
  Approach = object
    id: int
    snapshot: Snapshot
    outcome: WorkOutcome
    serviceCount: int
    done, provisional: bool
    pendingTarget, pendingDirection: string
  Direction = object
    id, parentId: int
    target, description: string
    snapshot: Snapshot
    unclear: bool
  WorkItem = object
    id, approachId, parentId: int
    target, direction: string
    snapshot: Snapshot
    isDirection: bool
  DevelopmentInput = object
    problem: Blob
    sources: BlobTree
    criteria: seq[Criterion]
    work: WorkItem
  Incoming = object
    id, parentId: int
    kind: IncomingKind
    developed: bool
    outcome: WorkOutcome
    target, description: string
    snapshot: Snapshot
  Transition = object
    id, parentId: int
    kind, target, direction, action, rationale: string
    outcome: WorkOutcome
  SearchState = object
    input: SearchInput
    frame: Frame
    approaches: seq[Approach]
    frontier: seq[Direction]
    transitions: seq[Transition]
    round, nextId, calls: int
    stopReason: string
  DedupSummary = object
    id, parentId: int
    kind: IncomingKind
    developed: bool
    outcome: WorkOutcome
    mechanism, summary, target, direction: string
    primitives: seq[string]
    findings: seq[Finding]
    assumptions, blockers: seq[string]
    serviceCount: int
    done, provisional: bool
    pendingTarget, pendingDirection: string
  DedupInput = object
    heads: seq[DedupSummary]
    incoming: seq[DedupSummary]
    approachLimit: int
  DedupDecision = object
    incomingId: int
    relation: Relation
    approachId: int
    keepIncoming: bool
    evictApproachId: int
    rationale: string
  DedupBatch = object
    state: SearchState
    incoming: seq[Incoming]
  SearchOutput = object
    status: SearchStatus
    stopReason: string
    scope: string
    criteria: seq[Criterion]
    approaches: seq[Approach]
    frontier: seq[Direction]
    transitions: seq[Transition]
    rounds, processorCalls: int

const
  frameProfile = luna.medium
  proposalProfile = luna.high
  developmentProfile = luna.high
  dedupeProfile = luna.low
  frameCost = profile_cost(luna, frameProfile.effort)
  proposalCost = profile_cost(luna, proposalProfile.effort)
  developmentCost = profile_cost(luna, developmentProfile.effort)
  dedupeCost = profile_cost(luna, dedupeProfile.effort)
  defaultBudget = 40.0
  contextFiles = [
    "src/docs/fstar_pulse_migration_proposal.md",
    "src/docs/fstar_pulse_migration_research_report.md",
    "src/docs/sqlite_artifact_storage_pivot.md",
    "src/docs/workflow_readiness_audit.md",
    "src/docs/vecherinka_dsl_guide.md",
    "src/docs/vecherinka_budgeting_spec.md",
    "src/examples/vecherinka_problem_kernel.nim",
    "src/examples/vecherinka_problem_kernel_proposal.md",
    "src/examples/fstar_pulse_api_design_search_proposal.md"]

proc bytesOf(value: string): seq[byte] =
  result = newSeq[byte](value.len)
  for i, c in value:
    result[i] = byte(c)

proc repositoryContext(root: Path): BlobTree =
  result.suggestedFilename = "fstar-workflow-design-context"
  for relative in contextFiles:
    let path = root / Path(relative)
    if not fileExists($path):
      raise newException(IOError, "required context file is missing: " & $path)
    result.entries.add(BlobTreeEntry(path: relative, kind: btekFile,
      bytes: bytesOf(readFile($path))))
  result = canonicalBlobTree(result)

proc findingFor(snapshot: Snapshot; criterionId: string): Finding =
  result.state = evidenceGap
  for finding in snapshot.findings:
    if finding.criterionId == criterionId:
      return finding

proc evidenceMatches(kind: EvidenceKind; state: EvidenceState): bool =
  case kind
  of evidenceDesign:
    state in {evidenceProposed, evidenceSupported, evidenceImplemented,
      evidenceExecuted, evidenceProved}
  of evidenceAnalysis:
    state in {evidenceSupported, evidenceImplemented, evidenceExecuted,
      evidenceProved}
  of evidenceImplementation:
    state in {evidenceImplemented, evidenceExecuted, evidenceProved}
  of evidenceExecution: state == evidenceExecuted
  of evidenceProof: state == evidenceProved

proc candidateCompleteReported(frame: Frame; snapshot: Snapshot): bool =
  if frame.criteria.len == 0:
    return false
  for criterion in frame.criteria:
    if criterion.required:
      let finding = findingFor(snapshot, criterion.id)
      if not evidenceMatches(criterion.evidence, finding.state) or
          finding.evidence.len == 0:
        return false
  true

proc approachIndex(state: SearchState; id: int): int =
  for i, item in state.approaches:
    if item.id == id:
      return i
  -1

proc auditTarget(): string =
  ## Do not infer a next target by ranking uncertain processor findings.
  "continue the source-grounded rubric audit"

proc fallbackDecision(state: SearchState; item: Incoming;
    reason: string): DedupDecision =
  ## Ambiguous reconciliation preserves work provisionally; old report IDs
  ## and malformed model references are not valid state transitions.
  result = DedupDecision(incomingId: item.id, relation: relationUnclear,
    keepIncoming: true, rationale: reason)
  if item.kind == incomingCandidate and
      state.approaches.len >= state.input.maxApproaches:
    var oldest = high(int)
    for head in state.approaches:
      if head.id < oldest: oldest = head.id
    if oldest < high(int): result.evictApproachId = oldest

proc decisionFor(state: SearchState; decisions: seq[DedupDecision];
    item: Incoming): DedupDecision =
  var matches = 0
  for decision in decisions:
    if decision.incomingId == item.id:
      inc matches
      result = decision
  if matches != 1:
    return fallbackDecision(state, item,
      if matches == 0: "missing decision; retained provisionally" else:
        "duplicate decisions; retained provisionally")
  if result.relation == relationSameAs and
      state.approachIndex(result.approachId) < 0:
    return fallbackDecision(state, item,
      "SameAs ID is not a live head in this run; retained provisionally")
  let parentIsLive = item.parentId > 0 and
    state.approachIndex(item.parentId) >= 0
  let addsHead = item.kind == incomingCandidate and result.keepIncoming and
    result.relation != relationSameAs and
    (result.relation == relationDistinct or not parentIsLive)
  if addsHead and state.approaches.len >= state.input.maxApproaches and
      state.approachIndex(result.evictApproachId) < 0:
    return fallbackDecision(state, item,
      "invalid eviction ID; retained provisionally using oldest live head")

proc logRecord(state: var SearchState; item: Incoming; action, rationale: string) =
  state.transitions.add(Transition(id: item.id, parentId: item.parentId,
    kind: $item.kind, target: item.target, direction: item.description,
    action: action, rationale: rationale, outcome: item.outcome))

proc addApproach(state: var SearchState; item: Incoming; provisional: bool;
    evictId: int): bool =
  let done = (provisional and item.developed) or
    (item.outcome == workFinished and item.target.len == 0)
  let target = if provisional and not done:
      "one bounded distinctness trial"
    elif item.target.len > 0: item.target
    else: auditTarget()
  if state.approaches.len < state.input.maxApproaches:
    state.approaches.add(Approach(id: item.id, snapshot: item.snapshot,
      outcome: item.outcome, done: done, provisional: provisional,
      pendingTarget: target,
      pendingDirection: item.description))
    return true
  let worst = state.approachIndex(evictId)
  if worst < 0 or evictId == item.id:
    return false
  let evicted = state.approaches[worst]
  state.logRecord(Incoming(id: evicted.id, kind: incomingCandidate,
    outcome: evicted.outcome, snapshot: evicted.snapshot), "evicted",
    "selected by batch reconciler at approach cap")
  state.approaches.delete(worst)
  state.approaches.add(Approach(id: item.id, snapshot: item.snapshot,
    outcome: item.outcome, done: done, provisional: provisional,
    pendingTarget: target, pendingDirection: item.description))
  true

proc addDirection(state: var SearchState; item: Incoming; unclear: bool) =
  state.frontier.add(Direction(id: item.id, parentId: item.parentId,
    target: item.target, description: item.description,
    snapshot: item.snapshot, unclear: unclear))
  while state.frontier.len > state.input.maxFrontier:
    let worst = state.frontier.high
    let dropped = state.frontier[worst]
    state.frontier.delete(worst)
    state.logRecord(Incoming(id: dropped.id, parentId: dropped.parentId,
      kind: incomingDirection, outcome: workUnfinished, target: dropped.target,
      description: dropped.description, snapshot: dropped.snapshot),
      "pruned", "frontier cap; older allocation IDs are retained")

proc applyDecision(state: var SearchState; item: Incoming;
    decision: DedupDecision) =
  var safeDecision = decision
  if safeDecision.relation == relationSameAs and
      state.approachIndex(safeDecision.approachId) < 0:
    safeDecision = fallbackDecision(state, item,
      "SameAs ID is not a live head in this run; retained provisionally")
  let relation = safeDecision.relation
  let targetId = safeDecision.approachId
  let index = state.approachIndex(targetId)
  case item.kind
  of incomingDirection:
    case relation
    of relationDistinct:
      if safeDecision.keepIncoming:
        state.addDirection(item, false)
        state.logRecord(item, "frontier", safeDecision.rationale)
      else:
        state.logRecord(item, "excluded", safeDecision.rationale)
    of relationSameAs:
      if safeDecision.keepIncoming:
        state.approaches[index].done = false
        state.approaches[index].pendingTarget = item.target
        state.approaches[index].pendingDirection = item.description
        state.logRecord(item, "same-approach target", safeDecision.rationale)
      else:
        state.logRecord(item, "excluded", safeDecision.rationale)
    of relationUnclear:
      if safeDecision.keepIncoming:
        state.addDirection(item, true)
        state.logRecord(item, "unclear frontier", safeDecision.rationale)
      else:
        state.logRecord(item, "excluded", safeDecision.rationale)
  of incomingCandidate:
    if item.parentId > 0 and state.approachIndex(item.parentId) >= 0:
      let own = state.approachIndex(item.parentId)
      if relation == relationDistinct:
        state.approaches[own].serviceCount.inc
        let accepted = safeDecision.keepIncoming and state.addApproach(item,
          false, safeDecision.evictApproachId)
        # This target was already developed; do not spend another round on
        # the same parent snapshot after forking or rejecting its result.
        state.approaches[own].pendingTarget = auditTarget()
        state.approaches[own].pendingDirection = ""
        state.approaches[own].done = false
        state.logRecord(item, if accepted: "forked approach" else: "excluded",
          if accepted: safeDecision.rationale else:
            "not retained or no valid eviction at approach cap")
      elif relation == relationSameAs and targetId != item.parentId:
        if safeDecision.keepIncoming:
          state.approaches[index].snapshot = item.snapshot
          state.approaches[index].outcome = item.outcome
        state.approaches[index].serviceCount.inc
        state.approaches.delete(own)
        state.logRecord(item, "merged", safeDecision.rationale)
      else:
        if safeDecision.keepIncoming:
          state.approaches[own].snapshot = item.snapshot
          state.approaches[own].outcome = item.outcome
        state.approaches[own].serviceCount.inc
        state.approaches[own].provisional =
          state.approaches[own].provisional and relation == relationUnclear
        if state.approaches[own].provisional:
          state.approaches[own].pendingTarget = "distinctness remains unclear"
          state.approaches[own].done = true
        elif safeDecision.keepIncoming:
          state.approaches[own].pendingTarget =
            if item.target.len > 0: item.target else: auditTarget()
          state.approaches[own].pendingDirection = item.description
          state.approaches[own].done = item.outcome == workFinished and
            item.target.len == 0
        else:
          # A rejected replacement still consumes the assigned stage.
          state.approaches[own].done = true
        state.logRecord(item, "updated incumbent", safeDecision.rationale)
    elif relation == relationSameAs:
      if safeDecision.keepIncoming:
        state.approaches[index].snapshot = item.snapshot
        state.approaches[index].outcome = item.outcome
      if item.developed:
        state.approaches[index].serviceCount.inc
        if safeDecision.keepIncoming:
          state.approaches[index].pendingTarget = if item.target.len > 0:
            item.target else: auditTarget()
          state.approaches[index].pendingDirection = item.description
          state.approaches[index].done = item.outcome == workFinished and
            item.target.len == 0
      state.logRecord(item, "merged", safeDecision.rationale)
    elif safeDecision.keepIncoming:
      let accepted = state.addApproach(item, relation == relationUnclear,
        safeDecision.evictApproachId)
      state.logRecord(item, if not accepted: "excluded"
        elif relation == relationDistinct: "retained" else: "provisional",
        if not accepted: "no valid eviction at approach cap" else:
          safeDecision.rationale)
    else:
      state.logRecord(item, "excluded", safeDecision.rationale)

proc dedupInput(batch: DedupBatch): DedupInput =
  result.approachLimit = batch.state.input.maxApproaches
  for head in batch.state.approaches:
    result.heads.add(DedupSummary(id: head.id,
      outcome: head.outcome,
      mechanism: head.snapshot.proposal.mechanism,
      summary: head.snapshot.proposal.summary,
      primitives: head.snapshot.proposal.primitives,
      findings: head.snapshot.findings,
      assumptions: head.snapshot.assumptions, blockers: head.snapshot.blockers,
      serviceCount: head.serviceCount, done: head.done,
      provisional: head.provisional, pendingTarget: head.pendingTarget,
      pendingDirection: head.pendingDirection))
  for item in batch.incoming:
    result.incoming.add(DedupSummary(id: item.id,
      parentId: item.parentId, kind: item.kind, developed: item.developed,
      outcome: item.outcome,
      mechanism: item.snapshot.proposal.mechanism,
      summary: item.snapshot.proposal.summary, target: item.target,
      direction: item.description,
      primitives: item.snapshot.proposal.primitives,
      findings: item.snapshot.findings,
      assumptions: item.snapshot.assumptions, blockers: item.snapshot.blockers))

proc hasEligibleWork(state: SearchState): bool =
  if state.frontier.len > 0:
    return true
  for approach in state.approaches:
    if not approach.done:
      return true

proc chooseWork(state: var SearchState; count: int): seq[WorkItem] =
  var chosenFrontier = newSeq[bool](state.frontier.len)
  var chosenApproaches = newSeq[bool](state.approaches.len)
  let reserve = min(state.input.explorationSlots, count)
  for i in 0 ..< min(reserve, state.frontier.len):
    chosenFrontier[i] = true
    let direction = state.frontier[i]
    result.add(WorkItem(id: state.nextId, parentId: direction.parentId,
      target: direction.target, direction: direction.description,
      snapshot: direction.snapshot, isDirection: true))
    inc state.nextId
  while result.len < count:
    var best = -1
    for i, approach in state.approaches:
      if chosenApproaches[i] or approach.done:
        continue
      if best < 0 or approach.serviceCount < state.approaches[best].serviceCount or
          (approach.serviceCount == state.approaches[best].serviceCount and
           approach.id < state.approaches[best].id):
        best = i
    if best < 0: break
    chosenApproaches[best] = true
    let approach = state.approaches[best]
    result.add(WorkItem(id: state.nextId, approachId: approach.id,
      parentId: approach.id, target: approach.pendingTarget,
      direction: approach.pendingDirection, snapshot: approach.snapshot))
    inc state.nextId
  for i, direction in state.frontier:
    if result.len >= count: break
    if chosenFrontier[i]: continue
    chosenFrontier[i] = true
    result.add(WorkItem(id: state.nextId, parentId: direction.parentId,
      target: direction.target, direction: direction.description,
      snapshot: direction.snapshot, isDirection: true))
    inc state.nextId
  var remaining: seq[Direction]
  for i, direction in state.frontier:
    if not chosenFrontier[i]: remaining.add(direction)
  state.frontier = remaining

proc makeOutput(state: SearchState; reason: string): SearchOutput =
  result.status = searchIncomplete
  result.stopReason = reason
  result.scope = state.frame.scope
  result.criteria = state.frame.criteria
  result.approaches = state.approaches
  result.frontier = state.frontier
  result.transitions = state.transitions
  result.rounds = state.round
  result.processorCalls = state.calls
  for approach in state.approaches:
    if candidateCompleteReported(state.frame, approach.snapshot):
      result.status = searchCandidateComplete
      break

proc absoluteArgument(value, name: string): Path =
  if not isAbsolute(value):
    quit(name & " must be an absolute path: " & value, 2)
  Path(absolutePath(value))

proc parsePositive(value, name: string): int =
  try: result = parseInt(value)
  except ValueError: quit(name & " must be a positive integer", 2)
  if result < 1: quit(name & " must be a positive integer", 2)

proc parseBudget(value: string): float =
  try: result = parseFloat(value)
  except ValueError: quit("--budget must be a finite positive number", 2)
  if classify(result) in {fcNan, fcInf, fcNegInf} or result <= 0:
    quit("--budget must be a finite positive number", 2)

proc requireNew(path: Path) =
  if fileExists($path) or dirExists($path) or symlinkExists($path):
    raise newException(IOError, "output already exists: " & $path)

proc render(output: SearchOutput): string =
  let status = if output.status == searchCandidateComplete:
      "candidate-complete (processor-reported)" else: "incomplete"
  result = "# F* workflow API design search\n\nStatus: **" & status &
    "**\n\nStop reason: " & output.stopReason & "\n" &
    "Rounds: " & $output.rounds & "\nProcessor calls: " &
    $output.processorCalls & "\n\n"
  result.add output.scope & "\n\n"
  result.add "## Rubric\n\n"
  for criterion in output.criteria:
    result.add "- `" & criterion.id & "` (" & $criterion.evidence & "): " &
      criterion.requirement & (if criterion.required: " [required]" else: "") & "\n"
  result.add "\n## Retained approaches\n"
  for approach in output.approaches:
    result.add "\n### Approach " & $approach.id &
      (if approach.provisional: " (provisional)" else: "") & "\n\n" &
      approach.snapshot.proposal.mechanism & "\n\n" &
      approach.snapshot.proposal.summary & "\n\n"
    result.add "Primitive inventory: " &
      (if approach.snapshot.proposal.primitives.len == 0: "none stated" else:
       approach.snapshot.proposal.primitives.join(", ")) & "\n\n"
    for assumption in approach.snapshot.assumptions:
      result.add "- Assumption: " & assumption & "\n"
    for finding in approach.snapshot.findings:
      result.add "- `" & finding.criterionId & "`: **" & $finding.state &
        "** — " & finding.evidence.join("; ") & "\n"
    for blocker in approach.snapshot.blockers:
      result.add "- Blocker: " & blocker & "\n"
  result.add "\n## Remaining directions\n\n"
  if output.frontier.len == 0: result.add "None\n"
  for direction in output.frontier:
    result.add "- #" & $direction.id & " from approach #" &
      $direction.parentId & ": " & direction.target & " — " &
      direction.description & (if direction.unclear: " [unclear]" else: "") & "\n"
  result.add "\n## Search transitions\n\n"
  for record in output.transitions:
    result.add "- #" & $record.id & " " & record.kind & " " &
      $record.outcome & " " & record.action &
      (if record.target.len > 0: " (" & record.target & ")" else: "") &
      (if record.direction.len > 0: " — " & record.direction else: "") &
      (if record.rationale.len > 0: ": " & record.rationale else: "") & "\n"
  result.add "\nThe SQLite ledger retains full processor inputs and results. Evidence " &
    "states are processor assessments. A required proof or execution " &
    "claim is complete only when its linked artifact has been independently checked. " &
    "For identical saved processor outputs, configuration, code, and budget " &
    "snapshots, allocation and reduction are deterministic; model outputs may vary.\n"

proc writeNew(path: Path; contents: string) =
  requireNew(path)
  let parent = parentDir($path)
  if parent.len > 0: createDir(parent)
  let temporary = Path($path & ".tmp")
  requireNew(temporary)
  writeFile($temporary, contents)
  moveFile($temporary, $path)

proc usageText(program: string): string =
  "Usage:\n  " & program & " SPEC.md OUTPUT.md DATABASE.sqlite3" &
    " [--budget USD] [--beam N] [--exploration N] [--rounds N]" &
    " [--approaches N] [--frontier N]\n  " & program &
    " --resume DATABASE.sqlite3 OUTPUT.md\n\n" &
    "Run from the repository root. Pass the F* problem specification as SPEC.md. " &
    "The CLI supplies pre-pivot research as historical evidence and workflow " &
    "examples. " &
    "Paths must be absolute; new-run output and database paths must not exist.\n" &
    "Defaults: budget 40, beam 3, exploration slots 1, rounds 3, " &
    "approaches 6, frontier 12. Budget is a scheduler estimate; the hard " &
    "processor-call cap excludes protocol follow-up turns."

proc usage(program: string) = quit(usageText(program), 2)
proc help(program: string) =
  echo usageText(program)
  quit(0)

vecherinka(solve_fstar_pulse_api_design_search, default_agent_prompt_templates):
  > frame Blob ~> Frame:
      frameProfile[Blob, Frame](
      "Treat the supplied problem specification as authoritative. When it " &
      "contains labeled prior-search context, use only the authoritative " &
      "specification for requirements; prior reports are unverified evidence, " &
      "not new obligations. Cross-check all spec sections. Extract a concise " &
      "rubric for an ordinary-F* workflow API and runtime, normally " &
      "extracted to OCaml. Preserve the full F* language inside and outside " &
      "so, dynamic expansion, durable continuation, generic backend " &
      "substitution, artifact/I/O-state evaluation, proofs, and the " &
      "deterministic extracted-code runner. Do not add Pulse, KaRaMeL, or " &
      "provider-specific model-state requirements from historical sources. " &
      "Return one criterion per obligation in spec order, with evidence kind " &
      "and requiredness. This is a rubric, not an API proposal.")

  > discovery_inputs (SearchInput, Frame) ~> seq[DiscoveryInput]:
    so((SearchInput, Frame), seq[DiscoveryInput], input) do:
      var items: seq[DiscoveryInput]
      for slot in 1 .. input[0].beamWidth:
        items.add(DiscoveryInput(problem: input[0].problem,
          frame: input[1], slot: slot))
      pure(items)

  > propose DiscoveryInput ~> Development:
      proposalProfile[DiscoveryInput, Development](
      "Independently propose one materially distinct ordinary-F* API approach " &
      "to the problem and rubric. If prior search results appear in the input, " &
      "treat them as unverified context that may inspire or be improved, not " &
      "as active search state or proof; recheck cited artifacts before relying " &
      "on them. " &
      "Target normal F* extraction, preferably " &
      "to OCaml; do not require Pulse, KaRaMeL, or an LLM/provider client. Do " &
      "not see other proposals or invent fixed candidate labels. Return a complete initial snapshot, explicit " &
      "assumptions and blockers, one finding for every criterion ID, and a " &
      "concrete next target. Use workUnfinished. The slot number is only a " &
      "replicate ID; choose independently. Do not claim proof or execution " &
      "without an exact checked artifact.")

  > proposal_batch (SearchInput, Frame) ~>
      ((SearchInput, Frame), seq[Development]):
    fan(it((SearchInput, Frame)),
      discovery_inputs >>> lift(seq[here])[propose])

  > normalize_frame (SearchInput, Frame) ~> (SearchInput, Frame):
    so((SearchInput, Frame), (SearchInput, Frame), input) do:
      var frame = input[1]
      if frame.criteria.len == 0:
        raise newException(ValueError, "framing returned an empty rubric")
      for i in 0 ..< frame.criteria.len:
        frame.criteria[i].id = "C" & $(i + 1)
      pure((input[0], frame))

  > prepare_bootstrap ((SearchInput, Frame), seq[Development]) ~> DedupBatch:
    so(((SearchInput, Frame), seq[Development]), DedupBatch, input) do:
      let (sourceAndFrame, results) = input
      var state = SearchState(input: sourceAndFrame[0], frame: sourceAndFrame[1],
        nextId: results.len + 1, calls: results.len + 2)
      var incoming: seq[Incoming]
      for i, result in results:
        state.transitions.add(Transition(id: i + 1, kind: "proposal",
          action: "discovered", outcome: result.outcome,
          rationale: result.failure))
        if result.outcome != workFailed:
          incoming.add(Incoming(id: i + 1, kind: incomingCandidate,
            outcome: result.outcome, target: result.nextTarget,
            snapshot: result.snapshot))
          if result.newDirection.len > 0:
            incoming.add(Incoming(id: state.nextId, parentId: i + 1,
              kind: incomingDirection, outcome: result.outcome,
              target: result.newDirectionTarget,
              description: result.newDirection, snapshot: result.snapshot))
            inc state.nextId
      pure(DedupBatch(state: state, incoming: incoming))

  > dedupe DedupInput ~> seq[DedupDecision]:
      dedupeProfile[DedupInput, seq[DedupDecision]](
      "Reconcile this batch from its full typed summaries. IDs in problem " &
      "text or prior reports are stale: use only IDs in these structured " &
      "lists. Return exactly one decision per incoming ID; SameAs may refer " &
      "only to a current head or an earlier accepted incoming candidate, and " &
      "eviction only to a current head. At bootstrap, no SameAs target exists " &
      "until a candidate has been accepted. If uncertain, use relationUnclear " &
      "with keepIncoming=true; unclear work gets one bounded trial. Compare " &
      "findings, assumptions, blockers, outcomes, and mechanisms; do not use " &
      "a local score or invent canonical labels. SameAs merges a candidate " &
      "into that head or makes a direction its pending target. keepIncoming " &
      "controls retention/replacement. Choose a live eviction ID only when " &
      "a new head needs a slot. Include a short rationale per decision.")

  > make_dedup_input DedupBatch ~> DedupInput:
    so(DedupBatch, DedupInput, input) do:
      pure(dedupInput(input))

  > seed (DedupBatch, seq[DedupDecision]) ~> SearchState:
    so((DedupBatch, seq[DedupDecision]), SearchState, input) do:
      var state = input[0].state
      for item in input[0].incoming:
        var decision = decisionFor(state, input[1], item)
        # Bootstrap must not become an empty search due to a bad merge choice.
        if state.approaches.len == 0 and state.frontier.len == 0 and
            item.kind == incomingCandidate and not decision.keepIncoming:
          decision = fallbackDecision(state, item,
            "bootstrap would be empty; retained provisional candidate")
        state.applyDecision(item, decision)
      pure(state)

  > development_inputs (SearchState, seq[WorkItem]) ~> seq[DevelopmentInput]:
    so((SearchState, seq[WorkItem]), seq[DevelopmentInput], input) do:
      var items: seq[DevelopmentInput]
      for work in input[1]:
        items.add(DevelopmentInput(problem: input[0].input.problem,
          sources: input[0].input.sources, criteria: input[0].frame.criteria,
          work: work))
      pure(items)

  > develop DevelopmentInput ~> Development:
    developmentProfile[DevelopmentInput, Development](
      "Develop the assigned approach or direction against the full problem " &
      "and supplied repository sources. Return a COMPLETE replacement " &
      "snapshot. Treat prior reports and their run-local IDs as history; do " &
      "not treat old paths or evidence claims as current unless you can reopen " &
      "and verify them. " &
      "Preserve unresolved requirements and cite " &
      "source paths or checked proof/run artifacts in finding evidence; " &
      "return one finding per criterion. On failure, keep the last valid " &
      "snapshot. Audit the rubric against the repository sources and flag " &
      "any omitted obligation as a blocker. Use workFailed, workUnfinished, " &
      "or workFinished honestly; " &
      "unfinished results need a concrete nextTarget, while finished stages " &
      "may name an improvement target. Suggest at most one materially " &
      "different new direction. `isDirection` means grow from that direction; " &
      "otherwise improve the identified approach. Code and proof claims need " &
      "concrete artifacts. The goal is an implemented, proved ordinary-F* API " &
      "and runnable deterministic debug runner using actual extracted F* " &
      "workflow code, with generic scripted adapters and no Pulse, KaRaMeL, " &
      "LLM service, Codex, JEV, or network dependency in that target runner. " &
      "Do not add provider-specific model-state management or restrict or " &
      "reinterpret `so` callbacks. " &
      "Do not call prose or model agreement a proof.")

  > run_development (SearchState, seq[WorkItem]) ~>
      ((SearchState, seq[WorkItem]), seq[Development]):
    fan(it((SearchState, seq[WorkItem])),
      development_inputs >>> lift(seq[here])[develop])

  > prepare_dedup ((SearchState, seq[WorkItem]), seq[Development]) ~> DedupBatch:
    so(((SearchState, seq[WorkItem]), seq[Development]), DedupBatch, input) do:
      let (stateAndWork, results) = input
      var state = stateAndWork[0]
      var incoming: seq[Incoming]
      for i, result in results:
        let work = stateAndWork[1][i]
        state.transitions.add(Transition(id: work.id,
          parentId: if work.isDirection: work.parentId else: work.approachId,
          kind: if work.isDirection: "direction development" else: "development",
          target: work.target, action: "completed", outcome: result.outcome,
          rationale: result.failure))
        if result.outcome != workFailed:
          incoming.add(Incoming(id: work.id,
            parentId: if work.isDirection: 0 else: work.approachId,
            kind: incomingCandidate, developed: true, outcome: result.outcome,
            target: result.nextTarget,
            snapshot: result.snapshot))
          if result.newDirection.len > 0:
            incoming.add(Incoming(id: state.nextId,
              parentId: if work.isDirection: work.parentId else: work.approachId,
              kind: incomingDirection, target: result.newDirectionTarget,
              outcome: result.outcome,
              description: result.newDirection, snapshot: result.snapshot))
            inc state.nextId
        elif not work.isDirection:
          let index = state.approachIndex(work.approachId)
          if index >= 0:
            state.approaches[index].done = true
            state.approaches[index].serviceCount.inc
      state.round.inc
      state.calls += results.len + 1
      pure(DedupBatch(state: state, incoming: incoming))

  > commit (DedupBatch, seq[DedupDecision]) ~> SearchState:
    so((DedupBatch, seq[DedupDecision]), SearchState, input) do:
      var state = input[0].state
      for item in input[0].incoming:
        state.applyDecision(item, decisionFor(state, input[1], item))
      pure(state)

  > finish SearchState ~> SearchOutput:
    so(SearchState, SearchOutput, state) do:
      let reason = if state.stopReason.len > 0: state.stopReason else: "search stopped"
      pure(makeOutput(state, reason))

  > route SearchState ~> SearchOutput:
    so_budget(SearchState, SearchOutput, state, budget) do:
      var next = state
      let availableCalls = state.input.maxCalls - state.calls - 1
      let affordable = int(max(0.0, budget.global_remaining - dedupeCost) /
        developmentCost)
      let count = min(state.input.beamWidth, min(availableCalls, affordable))
      if state.round >= state.input.maxRounds:
        next.stopReason = "round limit"
        next >>> finish
      elif availableCalls < 1:
        next.stopReason = "processor-call limit"
        next >>> finish
      elif budget.global_remaining < developmentCost + dedupeCost:
        next.stopReason = "budget reserve for development and deduplication"
        next >>> finish
      elif not state.hasEligibleWork:
        next.stopReason = "no eligible work"
        next >>> finish
      elif count < 1:
        next.stopReason = "no affordable work batch"
        next >>> finish
      else:
        let works = next.chooseWork(count)
        if works.len == 0:
          next.stopReason = "no eligible work"
          next >>> finish
        else:
          (next, works) >>> run_development >>> prepare_dedup >>>
            fan(it(DedupBatch), make_dedup_input >>> dedupe) >>> commit >>> route

  > search_entry SearchInput ~> SearchOutput {.entry.}:
    fan(it(SearchInput), it(SearchInput)[problem] >>> frame) >>> normalize_frame >>>
      proposal_batch >>> prepare_bootstrap >>>
      fan(it(DedupBatch), make_dedup_input >>> dedupe) >>> seed >>> route

proc runCli() =
  var positional: seq[string]
  var budget = defaultBudget
  var beam = 3
  var exploration = 1
  var rounds = 3
  var approaches = 6
  var frontier = 12
  var overridden = false
  var i = 1
  while i <= paramCount():
    let arg = paramStr(i)
    if arg in ["--budget", "--beam", "--exploration", "--rounds",
        "--approaches", "--frontier"]:
      inc i
      if i > paramCount(): quit(arg & " requires a value", 2)
      let value = paramStr(i)
      overridden = true
      case arg
      of "--budget": budget = parseBudget(value)
      of "--beam": beam = parsePositive(value, arg)
      of "--exploration": exploration = parsePositive(value, arg)
      of "--rounds": rounds = parsePositive(value, arg)
      of "--approaches": approaches = parsePositive(value, arg)
      of "--frontier": frontier = parsePositive(value, arg)
      else: discard
    elif arg.startsWith("--") and arg != "--resume":
      quit("unknown option: " & arg, 2)
    else:
      positional.add(arg)
    inc i
  if positional.len == 3 and positional[0] == "--resume":
    if overridden: quit("search limits and budget are saved; omit overrides on resume", 2)
    let database = absoluteArgument(positional[1], "DATABASE_PATH")
    let destination = absoluteArgument(positional[2], "OUTPUT_PATH")
    requireNew(destination)
    let output = resume_solve_fstar_pulse_api_design_search(database,
      default_agent_prompt_templates, finish_work_retry_limit = 1)
    writeNew(destination, render(output))
    return
  if positional.len != 3 or positional[0] == "--resume": usage(getAppFilename())
  if beam < 2 or exploration >= beam:
    quit("--beam must be at least 2 and --exploration must be smaller than --beam", 2)
  if approaches < 2:
    quit("--approaches must be at least 2", 2)
  if beam > high(int) - 2 or
      rounds > (high(int) - beam - 2) div (beam + 1):
    quit("--beam and --rounds produce an unsupported processor-call bound", 2)
  let problem = absoluteArgument(positional[0], "SPEC_PATH")
  let destination = absoluteArgument(positional[1], "OUTPUT_PATH")
  let database = absoluteArgument(positional[2], "DATABASE_PATH")
  requireNew(destination)
  if $destination == $database: quit("OUTPUT_PATH and DATABASE_PATH must differ", 2)
  if fileExists($database) or dirExists($database) or symlinkExists($database):
    quit("DATABASE_PATH already exists; use a new path or --resume", 2)
  let root = Path(absolutePath(os.getCurrentDir()))
  if not fileExists($(root / Path("src/docs/fstar_pulse_migration_proposal.md"))):
    quit("run this CLI from the repository root", 2)
  let maxCalls = beam + 2 + rounds * (beam + 1)
  let minimumBudget = frameCost + float(beam) * proposalCost + dedupeCost
  if budget < minimumBudget:
    quit("--budget must cover framing, independent proposals, and initial deduplication (at least " &
      $minimumBudget & ")", 2)
  let input = SearchInput(problem: blobFromFile(problem),
    sources: repositoryContext(root), beamWidth: beam,
    explorationSlots: exploration, maxRounds: rounds,
    maxApproaches: approaches, maxFrontier: frontier, maxCalls: maxCalls)
  let dbParent = parentDir($database)
  if dbParent.len > 0: createDir(dbParent)
  let output = solve_fstar_pulse_api_design_search(input, budget,
    default_agent_prompt_templates, database_path = database,
    finish_work_retry_limit = 1)
  writeNew(destination, render(output))

when isMainModule:
  if paramCount() == 1 and paramStr(1) in ["--help", "-h"]:
    help(getAppFilename())
  runCli()
