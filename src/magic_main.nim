import std/sugar
import magic_api
import magic_solve
import magic_runtime

start[Problem, Response](Problem(goal: "Write a greeting to a class of college students"), solve, (outcome: Outcome[Response]) =>
  echo outcome
)
