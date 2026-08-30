import std/strutils
import results
import codex_json

# API
type
  Error = object
    message: string
  Outcome[T] = Result[T, Error]
  Consumer[T] = proc (outcome: Outcome[T]) {.closure.}

type
  Model = enum
    luna, terra, sol
  Profile = object
    model: Model
    effort: ReasoningEffort
  Prompt = string
  Start = object
  Context = object

proc submit[A, B](
  profile: Profile;
  prompt: Prompt;
  data: A;
  callback: Consumer[B]
) =
  # Runtime implementation sends profile, prompt, data, then calls callback.
  echo "Should call profile $# with prompt $# now" % [$profile, prompt]
  callback(Outcome[B].err(Error(message: "TODO")))

type
  Contextual[A, B] = proc (ctx: Context): proc (value: A; consumer: Consumer[B]) {.closure.}

template `~>`(A, B: typedesc): untyped =
  Contextual[A, B]

proc pure[T](given: T): Start ~> T =
  proc (_: Context): proc (_: Start; consumer: Consumer[T]) {.closure.} =
    proc (_: Start; consumer: Consumer[T]) =
      consumer(Outcome[T].ok(given))

proc `>>>`[A, B, C](
  left: Contextual[A, B];
  right: Contextual[B, C]
): Contextual[A, C] =
  proc composed(ctx: Context): proc (value: A; consumer: Consumer[C]) =
    let left_step = left(ctx)
    let right_step = right(ctx)
    proc apply(value: A; consumer: Consumer[C]) =
      left_step(value, proc(outcome: Outcome[B]) =
        if outcome.isErr:
          consumer(Outcome[C].err(outcome.error))
        else:
          right_step(outcome.get, consumer))
    apply
  composed

proc `[]`[A, B](profile: Profile; _: typedesc[A]; _: typedesc[B]): proc (prompt: Prompt): Contextual[A, B] =
  result = proc (prompt: Prompt): A ~> B =
    proc (_: Context): proc (value: A; consumer: Consumer[B]) =
      proc (value: A; consumer: Consumer[B]) =
        submit(profile, prompt, value, consumer)

proc minimal(model: Model): Profile = Profile(model: model, effort: re_minimal)
proc low(model: Model): Profile = Profile(model: model, effort: re_low)
proc medium(model: Model): Profile = Profile(model: model, effort: re_medium)
proc high(model: Model): Profile = Profile(model: model, effort: re_high)
proc xhigh(model: Model): Profile = Profile(model: model, effort: re_xhigh)

# EXAMPLE
type
  Problem = object 
    goal: string
  Plan = object 
    plan: string
  Response = object
    solved: bool
    message: string

const cheap = luna.low

proc solve(problem: Problem): Start ~> Response =
  pure(problem) >>>
    cheap[Problem, Plan]("Create a plan to solve this problem") >>>
    cheap[Plan, Response]("Respond to the problem")

# USAGE
proc main() =
  let context = Context()
  let problem = Problem(goal: "Say hi!")
  proc consumer(outcome: Outcome[Response]) =
    echo outcome
  let work = solve problem
  (work context)(Start(), consumer)

main()
