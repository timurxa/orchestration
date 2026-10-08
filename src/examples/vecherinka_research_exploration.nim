## Cost-bounded exploration from a research-direction Blob.
## Each analysis adds knowledge and candidate problems to one typed state.
## Solver batches consume only budget left after reserving another analysis
## and final synthesis; recursion ends when no further batch is affordable.
## Provide at least one medium call plus one high call in initial_budget so
## the initial proposal can be followed by the final synthesis.

{.experimental: "callOperator".}

import std/[os, paths, strutils]
import ../api/vecherinka

type
  ResearchProblem = object
    question: string
    why_it_matters: string

  ResearchAnswer = object
    question: string
    answer: string
    evidence: seq[string]
    uncertainty: seq[string]

  ExplorationState = object
    direction: Blob
    problems_proposed: seq[ResearchProblem]
    answers: seq[ResearchAnswer]
    knowledge_made: seq[string]

  Reanalysis = object
    knowledge_made: seq[string]
    next_problems: seq[ResearchProblem]

  ExplorationOutput = object
    problems_proposed: seq[ResearchProblem]
    answers: seq[ResearchAnswer]
    knowledge_made: seq[string]
    synthesis: string
    summary: string

const
  planner = luna.medium
  solver = luna.high
  planner_cost = profile_cost(luna, planner.effort)
  solver_cost = profile_cost(luna, solver.effort)

vecherinka(solve_research_exploration, default_agent_prompt_templates):
  > propose_problems Blob ~> seq[ResearchProblem]:
    planner[Blob, seq[ResearchProblem]](
      "Read the research exploration direction from the materialized input file. " &
      "Propose the distinct problems whose investigation would most improve " &
      "understanding of that direction. Order them by expected value. For each, " &
      "state a focused question and why it matters. Do not impose an arbitrary " &
      "problem count; do not answer the questions or create files.")

  > solve_problem ResearchProblem ~> ResearchAnswer:
    solver[ResearchProblem, ResearchAnswer](
      "Investigate this problem as carefully as possible. Give a direct answer, " &
      "concrete evidence or reasoning, and remaining uncertainty. Stay focused " &
      "on the assigned question. Do not create files.")

  > reanalyze ExplorationState ~> Reanalysis:
    planner[ExplorationState, Reanalysis](
      "Reanalyze the complete central exploration state: the original direction, " &
      "all proposed problems, prior answers, and knowledge made. Identify useful " &
      "new knowledge and propose the most interesting unresolved next problems, " &
      "ordered by value. Avoid repeating answered questions. Return no next " &
      "problems when further investigation would add little. Do not create files.")

  > synthesize ExplorationState ~> ExplorationOutput:
    solver[ExplorationState, ExplorationOutput](
      "Produce the final exploration record from the complete state. Copy all " &
      "proposed problems, answers, and knowledge made into their corresponding " &
      "fields. Give an overall synthesis of what the findings mean for the " &
      "original direction, and a concise summary of what was done. Preserve " &
      "uncertainty; do not invent research or create files.")

  > solve_batch (ExplorationState, seq[ResearchProblem]) ~>
      (ExplorationState, seq[ResearchAnswer]):
    lift((ExplorationState, seq[here]))[solve_problem]

  > record_answers (ExplorationState, seq[ResearchAnswer]) ~> ExplorationState:
    so((ExplorationState, seq[ResearchAnswer]), ExplorationState, input) do:
      var state = input[0]
      state.answers.add(input[1])
      pure(state)

  > continue_after_analysis (ExplorationState, Reanalysis) ~> ExplorationOutput:
    so_budget((ExplorationState, Reanalysis), ExplorationOutput, input, budget) do:
      var state = input[0]
      let analysis = input[1]
      state.knowledge_made.add(analysis.knowledge_made)
      state.problems_proposed.add(analysis.next_problems)

      let reserve = planner_cost + solver_cost
      let affordable = int(max(0.0, budget.global_remaining - reserve) / solver_cost)
      let batch_size = min(affordable, analysis.next_problems.len)
      if batch_size == 0:
        state >>> synthesize
      else:
        let batch = analysis.next_problems[0 ..< batch_size]
        (state, batch) >>> solve_batch >>> record_answers >>> explore

  > explore ExplorationState ~> ExplorationOutput:
    so_budget(ExplorationState, ExplorationOutput, state, budget) do:
      if budget.global_remaining < planner_cost + solver_cost:
        state >>> synthesize
      else:
        state >>> fan(it(ExplorationState), reanalyze) >>> continue_after_analysis

  > begin_exploration (Blob, seq[ResearchProblem]) ~> ExplorationOutput:
    so_budget((Blob, seq[ResearchProblem]), ExplorationOutput, input, budget) do:
      let state = ExplorationState(
        direction: input[0],
        problems_proposed: input[1])
      let reserve = planner_cost + solver_cost
      let affordable = int(max(0.0, budget.global_remaining - reserve) / solver_cost)
      let batch_size = min(affordable, input[1].len)
      if batch_size == 0:
        state >>> synthesize
      else:
        let batch = input[1][0 ..< batch_size]
        (state, batch) >>> solve_batch >>> record_answers >>> explore

  > exploration_entry Blob ~> ExplorationOutput {.entry.}:
    fan(it(Blob), propose_problems) >>> begin_exploration

if paramCount() != 2:
  quit("Usage: vecherinka_research_exploration DIRECTION_FILE COST_BUDGET", 2)

var cost_budget: float
try:
  cost_budget = parseFloat(paramStr(2))
except ValueError:
  quit("COST_BUDGET must be a number", 2)

let exploration = solve_research_exploration(
  blobFromFile(Path(paramStr(1))), cost_budget)

echo "PROBLEMS PROPOSED"
for problem in exploration.problems_proposed:
  echo "- ", problem.question, " — ", problem.why_it_matters

echo "\nANSWERS"
for answer in exploration.answers:
  echo "- ", answer.question, "\n  ", answer.answer
  for evidence in answer.evidence:
    echo "  Evidence: ", evidence
  for uncertainty in answer.uncertainty:
    echo "  Uncertainty: ", uncertainty

echo "\nKNOWLEDGE MADE"
for item in exploration.knowledge_made:
  echo "- ", item

echo "\nSYNTHESIS\n", exploration.synthesis
echo "\nSUMMARY\n", exploration.summary
