{.experimental: "callOperator".}

import std/macros
import ../api/vecherinka

type
  POCInput = object
    request: string

  POCOutput = object
    response: string

const model_profile = "gpt-5.6-luna".medium

expandMacros: vecherinka(solve):
  > answer POCInput ~> POCOutput {.entry.}:
    model_profile[POCInput, POCOutput](
      "Return a short response. Set response to exactly `provenance-poc-ok`.")

let output = solve(POCInput(request: "provenance logging proof of concept"))
if output.response != "provenance-poc-ok":
  quit("unexpected child response: " & output.response, QuitFailure)
echo "child-response: ", output.response
