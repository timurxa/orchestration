import std/macros

type
  Context = object
    offset: int
  Idea = object
    value: int
  Plan = object
    value: int

type
  Contextual[A, B] = proc (ctx: Context): proc (value: A): B {.closure.}

template `~>`(a, b: typedesc): untyped =
  Contextual[a, b]

proc unpackArrow(n: NimNode): tuple[ok: bool, input, output: NimNode] =
  case n.kind
  of nnkInfix:
    if $n[0] == "~>":
      return (true, n[1], n[2])
  of nnkBracketExpr:
    if $n[0] == "Contextual":
      return (true, n[1], n[2])
    if $n[0] == "typeDesc":
      return unpackArrow(n[1])
  of nnkSym:
    let definition = n.getImpl
    if definition.kind == nnkTypeDef:
      return unpackArrow(definition[2])
  else:
    discard
  (false, newEmptyNode(), newEmptyNode())

macro `>>>`(left, right: typedesc): untyped =
  let first = unpackArrow(left)
  let second = unpackArrow(right)
  if not first.ok or not second.ok:
    error(">>> expects two A ~> B types", left)
  if not sameType(first.output, second.input):
    error("middle types do not match", right)
  result = newTree(nnkBracketExpr, bindSym"Contextual", first.input, second.output)

type
  Planner = Idea ~> Plan

proc `>>>`[A, B, C](
    first: proc (ctx: Context): proc (value: A): B {.closure.},
    second: proc (ctx: Context): proc (value: B): C {.closure.},
  ): proc (ctx: Context): proc (value: A): C {.closure.} =
  proc composed(ctx: Context): proc (value: A): C =
    let firstStep = first(ctx)
    let secondStep = second(ctx)
    proc apply(value: A): C =
      secondStep(firstStep(value))
    apply
  composed

proc ideaToPlan(ctx: Context): proc (idea: Idea): Plan =
  proc plan(idea: Idea): Plan =
    Plan(value: idea.value + ctx.offset)
  plan

proc planToIdea(ctx: Context): proc (plan: Plan): Idea =
  proc convert(plan: Plan): Idea =
    Idea(value: plan.value - ctx.offset)
  convert

type
  IdeaToIdea = (Idea ~> Plan) >>> (Plan ~> Idea)
  IdeaToIdeaViaAlias = Planner >>> (Plan ~> Idea)

let planner: Planner = ideaToPlan
let pipeline: IdeaToIdea = planner >>> planToIdea
let pipelineViaAlias: IdeaToIdeaViaAlias = pipeline
let result = pipelineViaAlias(Context(offset: 10))(Idea(value: 32))
doAssert result.value == 32
