import std/[sugar, paths]
import parsetoml
import bezkonza

{.experimental: "openSym".}

orchestrate:
  type
    Problem* = object
      goal*: string
    Variations* = object
      variations*: seq[Location]
    Response* = object
      solved*: bool
      message*: string

  artifact_types:
    Problem
    Variations
    Response

  const cheap = luna.low

  let solve*: Problem ~> Response =
    cheap[Problem, Variations]("Create multiple variations of the possible solution to this problem.") >>>
      cheap[Variations, Response]("Choose the best variation to answer the problem and write the message greeting.")

  const relative_global_objective_input_path = Path("./run_settings.toml")

  proc main*() =
    let cwd = paths.getCurrentDir()
    let global_objective_input_path = cwd / relative_global_objective_input_path
    let parsed = parsetoml.parseFile($global_objective_input_path)

    let problem = Problem(goal: parsed["objective"]["goal"].getStr())
    start[Problem, Response](problem, solve, (outcome: Outcome[Response]) =>
      echo outcome
    )

  when isMainModule:
    main()
