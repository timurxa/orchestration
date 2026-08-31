import magic_api

type
  Problem* = object 
    goal*: string
  Plan = object 
    plan: string
  Response* = object
    solved: bool
    message: string

const cheap = luna.low

proc solve*(problem: Problem): Start ~> Response =
  pure(problem) >>>
    cheap[Problem, Plan]("Create a plan to solve this problem") >>>
    cheap[Plan, Response]("Respond to the problem")
