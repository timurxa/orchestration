{.experimental: "callOperator".}

import std/[macros, assertions, sugar]
import fusion/matching

type
  FlowKind = enum
    fk_ref,
    fk_empty,
    fk_so,
    fk_it
  Flow*[A, B] = object
    case kind: FlowKind:
    of fk_ref:
      id: int
      entry: bool
    of fk_so:
      fn*: proc (a: A): B {.nimcall.}
    of fk_it: discard
    of fk_empty: discard
  Profile* = object
  PartialModelCallSyntax*[A, B] = object

template flow*(id: int, entry: bool) {.pragma.}
template `~>`*(A, B: untyped): untyped = Flow[A, B]
proc `[]`*[A, B](profile: Profile; _: typedesc[A]; _: typedesc[B]): PartialModelCallSyntax[A, B] = PartialModelCallSyntax[A, B]()
proc `()`*[A, B](partial: PartialModelCallSyntax[A, B]; prompt: string): Flow[A, B] = Flow[A, B](kind: fk_empty)
proc `>>>`*[A, B, C](lf: Flow[A, B]; rt: Flow[B, C]): Flow[A, C] = Flow[A, C](kind: fk_empty)
proc fanout*[A, B; C: tuple](c: C): Flow[A, B] = Flow[A, B](kind: fk_empty)
macro fan*(args: varargs[typed]): untyped =
  if args.len < 1: error("args.len must be >= 1")
  args[0].getTypeInst.assertMatch(
    BracketExpr([
      _ is Sym(),
      @input,
      _
  ]))

  var tuple_args = newTree(nnkTupleConstr)
  var tuple_type = newTree(nnkTupleConstr)
  var return_type = newTree(nnkTupleConstr)

  for arg in args:
    arg.getTypeInst.assertMatch(
      @full is BracketExpr([
        @sym is Sym(),
        @domain,
        @codomain
      ]))
    doAssert sym.strVal == "Flow"
    doAssert domain == input
    tuple_args.add arg
    tuple_type.add full
    return_type.add codomain

  result = quote do:
    fanout[`input`, `return_type`, `tuple_type`](`tuple_args`)

proc make_so_flow(domain, codomain, pattern, body: NimNode): NimNode =
  let parameter = ident(pattern.strVal)
  result = quote do:
    Flow[`domain`, `codomain`](
      kind: fk_so,
      fn: proc (`parameter`: `domain`): `codomain` =
        `body`
    )

macro so*(domain, codomain, pattern, body: untyped): untyped =
  result = make_so_flow(domain, codomain, pattern, body)

macro it*(T: untyped): untyped =
  result = quote do:
    Flow[`T`, `T`](
      kind: fk_it
    )

macro vecherinka*(body: untyped): untyped =
  result = newEmptyNode()
  var refs, procs = newStmtList()

  for id, child in body:
    case child:
    of Prefix([@prefix, Command([@name, Infix([@arrow, @domain, @raw_codomain]), .._]), @flow_body]):
      expectIdent prefix, ">"
      expectIdent arrow, "~>"
      expectKind flow_body, nnkStmtList

      let (codomain, entry) = case raw_codomain:
        of PragmaExpr([@bare_codomain, Pragma([@pragma])]):
          (bare_codomain, pragma.strVal == "entry")
        else: (raw_codomain, false)

      refs.add quote do:
        const `name` = Flow[`domain`, `codomain`](kind: fk_ref, id: `id`)

      let proc_name = genSym(nskProc, "flow")
      procs.add quote do:
        proc `proc_name`: `domain` ~> `codomain` {.flow(`id`, `entry`).} =
          `flow_body`
    else: error("Malformed konez flow", child)

  for node in procs:
    refs.add node

  result = quote do:
    `refs`

  dump result.repr
