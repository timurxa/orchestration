{.experimental: "callOperator".}

import vecherinka

type
  Input = object
  Middle = object
  Output = object

const profile = "gpt-5.6-luna".minimal

vecherinka(solve):
  > first Input ~> Middle:
    profile[Input, Middle]("first")
  > entry Input ~> Output {.entry.}:
    first >>> profile[Middle, Output]("second")

solve(Input())
