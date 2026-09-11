{.experimental: "callOperator".}

## Typed flow declarations and IR descriptors. Runtime values belong elsewhere.

import std/[macros, assertions, sugar]
import fusion/matching
import it_projection, lift_pattern_typed

type
  FlowIRKind* = enum
    firk_ref,
    firk_empty,
    firk_so,
    firk_it,
    firk_lift
  FlowIR* = ref object
    case kind: FlowIRKind:
    of firk_ref:
      id*: int
      entry*: bool
    of firk_so:
      fn*: pointer
    of firk_it:
      path*: ItPath
    of firk_lift:
      pattern*: string
      inner*: FlowIR
    else: discard
  FlowSpec*[A, B] = object
    ir*: FlowIR
  ProfileSpec* = object
  PartialModelCallSyntax*[A, B] = object
  here* = object
  PartialLiftSyntax*[Pattern: static string] = object

template flow_ir*(id: int, entry: bool) {.pragma.}
template `~>`*(A, B: untyped): untyped = FlowSpec[A, B]
proc `[]`*[A, B](profile: ProfileSpec; _: typedesc[A]; _: typedesc[B]): PartialModelCallSyntax[A, B] = PartialModelCallSyntax[A, B]()
proc `()`*[A, B](partial: PartialModelCallSyntax[A, B]; prompt: string): FlowSpec[A, B] =
  FlowSpec[A, B](ir: FlowIR(kind: firk_empty))
proc `>>>`*[A, B, C](lf: FlowSpec[A, B]; rt: FlowSpec[B, C]): FlowSpec[A, C] =
  FlowSpec[A, C](ir: FlowIR(kind: firk_empty))
proc `>>>`*[A, B](lf: A; rt: FlowSpec[A, B]): FlowSpec[void, B] =
  FlowSpec[void, B](ir: FlowIR(kind: firk_empty))
proc fanout*[A, B; C: tuple](c: C): FlowSpec[A, B] =
  FlowSpec[A, B](ir: FlowIR(kind: firk_empty))
proc pure*[A](v: A): FlowSpec[void, A] =
  FlowSpec[void, A](ir: FlowIR(kind: firk_empty))
macro fan*(args: varargs[typed]): untyped =
  if args.len < 1: error("args.len must be >= 1")
  args[0].getTypeInst.assertMatch(
    BracketExpr([
      _ is Sym(),
      @input,
      _
  ]))

  var tupleArgs = newTree(nnkTupleConstr)
  var tupleType = newTree(nnkTupleConstr)
  var returnType = newTree(nnkTupleConstr)

  for arg in args:
    arg.getTypeInst.assertMatch(
      @full is BracketExpr([
        @sym is Sym(),
        @domain,
        @codomain
      ]))
    doAssert sym.strVal == "FlowSpec"
    doAssert domain == input
    tupleArgs.add arg
    tupleType.add full
    returnType.add codomain

  result = quote do:
    fanout[`input`, `returnType`, `tupleType`](`tupleArgs`)

proc make_so_flow(domain, codomain, pattern, body: NimNode): NimNode =
  let parameter = ident(pattern.strVal)
  let bodyText = newLit(body.repr)
  result = quote do:
    FlowSpec[`domain`, `codomain`](
      ir: FlowIR(
        kind: firk_so,
        fn: cast[pointer](proc (`parameter`: `domain`): FlowSpec[void, `codomain`] =
        `body`)
      )
    )

macro so*(domain, codomain, pattern, body: untyped): untyped =
  result = make_so_flow(domain, codomain, pattern, body)

macro project_it(value: typed; path: static[ItPath]; depth: static[int] = 0): untyped =
  let group = path.groups[depth]
  result = newTree(nnkTupleConstr)

  template select(selector: NimNode) =
    # Every later group acts on each selected item, retaining tuple nesting.
    if depth + 1 < path.groups.len:
      result.add newCall(bindSym"project_it", selector, newLit(path), newLit(depth + 1))
    else:
      result.add selector

  for selector in group.selectors:
    case selector.kind
    of itsIndex:
      select(newTree(nnkBracketExpr, value, newLit(selector.index)))
    of itsField:
      select(newTree(nnkDotExpr, value, ident(selector.field)))
    of itsRange:
      let shape = value.getTypeImpl # might not be handling anonymous tuple types
      if shape.kind != nnkTupleTy and shape.kind != nnkTupleConstr:
        error("it range requires a tuple", value)
      let arity = shape.len
      if selector.first < 0 or selector.last >= arity:
        error("it range is outside tuple bounds", value)
      for index in selector.first .. selector.last:
        select(newTree(nnkBracketExpr, value, newLit(index)))

  if result.len == 1:
    result = result[0]

proc make_it_flow(domain: NimNode; path: ItPath): NimNode =
  let parameter = ident("it_input")
  let pathLiteral = newLit(path)
  let body = if path.groups.len == 0: parameter
             else: newCall(bindSym"project_it", parameter, pathLiteral)
  let codomain = quote do:
    typeof((block:
      var `parameter`: `domain`
      `body`))
  result = quote do:
    FlowSpec[`domain`, `codomain`](
      ir: FlowIR(
        kind: firk_it,
        path: `pathLiteral`
      )
    )

macro it*(domain: untyped): untyped =
  make_it_flow(domain, ItPath())

macro append_it*(
  domain: untyped;
  prior_path: static ItPath;
  new_selectors: untyped
): untyped =
  var new_path = prior_path
  new_path.groups.add parseItPath(newTree(nnkBracket, new_selectors)).groups[0]
  make_it_flow(domain, new_path)

macro `[]`*(
  base: FlowSpec;
  selectors: varargs[untyped]
): untyped =
  if (ObjConstr([
    _,
    ExprColonExpr([
      _,
      ObjConstr([
        _,
        _,
        ExprColonExpr([
          _,
          @path
        ])
      ])
    ])
  ])) ?= base:
    let group = newTree(nnkBracket)
    for selector in selectors:
      group.add selector
    return newCall(bindSym"append_it", base.getTypeInst[1], path, group)

macro make_lift(spelling: static string; step: typed): untyped =
  let flow_type = step.getTypeInst
  dump flow_type.repr
  BracketExpr([
      _ is Sym(),
      @step_domain,
      @step_codomain
  ]) := flow_type

  let pattern = parseExpr(spelling)
  dump pattern.repr
  let lift_pattern = parse_lift_pattern(pattern)
  debug_lift_pattern(lift_pattern)
  let (input_type, output_type) = lift_types(
    lift_pattern, step_domain, step_codomain)
  dump input_type.repr
  dump output_type.repr

  result = quote do:
    FlowSpec[`input_type`, `output_type`](
      ir: FlowIR(
        kind: firk_lift,
        pattern: `spelling`,
        inner: (`step`).ir
      )
    )

template `[]`*[Pattern: static string](
  partial: PartialLiftSyntax[Pattern];
  flow: untyped
): untyped = make_lift(Pattern, flow)

macro lift*(pattern: untyped): untyped =
  let spelling = newLit(pattern.repr)
  result = quote do:
    PartialLiftSyntax[`spelling`]()

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
        let `name` = FlowSpec[`domain`, `codomain`](ir: FlowIR(
          kind: firk_ref,
          id: `id`
        ))

      let proc_name = genSym(nskProc, "flow")
      procs.add quote do:
        proc `proc_name`: `domain` ~> `codomain` {.flow_ir(`id`, `entry`).} =
          `flow_body`
    else: error("Malformed vecherinka flow", child)

  for node in procs:
    refs.add node

  result = quote do:
    `refs`
