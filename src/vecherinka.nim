{.experimental: "callOperator".}

import std/[macros, assertions, sugar, options, genasts]
import fusion/matching
import it_projection, lift_pattern_typed

type
  FlowNodeKind* = enum
    fnode_reference
    fnode_empty
    fnode_so
    fnode_it
    fnode_lift
    fnode_compose
    fnode_fanout
  FlowNode* = object
    kind*: FlowNodeKind
    id*: int
    text*: string
    path*: ItPath
    children*: seq[FlowNode]
  ItAction* = object
    path*: ItPath
  LiftAction* = object
    pattern*: string
    step*: FlowNode
  FlowKind = enum
    fk_ref,
    fk_empty,
    fk_so,
    fk_it,
    fk_lift
  Flow*[A, B] = object
    node*: FlowNode
    case kind: FlowKind:
    of fk_ref:
      id: int
      entry: bool
    of fk_so:
      fn*: proc (a: A): B {.nimcall.}
    of fk_it:
      it_action*: ItAction
    of fk_lift:
      pattern*: string
      step*: 
    of fk_empty: discard
  Profile* = object
  PartialModelCallSyntax*[A, B] = object
  here* = object
  PartialLiftSyntax*[Pattern: static string] = object

# proc isFlowType(typ: NimNode): bool =
#   if typ.kind != nnkBracketExpr or typ.len != 3 or
#       not typ[0].eqIdent("Flow"):
#     return false
#   sameType(typ[0], bindSym("Flow"))
#
# proc isWrapperShape(shape: NimNode; wrapper: string): bool =
#   if shape.kind != nnkBracketExpr or shape.len != 2 or
#       not shape[0].eqIdent(wrapper):
#     return false
#   if wrapper == "Option":
#     return sameType(shape[0], bindSym("Option"))
#   true
#
# proc resolveFlowType(typ: NimNode): NimNode

template flow*(id: int, entry: bool) {.pragma.}
template `~>`*(A, B: untyped): untyped = Flow[A, B]
proc `[]`*[A, B](profile: Profile; _: typedesc[A]; _: typedesc[B]): PartialModelCallSyntax[A, B] = PartialModelCallSyntax[A, B]()
proc `()`*[A, B](partial: PartialModelCallSyntax[A, B]; prompt: string): Flow[A, B] =
  Flow[A, B](kind: fk_empty, node: FlowNode(kind: fnode_empty, text: prompt))
proc `>>>`*[A, B, C](lf: Flow[A, B]; rt: Flow[B, C]): Flow[A, C] =
  Flow[A, C](kind: fk_empty,
    node: FlowNode(kind: fnode_compose, children: @[lf.node, rt.node]))
proc fanout*[A, B; C: tuple](c: C): Flow[A, B] =
  Flow[A, B](kind: fk_empty)
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
    doAssert sym.strVal == "Flow"
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
    Flow[`domain`, `codomain`](
      kind: fk_so,
      node: FlowNode(kind: fnode_so, text: `bodyText`),
      fn: proc (`parameter`: `domain`): `codomain` =
        `body`
    )

macro so*(domain, codomain, pattern, body: untyped): untyped =
  result = make_so_flow(domain, codomain, pattern, body)

# macro `[]`*(_: LiftSyntax; output, pattern: untyped): untyped =
#   ## Explicit output supplies every independent `_` type; `here` reverses
#   ## the inner flow's endpoints. Object patterns retain their nominal type.
#   let spelling = newLit(pattern.repr)
#   dump spelling.strVal
#   result = quote do:
#     LiftSpec[`output`, `spelling`]()
#
# proc substituteType(node: NimNode; names: seq[string];
#     values: seq[NimNode]): NimNode
#
# proc liftShape(typ: NimNode): NimNode =
#   ## Follow aliases, retaining instantiated wrapper arguments.
#   result = typ
#   for _ in 0 .. 8:
#     if result.kind == nnkBracketExpr:
#       if result.len == 2 and result[0].eqIdent("seq"):
#         return
#       if result.len == 2 and result[0].eqIdent("Option"):
#         return
#       let head = result[0]
#       if head.kind notin {nnkIdent, nnkSym}:
#         return
#       let definition = head.getImpl
#       if definition.kind != nnkTypeDef:
#         return
#       var names: seq[string]
#       var values: seq[NimNode]
#       for parameter in definition[1]:
#         if parameter.kind in {nnkIdent, nnkSym}:
#           names.add parameter.strVal
#         elif parameter.kind == nnkIdentDefs:
#           names.add parameter[0].strVal
#       for index in 1 ..< result.len:
#         values.add result[index]
#       result = substituteType(definition[2], names, values)
#     elif result.kind == nnkSym:
#       let definition = result.getImpl
#       if definition.kind != nnkTypeDef:
#         return
#       let body = definition[2]
#       if body.kind == nnkObjectTy:
#         result = body
#         return
#       result = body
#     else:
#       return
#
# proc liftTag(pattern: LiftPattern; name: NimNode): NimNode =
#   for index in 0 ..< pattern.objectMemberCount:
#     let member = pattern.objectMember(index)
#     if name.eqIdent(member.name) and member.kind == lomTag:
#       return member.tag.tagExpression
#
# proc objectField(schema: NimNode; name: string; pattern: LiftPattern;
#     checks: var NimNode; accessed: bool): NimNode =
#   case schema.kind
#   of nnkIdentDefs:
#     for index in 0 ..< schema.len - 2:
#       if schema[index].eqIdent(name): return schema[^2]
#   of nnkRecList:
#     for child in schema:
#       result = objectField(child, name, pattern, checks, accessed)
#       if not result.isNil: return
#   of nnkRecCase:
#     result = objectField(schema[0], name, pattern, checks, accessed)
#     if not result.isNil: return
#     for index in 1 ..< schema.len:
#       let branch = schema[index]
#       result = objectField(branch[^1], name, pattern, checks, accessed)
#       if result.isNil: continue
#       if accessed:
#         let tag = liftTag(pattern, schema[0][0])
#         if tag.isNil:
#           error("lift variant field requires an explicit discriminator tag", schema)
#         # Prove the selected field belongs to this tag before generating access.
#         var accepted = newTree(nnkCaseStmt, tag)
#         for branchIndex in 1 ..< schema.len:
#           let sourceBranch = schema[branchIndex]
#           if sourceBranch.kind == nnkElse:
#             accepted.add(newTree(nnkElse,
#               newStmtList(newLit(branchIndex == index))))
#             continue
#           var testBranch = newNimNode(sourceBranch.kind)
#           for label in 0 ..< sourceBranch.len - 1:
#             testBranch.add(sourceBranch[label])
#           testBranch.add(newStmtList(newLit(branchIndex == index)))
#           accepted.add(testBranch)
#         if schema[^1].kind != nnkElse:
#           accepted.add(newTree(nnkElse, newStmtList(newLit(false))))
#         checks.add quote do:
#           static:
#             doAssert `accepted`, "lift tag does not contain the selected field"
#       return
#   else: discard
#
# proc objectDiscriminator(schema: NimNode; name: string): bool =
#   if schema.kind == nnkRecCase and schema[0][0].eqIdent(name): return true
#   if schema.kind in {nnkRecList, nnkRecCase, nnkOfBranch, nnkElse}:
#     for child in schema:
#       if objectDiscriminator(child, name): return true
#
# proc deriveLift(tree: LiftPatternTree; id: LiftPatternId;
#     output, innerInput, innerOutput: NimNode):
#     tuple[inputType, checks: NimNode] =
#   let pattern = tree.node(id)
#   case pattern.patternKind
#   of lpkKeep:
#     (output, newStmtList())
#   of lpkHere:
#     if not sameType(output, innerOutput):
#       error("lift `here` output must match the inner flow output", output)
#     (innerInput, newStmtList())
#   of lpkSeq, lpkOption:
#     let shape = liftShape(output)
#     let wrapper = if pattern.patternKind == lpkSeq: "seq" else: "Option"
#     if not isWrapperShape(shape, wrapper):
#       error("lift " & wrapper & " pattern requires matching output wrapper", output)
#     let child = deriveLift(tree, pattern.childId, shape[1],
#       innerInput, innerOutput)
#     let sourceType = newTree(nnkBracketExpr, shape[0], child.inputType)
#     (sourceType, child.checks)
#   of lpkTuple:
#     let fields = output.getTypeImpl
#     if fields.kind notin {nnkTupleTy, nnkTupleConstr} or
#         fields.len != pattern.tupleItemCount:
#       error("lift tuple pattern must cover every output tuple field", output)
#     let named = fields.kind == nnkTupleTy
#     var sourceType = newNimNode(fields.kind)
#     var checks = newStmtList()
#     for index in 0 ..< pattern.tupleItemCount:
#       let item = pattern.tupleItem(index)
#       let field = fields[index]
#       if item.name.len > 0 and (not named or not field[0].eqIdent(item.name)):
#         error("lift tuple labels must match output field order", output)
#       let fieldType = if named: field[^2] else: field
#       let child = deriveLift(tree, item.patternId, fieldType,
#         innerInput, innerOutput)
#       checks.add child.checks
#       if named:
#         sourceType.add(newIdentDefs(ident(field[0].strVal), child.inputType))
#       else:
#         sourceType.add(child.inputType)
#     (sourceType, checks)
#   of lpkObject:
#     let shape = liftShape(output)
#     if shape.kind != nnkObjectTy or shape[1].kind != nnkEmpty:
#       error("lift object pattern requires a non-inherited value object", output)
#     let head = pattern.objectTypeExpr
#     var checks = newStmtList()
#     checks.add quote do:
#       when not (`head` is `output`) or not (`output` is `head`):
#         {.error: "lift object head must match its output type".}
#     for index in 0 ..< pattern.objectMemberCount:
#       let member = pattern.objectMember(index)
#       let accessed = member.kind == lomPattern and
#         tree.node(member.patternId).patternKind != lpkKeep
#       let fieldType = objectField(shape[2], member.name, pattern, checks,
#         accessed or member.kind == lomTag)
#       if fieldType.isNil:
#         error("unknown lift object field: " & member.name, output)
#       case member.kind
#       of lomWildcard: discard
#       of lomTag:
#         if not objectDiscriminator(shape[2], member.name):
#           error("lift tags are only valid on variant discriminators", output)
#         let tag = member.tag.tagExpression
#         checks.add quote do:
#           static:
#             let checkedTag: `fieldType` = `tag`
#             discard checkedTag
#       of lomPattern:
#         if objectDiscriminator(shape[2], member.name):
#           error("lift cannot transform a variant discriminator", output)
#         let child = deriveLift(tree, member.patternId, fieldType,
#           innerInput, innerOutput)
#         checks.add child.checks
#         let required = child.inputType
#         checks.add quote do:
#           when not (`fieldType` is `required`) or not (`required` is `fieldType`):
#             {.error: "lift cannot change a nominal object field type".}
#     (output, checks)
#
# proc substituteType(node: NimNode; names: seq[string];
#     values: seq[NimNode]): NimNode =
#   if node.kind in {nnkIdent, nnkSym}:
#     for index, name in names:
#       if node.eqIdent(name):
#         return copyNimTree(values[index])
#     return copyNimTree(node)
#   result = newNimNode(node.kind)
#   for child in node:
#     result.add substituteType(child, names, values)
#
# proc resolveFlowType(typ: NimNode): NimNode =
#   result = typ
#   for _ in 0 .. 8:
#     if isFlowType(result):
#       return
#     let head = if result.kind == nnkBracketExpr: result[0] else: result
#     if head.kind notin {nnkIdent, nnkSym}:
#       return
#     let definition = head.getImpl
#     if definition.kind != nnkTypeDef:
#       return
#     let body = definition[2]
#     if result.kind == nnkBracketExpr:
#       var names: seq[string]
#       var values: seq[NimNode]
#       for parameter in definition[1]:
#         if parameter.kind in {nnkIdent, nnkSym}:
#           names.add parameter.strVal
#         elif parameter.kind == nnkIdentDefs:
#           names.add parameter[0].strVal
#       for index in 1 ..< result.len:
#         values.add result[index]
#       if body.kind == nnkBracketExpr and body.len == 3 and
#           body[0].eqIdent("Flow"):
#         result = newNimNode(nnkBracketExpr)
#         result.add copyNimTree(body[0])
#         result.add substituteType(body[1], names, values)
#         result.add substituteType(body[2], names, values)
#       else:
#         result = substituteType(body, names, values)
#     else:
#       result = body
#
# macro makeLift(output: typedesc; spelling: static[string]; step: typed): untyped =
#   let flowType = resolveFlowType(step.getTypeInst)
#   if not isFlowType(flowType):
#     error("lift expects a Flow value", step)
#   let tree = parseLiftPattern(parseExpr(spelling))
#   let target = output.getTypeInst[1]
#   let derived = deriveLift(tree, tree.rootId, target,
#     flowType[1], flowType[2])
#   let source = derived.inputType
#   let checks = derived.checks
#   let patternText = newLit(spelling)
#   let savedStep = genSym(nskLet, "liftStep")
#   let stepNode = newDotExpr(savedStep, ident("node"))
#   let childNodes = newTree(nnkPrefix, ident("@"),
#     newTree(nnkBracket, stepNode))
#   result = quote do:
#     block:
#       static:
#         `checks`
#       let `savedStep` = `step`
#       Flow[`source`, `target`](kind: fk_lift,
#         node: FlowNode(kind: fnode_lift, text: `patternText`,
#           children: `childNodes`),
#         liftAction: LiftAction(pattern: `patternText`, step: `stepNode`))
#
#   dump result.repr
#
# template `()`*[Output; Pattern: static[string]](
#     spec: LiftSpec[Output, Pattern]; step: untyped): untyped =
#   makeLift(Output, Pattern, step)

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
    Flow[`domain`, `codomain`](
      kind: fk_it,
      itAction: ItAction(path: `pathLiteral`)
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
  base: Flow;
  selectors: varargs[untyped]
): untyped =
  if (ObjConstr([
    _,
    _,
    ExprColonExpr([
      _,
      ObjConstr([
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
    Flow[`domain`, `codomain`](
      kind: fk_lift,

    )

  result = newEmptyNode()

template `[]`*[Pattern: static string](
  partial: PartialLiftSyntax[Pattern];
  flow: untyped
): untyped = make_lift(Pattern, flow)

macro lift*(pattern: untyped): untyped =
  let spelling = newLit(pattern.repr)
  dump spelling.strVal
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
        const `name` = Flow[`domain`, `codomain`](kind: fk_ref, id: `id`,
          node: FlowNode(kind: fnode_reference, id: `id`))

      let proc_name = genSym(nskProc, "flow")
      procs.add quote do:
        proc `proc_name`: `domain` ~> `codomain` {.flow(`id`, `entry`).} =
          `flow_body`
    else: error("Malformed konez flow", child)

  for node in procs:
    refs.add node

  result = quote do:
    `refs`
