## Typed parallel research pipeline:
## request -> distinct research topics -> parallel findings -> synthesis.

import vecherinka

type
  InformationRequest = object
    question: string
    decision_context: string

  ResearchTopic = object
    title: string
    focused_question: string

  ResearchPlan = object
    request: InformationRequest
    topics: seq[ResearchTopic]

  ResearchFinding = object
    topic: string
    summary: string
    evidence: seq[string]
    sources: seq[string]
    caveats: seq[string]

  FinalReport = object
    recommendation: string
    rationale: seq[string]
    sources: seq[string]
    caveats: seq[string]

const research_profile = "gpt-5.6-luna".medium

vecherinka(solve_parallel_research):
  > make_plan InformationRequest ~> ResearchPlan:
    research_profile[InformationRequest, ResearchPlan](
      "Copy the original request into the request field. Turn it into exactly four distinct, non-overlapping research topics. " &
      "Give each topic a concise title and focused question. Cover different decision dimensions " &
      "such as technical design, operations, alternatives, and migration or cost. Do not answer " &
      "the request yet. Do not create files.")

  > research_topic ResearchTopic ~> ResearchFinding:
    research_profile[ResearchTopic, ResearchFinding](
      "Research the assigned topic independently. Use current, authoritative sources when possible. " &
      "Return a concise summary, concrete evidence, source URLs, and caveats. Keep findings focused " &
      "on the assigned topic so a later synthesizer can combine distinct results. Do not create files.")

  > prepare_research ResearchPlan ~> (InformationRequest, seq[ResearchTopic]):
    so(ResearchPlan, (InformationRequest, seq[ResearchTopic]), input) do:
      pure((input.request, input.topics))

  > synthesize (InformationRequest, seq[ResearchFinding]) ~> FinalReport:
    research_profile[(InformationRequest, seq[ResearchFinding]), FinalReport](
      "Synthesize the research findings into a decision-ready final report for the original request. " &
      "Reconcile disagreements, distinguish evidence from judgment, give a clear recommendation, " &
      "list supporting rationale, include source URLs, and state meaningful caveats. Do not create files.")

  > research_entry InformationRequest ~> FinalReport {.entry.}:
    make_plan >>> prepare_research >>>
      lift((InformationRequest, seq[here]))[research_topic] >>> synthesize

let request = InformationRequest(
  question: "How should a small engineering team choose between SQLite, PostgreSQL, and DuckDB for a local-first analytics product in 2026?",
  decision_context: "Compare concurrency, deployment and operational burden, analytical capability, cloud migration, ecosystem maturity, and total cost. Recommend a default and explain when the alternatives win.")

let log_file = new_log_file_sink("parallel-research.jsonl")
let logger = new_structured_logger(log_file.sink, run_id = "parallel-research")
try:
  let report = solve_parallel_research(request, logger = logger)
  echo "RECOMMENDATION: ", report.recommendation
  for rationale in report.rationale:
    echo "RATIONALE: ", rationale
  for source in report.sources:
    echo "SOURCE: ", source
  for caveat in report.caveats:
    echo "CAVEAT: ", caveat
finally:
  log_file.close()
