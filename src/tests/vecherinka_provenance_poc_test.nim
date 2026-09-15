{.experimental: "callOperator".}

import std/macros
import ../api/vecherinka

type
  POCInput = object
    request: string

  POCOutput = object
    response: string

const profile = luna.medium

expandMacros: vecherinka(solve, default_agent_prompt_templates):
  > respond POCInput ~> POCOutput {.entry.}:
    profile[POCInput, POCOutput]("Return a short response. Set response to exactly `provenance-poc-ok`.")

let output = solve(POCInput(request: "provenance logging proof of concept"),
  100.0, default_agent_prompt_templates)
if output.response != "provenance-poc-ok":
  quit("unexpected child response: " & output.response, QuitFailure)
echo "child-response: ", output.response
