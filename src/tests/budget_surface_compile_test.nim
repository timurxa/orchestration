{.experimental: "callOperator".}

import std/macros
import ../api/vecherinka

type Simple = object
  value: int

const profile = luna.medium
const pool_weights = [
  (name: "default", weight: 1.0),
  (name: "Implementation", weight: 2.0)
]

expandMacros: vecherinka(solve, pools = pool_weights):
  > step Simple ~> Simple:
    profile[Simple, Simple]("step")
  > entry Simple ~> Simple {.entry.}:
    pool Implementation:
      step
  > budgeted Simple ~> Simple:
    so_budget(Simple, Simple, input, budget) do:
      if budget.pool_remaining >= 0.0: pure(input)
      else: pure(input)
