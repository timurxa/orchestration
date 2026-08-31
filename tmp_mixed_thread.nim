import std/typedthreads

type
  Problem = object
    goal: string
  Context = object
  Consumer[T] = proc (x: T) {.closure, gcsafe.}
  Step[A, B] = proc (x: A; c: Consumer[B]) {.closure, gcsafe.}
  Contextual[A, B] = proc (ctx: Context): Step[A, B] {.closure, gcsafe.}

proc solve(problem: Problem): Contextual[int, string] =
  proc makeStep(ctx: Context): Step[int, string] {.gcsafe.} =
    proc run(x: int; c: Consumer[string]) {.gcsafe.} =
      c(problem.goal)
    run
  makeStep

type RuntimeArgs = object
  problem: Problem

proc runtime(args: RuntimeArgs) {.thread, gcsafe.} =
  let work = solve(args.problem)
  let step = work(Context())
  step(0, proc (result: string) {.gcsafe.} = echo result)

proc start(problem: Problem) =
  var thread: Thread[RuntimeArgs]
  createThread(thread, runtime, RuntimeArgs(problem: problem))
  thread.joinThread()

start(Problem(goal: "Say hi"))
