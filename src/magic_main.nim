import std/[sugar, paths]
import parsetoml
import magic_api
import magic_solve
import magic_runtime

const relative_global_objective_input_path = Path("./run_settings.toml")

proc main() =
  let cwd = getCurrentDir()
  let global_objective_input_path = cwd / relative_global_objective_input_path
  let parsed = parsetoml.parseFile($global_objective_input_path)

  let problem = Problem(goal: parsed["objective"]["goal"].getStr())
  start[Problem, Response](problem, solve, (outcome: Outcome[Response]) =>
    echo outcome
  )

main()
