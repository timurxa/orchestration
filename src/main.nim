import std/[json, streams, paths, strutils]
import parsetoml
import results
import schematic
import codex_json
import codex_runtime
import artifact
import orchestration_api

# type DrainArg = object
#   stream: Stream
#
# proc drain_stderr(arg: DrainArg) {.thread.} =
#   var line: string
#   while arg.stream.readLine(line):
#     discard
#
# proc main() =
#   let runtime = init_codex_runtime(getCurrentDir())
#   let output = runtime.server_stdout_stream()
#   var stderr_reader: Thread[DrainArg]
#   stderr_reader.createThread(drain_stderr, DrainArg(stream: runtime.server_stderr_stream()))
#
#   var line: string
#   while output.readLine(line):
#     discard runtime.accept_json(parseJson(line))
#
#   stop_codex_runtime(runtime)
#   stderr_reader.joinThread()
#   runtime.deinit_codex_runtime()
#
# main()

# type
#   Compute = float
#   ProgramState = object
#     cwd: string
#     runtime: ptr CodexRuntime
#
#     budget: Compute
#     global_objective: Objective
#   Model = enum
#     m_sol, m_terra, m_luna
#
# proc model_compute_usage_multiplier(model: Model): float =
#   case model:
#   of m_luna: 1
#   of m_terra: 10
#   of m_sol: 25
#
# proc reasoning_effort_compute_usage_multiplier(effort: ReasoningEffort): float =
#   case effort:
#   of re_minimal: 0.4
#   of re_low: 1
#   of re_medium: 1.8
#   of re_high: 3.2
#   of re_xhigh: 5.3
#
#
# proc main() =
#   let cwd = Path(getCurrentDir())
#   let global_objective_input_path = cwd / relative_global_objective_input_path
#   let parsed = parsetoml.parseFile($global_objective_input_path)
#
#   let objective = Objective(
#     goal: parsed["objective"]["goal"].getStr()
#   )
#
#   let initial_budget = parsed["settings"]["budget"].getFloat()
#   echo objective
#   echo initial_budget
#
# main()


type
  Objective = object
    goal: string
  TestEnum = enum
    a, b, c
  TestType = object
    res: bool
    enu: TestEnum

const relative_global_objective_input_path = Path("./run_settings.toml")

proc main(): Result[ArtifactID, ModelError] =
  let global_objective_input_path = getCurrentDir() / relative_global_objective_input_path
  let parsed = parsetoml.parseFile($global_objective_input_path)

  let objective = Objective(goal: parsed["objective"]["goal"].getStr())

  let initial_budget = parsed["settings"]["budget"].getFloat()
  echo objective
  echo initial_budget

  let s = Scope(codex: init_codex_runtime($getCurrentDir()))

  let cheap = Profile(model: m_luna, effort: re_minimal)
  let test_prompt: Prompt = objective.goal
  let answer = s.perform(orchestration_api.Request[TestType](
    prompt: test_prompt,
    profile: cheap,
    anchors: @[],
  ))

  if not answer.isOk: return err(answer.error)

  echo answer.get()

  stop_codex_runtime(s.codex)
  s.codex.deinit_codex_runtime()

discard main()
