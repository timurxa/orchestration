{.experimental: "callOperator".}

import std/macros
import lift_pattern
import it_projection

type
  Location* = distinct string

  ## Endpoint types are sole runtime representation. Values never execute.
  Flow*[A, B] = object

  IdentitySyntax* = object
  LiftSyntax* = object
  LiftPairPartialSyntax* = object
  LiftPlainPartialSyntax* = object
  LiftPair*[A, B] = object
  FlowFactory*[A, B] = proc (): Flow[A, B]
  SoCarrier[A, B] = object

const
  it* = IdentitySyntax()
  lift* = LiftSyntax()

template `~>`*(A, B: untyped): untyped = Flow[A, B]
template zvetok*(body: untyped): untyped = body
template entry* {.pragma.}

proc cheap*[A, B](prompt: string): Flow[A, B] =
  discard prompt
  Flow[A, B]()

proc pure*[T](value: T): T = value

proc flattenFanoutArg(node: NimNode; operands: var seq[NimNode]) =
  if node.kind == nnkCommand:
    for child in node:
      flattenFanoutArg(child, operands)
  else:
    operands.add(node)

macro `&&&`*(args: varargs[untyped]): untyped =
  var operands: seq[NimNode]
  for arg in args:
    flattenFanoutArg(arg, operands)

  if operands.len < 2:
    error("&&& expects at least two flows", args)

  result = newNimNode(nnkCall)
  result.add(ident("fanoutFlat"))
  for operand in operands:
    result.add(operand)

proc flowType(typeInst: NimNode; source: NimNode): NimNode =
  var candidate = typeInst
  if candidate.kind == nnkProcTy:
    candidate = candidate[0][0]

  if candidate.kind != nnkBracketExpr or candidate.len != 3 or
      candidate[0].repr != "Flow":
    error("expected a Flow value or Flow-producing proc", source)
  copyNimTree(candidate)

macro fanoutFlat*(args: varargs[typed]): untyped =
  var inputType: NimNode
  var endpointTypes: seq[NimNode]
  var identities: seq[bool]

  for arg in args:
    let argType = arg.getTypeInst
    if argType.kind in {nnkIdent, nnkSym} and
        argType.strVal == "IdentitySyntax":
      identities.add(true)
      endpointTypes.add(nil)
      continue

    let endpoints = flowType(argType, arg)
    let candidateInput = endpoints[1]
    if inputType.isNil:
      inputType = copyNimTree(candidateInput)
    elif not sameType(inputType, candidateInput):
      error("&&& flows must share input type", arg)
    identities.add(false)
    endpointTypes.add(endpoints)

  if inputType.isNil:
    error("&&& needs at least one typed flow", args)

  var tupleType = newNimNode(nnkTupleConstr)
  for index, endpoints in endpointTypes:
    if identities[index]:
      tupleType.add(copyNimTree(inputType))
    else:
      tupleType.add(copyNimTree(endpoints[2]))

  var flowTypeNode = newNimNode(nnkBracketExpr)
  flowTypeNode.add(bindSym("Flow"))
  flowTypeNode.add(inputType)
  flowTypeNode.add(tupleType)

  result = newNimNode(nnkCall)
  result.add(flowTypeNode)

proc `>>>`*[A, B, C](left: Flow[A, B]; right: Flow[B, C]): Flow[A, C] =
  discard left
  discard right
  Flow[A, C]()

proc `>>>`*[A, B](value: A; right: Flow[A, B]): B =
  discard value
  discard right
  default(B)

proc `>>>`*[A, B, C](
    left: Flow[A, B];
    right: FlowFactory[B, C]
): Flow[A, C] =
  discard left
  discard right
  Flow[A, C]()

proc `>>>`*[A, B](value: A; right: FlowFactory[A, B]): B =
  discard value
  discard right
  default(B)

proc `>>>`*[Prefix, A, B](
    value: (Prefix, A);
    right: LiftPair[A, B]
): (Prefix, B) =
  discard value
  discard right
  default((Prefix, B))

proc `>>>`*[Input, Prefix, A, B](
    left: Flow[Input, (Prefix, A)];
    right: LiftPair[A, B]
): Flow[Input, (Prefix, B)] =
  discard left
  discard right
  Flow[Input, (Prefix, B)]()

proc liftPair*[A, B](step: Flow[A, B]): LiftPair[A, B] =
  discard step
  LiftPair[A, B]()

proc liftPair*[A, B](step: FlowFactory[A, B]): LiftPair[A, B] =
  discard step
  LiftPair[A, B]()

template so*[A, B](param, body: untyped): untyped =
  soImpl(SoCarrier[A, B], param, body)

macro soImpl*(tag: typedesc; param, body: untyped): untyped =
  let typeInst = tag.getTypeInst[1]
  if typeInst.kind != nnkBracketExpr or typeInst.len != 3:
    error("so expects input and output types", tag)

  let inputType = copyNimTree(typeInst[1])
  let outputType = copyNimTree(typeInst[2])
  let checker = genSym(nskProc, "soCheck")

  result = quote do:
    block:
      proc `checker`(`param`: `inputType`): `outputType` =
        `body`
      Flow[`inputType`, `outputType`]()

macro `[]`*(base: LiftSyntax; pattern: untyped): untyped =
  let tree = parseLiftPattern(pattern)
  let root = tree.rootPattern
  if root.patternKind == lpkTuple and root.tupleItemCount == 2:
    let first = tree.tupleItemPattern(root.tupleItem(0))
    let second = tree.tupleItemPattern(root.tupleItem(1))
    if first.patternKind == lpkKeep and second.patternKind == lpkHere:
      result = quote do:
        LiftPairPartialSyntax()
      return

  result = quote do:
    LiftPlainPartialSyntax()

macro `()`*(base: LiftPairPartialSyntax; body: typed): untyped =
  result = quote do:
    liftPair(`body`)

macro `()`*(base: LiftPlainPartialSyntax; body: typed): untyped =
  ## Pattern parser proves syntax. Type-only lowering preserves body endpoints;
  ## runtime reconstruction is intentionally outside this prototype.
  let endpoints = flowType(body.getTypeInst, body)
  var flowNode = newNimNode(nnkBracketExpr)
  flowNode.add(bindSym("Flow"))
  flowNode.add(copyNimTree(endpoints[1]))
  flowNode.add(copyNimTree(endpoints[2]))
  result = newNimNode(nnkCall)
  result.add(flowNode)

macro `[]`*(base: IdentitySyntax; typeArgs: varargs[untyped]): untyped =
  if typeArgs.len != 2:
    error("typed it projection expects `it[Input, Output][selectors]`", base)
  var projectionType = newNimNode(nnkBracketExpr)
  projectionType.add(bindSym("Flow"))
  projectionType.add(copyNimTree(typeArgs[0]))
  projectionType.add(copyNimTree(typeArgs[1]))
  result = newNimNode(nnkCall)
  result.add(projectionType)

proc validateItSelectors(selectors: seq[NimNode]; source: NimNode) =
  if selectors.len == 0:
    error("it projection needs at least one selector", source)
  var group = newNimNode(nnkBracket)
  for selector in selectors:
    group.add(selector)
  var path = newNimNode(nnkBracket)
  path.add(group)
  discard parseItPath(path)

macro `[]`*[A, B](
    base: Flow[A, B];
    selectors: varargs[untyped]
): untyped =
  var selectorNodes: seq[NimNode]
  for selector in selectors:
    selectorNodes.add(selector)
  validateItSelectors(selectorNodes, base)
  result = base
