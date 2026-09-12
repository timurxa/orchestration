{.experimental: "callOperator".}

## Typed flow declarations and IR descriptors. Runtime values belong elsewhere.

import std/[macros, assertions, options, sugar]
import fusion/matching
import codex_json
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
    model*: string
    effort*: ReasoningEffort
  PartialModelCallSyntax*[A, B] = object
  here* = object
  PartialLiftSyntax*[Pattern: static string] = object
  Location* = distinct string

proc minimal*(model: string): ProfileSpec = ProfileSpec(model: model, effort: re_minimal)
proc low*(model: string): ProfileSpec = ProfileSpec(model: model, effort: re_low)
proc medium*(model: string): ProfileSpec = ProfileSpec(model: model, effort: re_medium)
proc high*(model: string): ProfileSpec = ProfileSpec(model: model, effort: re_high)
proc xhigh*(model: string): ProfileSpec = ProfileSpec(model: model, effort: re_xhigh)

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
  BracketExpr([
      _ is Sym(),
      @step_domain,
      @step_codomain
  ]) := flow_type

  let pattern = parseExpr(spelling)
  let lift_pattern = parse_lift_pattern(pattern)
  debug_lift_pattern(lift_pattern)
  let (input_type, output_type) = lift_types(
    lift_pattern, step_domain, step_codomain)

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

type
  FlowWalkPhase = enum
    fwpGatherTypes,
    fwpProcess
  FlowWalkContext = object
    phase: FlowWalkPhase
    flow_spec_symbol: NimNode
    flow_types: seq[NimNode]
    encountered: int

  ArtifactTypeInfo = object
    type_expr: NimNode
    kind_name: NimNode
    value_name: NimNode

  ArtifactRegistry = object
    kind_name: NimNode
    artifact_name: NimNode
    work_name: NimNode
    types: seq[ArtifactTypeInfo]

  LiftOccurrence = object
    pattern: string
    tree: LiftPatternTree
    outer_domain: NimNode
    outer_codomain: NimNode
    inner_domain: NimNode
    inner_codomain: NimNode

  LiftEmitState = object
    ## Both emitters advance one shared preorder cursor per `here`.
    next_index: NimNode
    works: NimNode
    results: NimNode

proc flow_spec_type(node, flow_spec_symbol: NimNode): NimNode =
  ## `getTypeInst` is only safe on typed expression nodes. Type syntax,
  ## pragmas, and some macro/template calls have no type and fail hard.
  if node.kind == nnkSym and node.symKind notin {
      nskParam, nskTemp, nskVar, nskLet, nskConst, nskResult, nskForVar}:
    return nil
  if node.kind == nnkCommand:
    return nil
  if node.kind in nnkCallKinds and node.len > 0 and
      node[0].kind == nnkSym and node[0].symKind in {nskTemplate, nskMacro}:
    return nil
  if node.kind in nnkCallKinds and node.len > 0 and
      eqIdent(node[0], "typeof"):
    return nil
  if node.kind != nnkSym and node.kind notin nnkCallKinds and
      node.kind notin nnkLiterals and
      node.kind notin {nnkObjConstr, nnkPar, nnkDotExpr, nnkCast, nnkConv}:
    return nil

  try:
    let type_inst = node.getTypeInst
    if type_inst.kind == nnkBracketExpr and type_inst.len == 3 and
        type_inst[0].kind == nnkSym and type_inst[0] == flow_spec_symbol:
      return type_inst
  except CatchableError:
    discard
  nil

proc register_flow_type(types: var seq[NimNode]; type_node: NimNode) =
  for known in types:
    if sameType(known, type_node):
      return
  types.add type_node

proc field_value(node: NimNode; name: string): NimNode =
  if node.kind notin {nnkObjConstr, nnkCall}:
    return nil
  for child in node:
    if child.kind == nnkExprColonExpr and child.len == 2 and
        child[0].repr == name:
      return child[1]
  nil

proc is_named(node: NimNode; name: string): bool =
  node.kind in {nnkIdent, nnkSym, nnkAccQuoted} and node.repr == name

proc is_flow_ir_lift(node: NimNode): bool =
  if node.kind notin {nnkObjConstr, nnkCall}:
    return false
  let kind = node.field_value("kind")
  if kind.isNil:
    return false
  if kind.is_named("firk_lift"):
    return true
  kind.kind in {
    nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit
  } and kind.intVal == ord(firk_lift)

proc first_flow_spec_type(node, flow_spec_symbol: NimNode): NimNode =
  let direct = flow_spec_type(node, flow_spec_symbol)
  if not direct.isNil:
    return direct
  for child in node:
    result = first_flow_spec_type(child, flow_spec_symbol)
    if not result.isNil:
      return

proc same_lift(left, right: LiftOccurrence): bool =
  left.pattern == right.pattern and
    sameType(left.outer_domain, right.outer_domain) and
    sameType(left.outer_codomain, right.outer_codomain) and
    sameType(left.inner_domain, right.inner_domain) and
    sameType(left.inner_codomain, right.inner_codomain)

proc collect_lifts(
    node: NimNode;
    flow_spec_symbol: NimNode;
    lifts: var seq[LiftOccurrence]
) =
  let flow_type = flow_spec_type(node, flow_spec_symbol)
  if not flow_type.isNil:
    let ir = node.field_value("ir")
    if not ir.isNil and ir.is_flow_ir_lift:
      let pattern_node = ir.field_value("pattern")
      let inner = ir.field_value("inner")
      if pattern_node.isNil or inner.isNil or pattern_node.kind notin {
          nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
        error("malformed lift IR", node)
      let inner_type = first_flow_spec_type(inner, flow_spec_symbol)
      if inner_type.isNil:
        error("lift inner flow type is unavailable", inner)
      let occurrence = LiftOccurrence(
        pattern: pattern_node.strVal,
        tree: parse_lift_pattern(parseExpr(pattern_node.strVal)),
        outer_domain: copyNimTree(flow_type[1]),
        outer_codomain: copyNimTree(flow_type[2]),
        inner_domain: copyNimTree(inner_type[1]),
        inner_codomain: copyNimTree(inner_type[2]))
      var known = false
      for prior in lifts:
        if prior.same_lift(occurrence):
          known = true
          break
      if not known:
        lifts.add occurrence

  for child in node:
    collect_lifts(child, flow_spec_symbol, lifts)

proc walk_flow_specs(node: NimNode; context: var FlowWalkContext) =
  let flow_type = flow_spec_type(node, context.flow_spec_symbol)
  if not flow_type.isNil:
    inc context.encountered
    case context.phase
    of fwpGatherTypes:
      register_flow_type(context.flow_types, flow_type[1])
      register_flow_type(context.flow_types, flow_type[2])
      echo "FlowSpec node=", $node.kind,
        " type=", flow_type.repr,
        " domain=", flow_type[1].repr,
        " codomain=", flow_type[2].repr
    of fwpProcess:
      # Lowering will consume canonical expression roots. Typed AST wrappers
      # can expose one source occurrence as Sym, ObjConstr, and Call.
      discard

  for child in node:
    walk_flow_specs(child, context)

proc make_vecherinka_artifact_type(
    flow_types: seq[NimNode];
    registry: var ArtifactRegistry
): NimNode =
  let kind_name = ident("VecherinkaArtifactKind")
  let artifact_name = ident("VecherinkaArtifact")
  registry.kind_name = kind_name
  registry.artifact_name = artifact_name
  let kind_type = newTree(nnkEnumTy, newEmptyNode())
  let variant = newTree(nnkRecCase,
    newTree(nnkIdentDefs, ident("kind"), kind_name, newEmptyNode()))

  for index, flow_type in flow_types:
    let kind = ident("vak_" & $index)
    let value = ident("value_" & $index)
    registry.types.add ArtifactTypeInfo(
      type_expr: copyNimTree(flow_type),
      kind_name: kind,
      value_name: value)
    kind_type.add(kind)
    variant.add(newTree(nnkOfBranch, kind,
      newTree(nnkRecList,
        newTree(nnkIdentDefs, value, flow_type, newEmptyNode()))))

  newTree(nnkTypeSection,
    newTree(nnkTypeDef, kind_name, newEmptyNode(), kind_type),
    newTree(nnkTypeDef, artifact_name, newEmptyNode(),
      newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(),
        newTree(nnkRecList, variant))))

proc artifact_info(
    registry: ArtifactRegistry;
    type_expr: NimNode
): ArtifactTypeInfo =
  for info in registry.types:
    if sameType(info.type_expr, type_expr):
      return info
  error("lift type is missing from Artifact registry: " & type_expr.repr,
    type_expr)

proc is_void_type(type_expr: NimNode): bool =
  type_expr.is_named("void")

proc emit_artifact_pack(
    registry: ArtifactRegistry;
    type_expr, value: NimNode
): NimNode =
  let info = registry.artifact_info(type_expr)
  let artifact_name = registry.artifact_name
  let kind_name = info.kind_name
  let value_name = info.value_name
  let source = copyNimTree(value)
  quote do:
    `artifact_name`(kind: `kind_name`, `value_name`: `source`)

proc emit_artifact_unpack(
    registry: ArtifactRegistry;
    type_expr, artifact: NimNode
): NimNode =
  let info = registry.artifact_info(type_expr)
  let checked = genSym(nskLet, "artifact")
  let source = copyNimTree(artifact)
  let kind_name = info.kind_name
  let value_name = info.value_name
  quote do:
    block:
      let `checked` = `source`
      doAssert `checked`.kind == `kind_name`
      `checked`.`value_name`

proc make_fake_work_type(registry: var ArtifactRegistry): NimNode =
  ## Runtime work graph does not exist yet; keep generated work shape small.
  registry.work_name = genSym(nskType, "FakeWork")
  let work_name = registry.work_name
  let artifact_name = registry.artifact_name
  quote do:
    type
      `work_name` = object
        result_index*: int
        input*: `artifact_name`

proc lifted_node_types(
    tree: LiftPatternTree;
    id: LiftPatternId;
    inner_domain, inner_codomain: NimNode
): tuple[input_type, output_type: NimNode] =
  let pattern = tree.node(id)
  case pattern.kind
  of lpk_type:
    result = (pattern.type_expression, pattern.type_expression)
  of lpk_here:
    result = (copyNimTree(inner_domain), copyNimTree(inner_codomain))
  of lpk_seq, lpk_option:
    let child = lifted_node_types(tree, pattern.child_id(),
      inner_domain, inner_codomain)
    let wrapper = if pattern.kind == lpk_seq: "seq" else: "Option"
    result = (
      newTree(nnkBracketExpr, ident(wrapper), child.input_type),
      newTree(nnkBracketExpr, ident(wrapper), child.output_type))
  of lpk_tuple:
    result.input_type = newTree(nnkTupleConstr)
    result.output_type = newTree(nnkTupleConstr)
    for index in 0 ..< pattern.tuple_item_count:
      let item = pattern.tuple_item(index)
      let child = lifted_node_types(tree, item.pattern_id,
        inner_domain, inner_codomain)
      if item.name.len == 0:
        result.input_type.add child.input_type
        result.output_type.add child.output_type
      else:
        result.input_type.add newTree(nnkExprColonExpr,
          ident(item.name), child.input_type)
        result.output_type.add newTree(nnkExprColonExpr,
          ident(item.name), child.output_type)
  of lpk_object:
    result = (pattern.type_expression, pattern.type_expression)

proc node_here_count(tree: LiftPatternTree; id: LiftPatternId): int =
  let pattern = tree.node(id)
  case pattern.kind
  of lpk_here:
    result = 1
  of lpk_type:
    result = 0
  of lpk_seq, lpk_option:
    result = tree.node_here_count(pattern.child_id())
  of lpk_tuple:
    for index in 0 ..< pattern.tuple_item_count:
      let item = pattern.tuple_item(index)
      result += tree.node_here_count(item.pattern_id)
  of lpk_object:
    for index in 0 ..< pattern.object_member_count:
      let member = pattern.object_member(index)
      result += tree.node_here_count(member.pattern_id)

proc tuple_value(value: NimNode; item: LiftPatternItem; index: int): NimNode =
  if item.name.len == 0:
    newTree(nnkBracketExpr, value, newLit(index))
  else:
    newTree(nnkDotExpr, value, ident(item.name))

proc object_value(value: NimNode; name: string): NimNode =
  newTree(nnkDotExpr, value, ident(name))

proc emit_destructure(
    tree: LiftPatternTree;
    id: LiftPatternId;
    value: NimNode;
    state: var LiftEmitState;
    registry: ArtifactRegistry;
    input_type: NimNode
): NimNode =
  ## Runtime loops mirror `emit_construct`, so `result_index` remains stable
  ## across dynamic sequence and Option cardinality.
  let pattern = tree.node(id)
  case pattern.kind
  of lpk_type:
    result = quote do:
      discard
  of lpk_here:
    let index = genSym(nskLet, "result_index")
    let work_name = registry.work_name
    let next_index = state.next_index
    let works = state.works
    let source = copyNimTree(value)
    let packed = registry.emit_artifact_pack(input_type, source)
    result = quote do:
      let `index` = `next_index`
      inc `next_index`
      `works`.add `work_name`(
        result_index: `index`,
        input: `packed`)
  of lpk_seq:
    let item = genSym(nskForVar, "item")
    let body = emit_destructure(tree, pattern.child_id(), item, state,
      registry, input_type)
    let source = copyNimTree(value)
    result = quote do:
      for `item` in `source`:
        `body`
  of lpk_option:
    let item = genSym(nskLet, "some_value")
    let body = emit_destructure(tree, pattern.child_id(), item, state,
      registry, input_type)
    let source = copyNimTree(value)
    result = quote do:
      if `source`.isSome:
        let `item` = `source`.get
        `body`
  of lpk_tuple:
    result = newStmtList()
    for index in 0 ..< pattern.tuple_item_count:
      let item = pattern.tuple_item(index)
      result.add emit_destructure(tree, item.pattern_id,
        tuple_value(copyNimTree(value), item, index), state,
        registry, input_type)
  of lpk_object:
    result = newStmtList()
    for index in 0 ..< pattern.object_member_count:
      let member = pattern.object_member(index)
      result.add emit_destructure(tree, member.pattern_id,
        object_value(copyNimTree(value), member.name), state,
        registry, input_type)

proc emit_construct(
    tree: LiftPatternTree;
    id: LiftPatternId;
    original: NimNode;
    state: var LiftEmitState;
    registry: ArtifactRegistry;
    input_type, output_type: NimNode
): NimNode =
  ## Revisit retained input shape; never infer structure from result count.
  let pattern = tree.node(id)
  case pattern.kind
  of lpk_type:
    result = copyNimTree(original)
  of lpk_here:
    let index = genSym(nskLet, "result_index")
    let results = state.results
    let next_index = state.next_index
    let value = newTree(nnkBracketExpr, results, index)
    let unpacked = registry.emit_artifact_unpack(output_type, value)
    result = quote do:
      let `index` = `next_index`
      inc `next_index`
      `unpacked`
  of lpk_seq:
    let item = genSym(nskForVar, "item")
    let output = genSym(nskVar, "output")
    let body = emit_construct(tree, pattern.child_id(), item, state,
      registry, input_type, output_type)
    let source = copyNimTree(original)
    let sequence_type = lifted_node_types(tree, id,
      input_type, output_type).output_type
    result = quote do:
      block:
        var `output`: `sequence_type`
        for `item` in `source`:
          `output`.add(`body`)
        `output`
  of lpk_option:
    let child_types = lifted_node_types(tree, pattern.child_id(),
      input_type, output_type)
    let source = copyNimTree(original)
    let child_source = newTree(nnkDotExpr, source, ident("get"))
    let body = emit_construct(tree, pattern.child_id(), child_source, state,
      registry, input_type, output_type)
    let child_output_type = child_types.output_type
    result = quote do:
      if `source`.isSome:
        some(`body`)
      else:
        none[`child_output_type`]()
  of lpk_tuple:
    result = newTree(nnkTupleConstr)
    for index in 0 ..< pattern.tuple_item_count:
      let item = pattern.tuple_item(index)
      let source = tuple_value(copyNimTree(original), item, index)
      let child = emit_construct(tree, item.pattern_id, source, state,
        registry, input_type, output_type)
      if item.name.len == 0:
        result.add child
      else:
        result.add newTree(nnkExprColonExpr, ident(item.name), child)
  of lpk_object:
    let output = genSym(nskVar, "output")
    result = newStmtList()
    result.add quote do:
      var `output` = `original`
    for index in 0 ..< pattern.object_member_count:
      let member = pattern.object_member(index)
      if tree.node_here_count(member.pattern_id) == 0:
        continue
      let source = object_value(copyNimTree(original), member.name)
      let body = emit_construct(tree, member.pattern_id, source, state,
        registry, input_type, output_type)
      let field = ident(member.name)
      result.add quote do:
        `output`.`field` = `body`
    result.add output

proc make_lift_helpers(
    occurrence: LiftOccurrence;
    registry: ArtifactRegistry
): NimNode =
  if occurrence.inner_domain.is_void_type or occurrence.inner_codomain.is_void_type:
    error("lift inner flow must have non-void endpoints")
  let destructure_name = genSym(nskProc, "lift_destructure")
  let construct_name = genSym(nskProc, "lift_construct")
  let artifact_name = registry.artifact_name
  let work_name = registry.work_name
  let outer_domain = copyNimTree(occurrence.outer_domain)
  let outer_codomain = copyNimTree(occurrence.outer_codomain)
  let input = genSym(nskParam, "input")
  let original = genSym(nskLet, "original")
  let next_index = genSym(nskVar, "next_index")
  let unpack_input = registry.emit_artifact_unpack(
    occurrence.outer_domain, input)
  var destructure_state = LiftEmitState(
    next_index: next_index,
    works: ident("result"))
  let destructure_body = emit_destructure(occurrence.tree,
    occurrence.tree.root_id, original, destructure_state, registry,
    occurrence.inner_domain)

  let results = genSym(nskParam, "results")
  let original_input = genSym(nskParam, "original")
  let construct_next_index = genSym(nskVar, "next_index")
  var construct_state = LiftEmitState(
    next_index: construct_next_index,
    results: results)
  let construct_body = emit_construct(occurrence.tree,
    occurrence.tree.root_id, original_input, construct_state, registry,
    occurrence.inner_domain, occurrence.inner_codomain)

  result = newStmtList()
  result.add quote do:
    proc `destructure_name`(
        `input`: `artifact_name`): seq[`work_name`] {.nimcall.} =
      let `original` = `unpack_input`
      var `next_index` = 0
      `destructure_body`
  result.add quote do:
    proc `construct_name`(
        `results`: seq[`artifact_name`];
        `original_input`: `outer_domain`):
        `outer_codomain` {.nimcall.} =
      var `construct_next_index` = 0
      `construct_body`

macro vecherinka_runtime*(body: typed): untyped =
  var context = FlowWalkContext(
    phase: fwpGatherTypes,
    flow_spec_symbol: bindSym("FlowSpec"))
  walk_flow_specs(body, context)
  echo "FlowSpec types gathered=", context.flow_types.len

  context.phase = fwpProcess
  context.encountered = 0
  walk_flow_specs(body, context)
  echo "FlowSpec nodes processed=", context.encountered

  var lifts: seq[LiftOccurrence]
  collect_lifts(body, context.flow_spec_symbol, lifts)

  var registry: ArtifactRegistry
  result = newStmtList(make_vecherinka_artifact_type(
    context.flow_types, registry))
  if lifts.len > 0:
    result.add make_fake_work_type(registry)
    for lift in lifts:
      result.add make_lift_helpers(lift, registry)
  result.add(body)

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
    vecherinka_runtime:
      `refs`
