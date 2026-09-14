## Typed source syntax, compile-time IR, and lowering.
## Included by `vecherinka.nim`; import the façade for public use.

import std/[macros, assertions, options, strutils]
import fusion/matching
import it_projection, lift_pattern_typed
import schematic

type
  FlowIRKind* = enum
    firk_ref,
    firk_empty,
    firk_so,
    firk_it,
    firk_lift
  FlowIR* = ref object
    case kind*: FlowIRKind:
    of firk_ref:
      id*: int
      entry*: bool
    of firk_it:
      path*: ItPath
    of firk_lift:
      pattern*: string
      inner*: FlowIR
    else: discard
  FlowSpec*[A, B] = object
    ir*: FlowIR
  PartialModelCallSyntax*[A, B] = object
  here* = object
  PartialLiftSyntax*[Pattern: static string] = object
  ## Relative path resolved against RuntimeContext.runtime_dir.
  Location* = distinct string

template flow_ir*(id: int, entry: bool) {.pragma.}
template `~>`*(A, B: untyped): untyped = FlowSpec[A, B]
template flow_spec_symbol: NimNode = bindSym("FlowSpec")
template partial_model_call_symbol: NimNode = bindSym("PartialModelCallSyntax")
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
  doAssert args.len >= 1, "args.len must be >= 1"
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

proc so_syntax*[A, B](
    fn: proc(input: A): FlowSpec[void, B]
): FlowSpec[A, B] =
  FlowSpec[A, B](ir: FlowIR(kind: firk_so))

proc so_syntax*[A, B](
    fn: proc(input: A; working_dir: Path): FlowSpec[void, B]
): FlowSpec[A, B] =
  FlowSpec[A, B](ir: FlowIR(kind: firk_so))

macro so*(domain, codomain, pattern, body: untyped): untyped =
  let parameter = ident(pattern.strVal)
  result = quote do:
    so_syntax[`domain`, `codomain`](proc (`parameter`: `domain`):
      FlowSpec[void, `codomain`] = `body`)

macro so*(domain, codomain, pattern, working_dir_name, body: untyped): untyped =
  let parameter = ident(pattern.strVal)
  let working_dir_parameter = ident(working_dir_name.strVal)
  result = quote do:
    so_syntax[`domain`, `codomain`](proc (`parameter`: `domain`;
        `working_dir_parameter`: Path):
      FlowSpec[void, `codomain`] = `body`)

macro project_it(value: typed; path: static[ItPath]; depth: static[int] = 0): untyped =
  if path.groups.len == 0:
    return value
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
      doAssert shape.kind in {nnkTupleTy, nnkTupleConstr},
        "it range requires a tuple"
      let arity = shape.len
      doAssert selector.first >= 0 and selector.last < arity,
        "it range is outside tuple bounds"
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
  ArtifactTypeInfo = object
    type_expr: NimNode
    kind_name: NimNode
    value_name: NimNode

  ArtifactRegistry = object
    kind_name: NimNode
    artifact_name: NimNode
    types: seq[ArtifactTypeInfo]

  FlowWalkContext = object
    flow_types: seq[NimNode]
    flow_refs: seq[FlowRefInfo]
    flow_procs: seq[FlowProcInfo]
    flow_pairs: seq[FlowPair]
    artifact_registry: ArtifactRegistry
    prompt_templates: NimNode

  FlowRefInfo = object
    id: int
    name: string
    symbol: NimNode
    flow_type: NimNode
    entry: bool

  FlowProcInfo = object
    id: int
    body: NimNode
    flow_type: NimNode

  FlowPair = object
    ref_info: FlowRefInfo
    proc_info: FlowProcInfo

  LoweredFlow = object
    head: NimNode
    tail: NimNode

proc replace_symbol(
    node, original, replacement: NimNode
): NimNode =
  ## Replace only references bound to original symbol; same-spelled locals stay intact.
  if node.kind == nnkSym and node == original:
    return copyNimTree(replacement)
  result = copyNimTree(node)
  for index in 0 ..< node.len:
    result[index] = replace_symbol(node[index], original, replacement)

type
  LiftEmitState = object
    ## Both emitters advance one shared preorder cursor per `here`.
    next_index: NimNode
    works: NimNode
    results: NimNode

proc flow_spec_type(node: NimNode): NimNode =
  ## `getTypeInst` is only safe on typed expression nodes. Type syntax,
  ## pragmas, and some macro/template calls have no type and fail hard.
  if node.kind == nnkInfix and node.len > 0 and eqIdent(node[0], "~>"):
    return nil
  if node.kind == nnkSym and node.symKind == nskResult:
    return nil
  if node.kind == nnkSym and node.symKind notin {
      nskParam, nskTemp, nskVar, nskLet, nskConst, nskResult, nskForVar}:
    return nil
  if node.kind == nnkCommand:
    return nil
  if node.kind in nnkCallKinds and node.len > 0 and
      node[0].kind == nnkSym and node[0].symKind in {nskTemplate, nskMacro}:
    return nil
  if node.kind in nnkCallKinds and node.len > 0 and
      node[0].kind == nnkSym and node[0].symKind == nskProc and
      not eqIdent(node[0], "pure") and
      not eqIdent(node[0], "fanout") and
      not eqIdent(node[0], "so_syntax") and
      not eqIdent(node[0], ">>>") and
      not eqIdent(node[0], "()"):
    ## Ordinary callback calls may still be semantically untyped here;
    ## only known flow constructors need early type inspection.
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
    if (BracketExpr([
        @head is Sym(),
        _,
        _
      ]) ?= type_inst) and head == flow_spec_symbol:
      return type_inst
  except CatchableError:
    discard
  nil

proc type_inst_or_nil(node: NimNode): NimNode =
  ## Type queries are valid only for semantically typed expressions.
  try:
    result = node.getTypeInst
  except CatchableError:
    result = nil

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

proc is_flow_ir_kind(node: NimNode; expected: FlowIRKind): bool =
  if node.kind notin {nnkObjConstr, nnkCall}:
    return false
  let kind = node.field_value("kind")
  if kind.isNil:
    return false
  if kind.is_named($expected):
    return true
  kind.kind in {
    nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit
  } and kind.intVal == ord(expected)

proc is_flow_ir_lift(node: NimNode): bool =
  is_flow_ir_kind(node, firk_lift)

proc is_flow_ir_it(node: NimNode): bool =
  is_flow_ir_kind(node, firk_it)

proc flow_ir_ref_id(node: NimNode; id: var int): bool =
  if node.kind notin {nnkObjConstr, nnkCall}:
    return false
  let kind = node.field_value("kind")
  let id_node = node.field_value("id")
  if kind.isNil or id_node.isNil or
      (not kind.is_named("firk_ref") and
       (kind.kind notin {
          nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit
        } or kind.intVal != ord(firk_ref))) or
      id_node.kind notin {
        nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit
      }:
    return false
  id = id_node.intVal
  true

proc flow_ref_info(node: NimNode; info: var FlowRefInfo): bool =
  if (IdentDefs([
      @name is Sym(),
      _,
      @initializer
    ]) ?= node):
    let flow_type = flow_spec_type(initializer)
    let ir = initializer.field_value("ir")
    var id: int
    if not flow_type.isNil and not ir.isNil and flow_ir_ref_id(ir, id):
      let entry_node = ir.field_value("entry")
      let entry = not entry_node.isNil and entry_node.repr == "true"
      info = FlowRefInfo(id: id, name: name.strVal, symbol: name,
        flow_type: copyNimTree(flow_type), entry: entry)
      return true
  false

proc flow_ir_proc_id(node: NimNode; id: var int): bool =
  if node.kind != nnkProcDef:
    return false
  for child in node:
    if child.kind != nnkPragma:
      continue
    for pragma in child:
      if pragma.kind notin {nnkCall, nnkCommand} or pragma.len < 2 or
          not eqIdent(pragma[0], "flow_ir") or
          pragma[1].kind notin {
            nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit
          }:
        continue
      id = pragma[1].intVal
      return true
  false

proc first_flow_spec_type(node: NimNode): NimNode =
  let direct = flow_spec_type(node)
  if not direct.isNil:
    return direct
  for child in node:
    result = first_flow_spec_type(child)
    if not result.isNil:
      return

proc walk_flow_specs(node: NimNode; context: var FlowWalkContext) =
  let flow_type = flow_spec_type(node)
  if not flow_type.isNil:
    ## A void codomain has no artifact-registry slot. Reject it here, at the
    ## FlowSpec contract boundary, instead of letting lowering fail later in
    ## model_output_kind. Void domains remain valid for no-input flows.
    if flow_type[2].is_named("void"):
      error("FlowSpec codomain cannot be void", node)
    if not flow_type[1].is_named("void"):
      register_flow_type(context.flow_types, flow_type[1])
    register_flow_type(context.flow_types, flow_type[2])

  for child in node:
    walk_flow_specs(child, context)

proc model_call_parts(
    node, flow_type: NimNode;
    profile, prompt: var NimNode
): bool =
  ## Fusion matching handles the stable typed call-tree shape. Compiler type
  ## identity validates the generic endpoints and prompt overload.
  if (Call([
      @head_node is Sym(),
      Call([
        @partial_head_node is Sym(),
        @matched_profile,
        _,
        _
      ]),
      @matched_prompt
    ]) ?= node):
    if head_node.symKind != nskProc or not eqIdent(head_node, "()"):
      return false
    if partial_head_node.symKind != nskProc or
        not eqIdent(partial_head_node, "[]"):
      return false
    if flow_type.isNil or flow_type.kind != nnkBracketExpr or
        flow_type.len != 3:
      return false

    let partial_type = type_inst_or_nil(node[1])
    if partial_type.isNil or partial_type.kind != nnkBracketExpr or
        partial_type.len != 3 or partial_type[0].kind != nnkSym or
        partial_type[0] != partial_model_call_symbol:
      return false

    if not sameType(partial_type[1], flow_type[1]) or
        not sameType(partial_type[2], flow_type[2]):
      return false

    let prompt_type = type_inst_or_nil(matched_prompt)
    if prompt_type.isNil or not sameType(prompt_type, bindSym("string")):
      return false

    profile = matched_profile
    prompt = matched_prompt
    true
  else:
    false

const prompt_substitution_names = [
  "task", "input", "working_dir", "runtime_dir", "model", "effort"
]

proc prompt_name_start(value: char): bool =
  value in {'a'..'z', 'A'..'Z', '_'}

proc prompt_name_char(value: char): bool =
  prompt_name_start(value) or value in {'0'..'9'}

proc known_prompt_name(name: string): bool =
  for known in prompt_substitution_names:
    if cmpIgnoreStyle(name, known) == 0:
      return true
  false

proc contains_prompt_name(names: seq[string]; wanted: string): bool =
  for name in names:
    if cmpIgnoreStyle(name, wanted) == 0:
      return true
  false

proc scan_prompt_names(text: string): tuple[names: seq[string], issue: string] =
  ## Scan exactly the named subset accepted by `strutils.format`.
  var index = 0
  while index < text.len:
    if text[index] != '$':
      inc index
      continue
    if index + 1 >= text.len:
      return (result.names, "trailing '$'")
    let next = text[index + 1]
    if next == '$':
      inc index, 2
      continue
    if not prompt_name_start(next):
      return (result.names,
        "expected named placeholder after '$' at index " & $index)
    var last = index + 2
    while last < text.len and prompt_name_char(text[last]):
      inc last
    result.names.add(text.substr(index + 1, last - 1))
    index = last

macro checked_prompt*(prompt_text: untyped; required: varargs[untyped]): untyped =
  if prompt_text.kind notin {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
    error("checked_prompt requires a string literal", prompt_text)
  let text = prompt_text.strVal
  let scanned = scan_prompt_names(text)
  if scanned.issue.len != 0:
    error("invalid checked_prompt: " & scanned.issue, prompt_text)
  for name in scanned.names:
    if not known_prompt_name(name):
      error("unknown checked_prompt substitution: $" & name, prompt_text)
  for expected in required:
    if expected.kind notin {nnkStrLit, nnkRStrLit, nnkTripleStrLit}:
      error("checked_prompt names must be string literals", expected)
    let name = expected.strVal
    if not known_prompt_name(name):
      error("unknown checked_prompt required substitution: $" & name, expected)
    if not contains_prompt_name(scanned.names, name):
      error("checked_prompt missing required substitution: $" & name, prompt_text)
  newLit(text)

proc fanout_parts(
    node, flow_type: NimNode;
    branches: var NimNode
): bool =
  if (Call([
      @head_node is Sym(),
      @matched_branches
    ]) ?= node):
    if head_node.symKind != nskProc or not eqIdent(head_node, "fanout") or
        matched_branches.kind != nnkTupleConstr:
      return false
    doAssert matched_branches.len > 0 and flow_type.kind == nnkBracketExpr,
      "fanout requires non-empty typed FlowSpec branches"
    branches = matched_branches
    return true
  false

proc pure_parts(
    node, flow_type: NimNode;
    value: var NimNode
): bool =
  if (Call([
      @head_node is Sym(),
      @matched_value
    ]) ?= node):
    if head_node.symKind != nskProc or not eqIdent(head_node, "pure"):
      return false
    if flow_type.kind != nnkBracketExpr or flow_type.len != 3 or
        not flow_type[1].is_named("void"):
      return false
    value = matched_value
    return true
  false

proc so_parts(
    node, flow_type: NimNode;
    lambda: var NimNode
): bool =
  if (Call([
      @head_node is Sym(),
      @matched_lambda
    ]) ?= node):
    if head_node.symKind != nskProc or not eqIdent(head_node, "so_syntax"):
      return false
    if flow_type.kind != nnkBracketExpr or flow_type.len != 3:
      return false
    var candidate = matched_lambda
    while candidate.kind in {nnkHiddenStdConv, nnkHiddenCallConv}:
      doAssert candidate.len == 2, "malformed so callback conversion"
      candidate = candidate[1]
    doAssert candidate.kind == nnkLambda, "so_syntax requires callback proc"
    lambda = candidate
    return true
  false

proc so_lambda_parts(
    lambda: NimNode;
    parameter, input_type, working_dir_parameter, body: var NimNode
): bool =
  if lambda.kind != nnkLambda or lambda.len < 7:
    return false
  let formals = lambda[3]
  if formals.kind != nnkFormalParams or formals.len notin 2 .. 3:
    return false
  if formals[1].kind != nnkIdentDefs or formals[1].len != 3 or
      formals[1][0].kind != nnkSym:
    return false
  parameter = formals[1][0]
  input_type = formals[1][1]
  working_dir_parameter = newEmptyNode()
  if formals.len == 3:
    if formals[2].kind != nnkIdentDefs or formals[2].len != 3 or
        formals[2][0].kind != nnkSym:
      return false
    working_dir_parameter = formals[2][0]
  if lambda[6].kind != nnkAsgn or lambda[6].len != 2:
    return false
  body = lambda[6][1]
  true

proc emit_artifact_pack(
    registry: ArtifactRegistry;
    type_expr, value: NimNode
): NimNode

proc emit_artifact_unpack(
    registry: ArtifactRegistry;
    type_expr, artifact: NimNode
): NimNode

proc artifact_info(
    registry: ArtifactRegistry;
    type_expr: NimNode
): ArtifactTypeInfo

proc is_void_type(type_expr: NimNode): bool

type
  ArtifactNodeKind = enum
    ank_inline
    ank_location
    ank_object
    ank_variant
    ank_tuple
    ank_seq
    ank_option
    ank_option_none

  ArtifactNode = ref object
    kind: ArtifactNodeKind
    type_expr: NimNode
    needs_runtime_cast: bool
    fixed_array: bool
    fixed_length: int
    fixed_lower_bound: int
    type_name: string
    tag_name: NimNode
    fields: seq[ArtifactField]
    branches: seq[ArtifactBranch]
    element: ArtifactNode

  ArtifactField = object
    name: string
    selector: NimNode
    node: ArtifactNode

  ArtifactBranch = object
    tags: seq[NimNode]
    is_else: bool
    fields: seq[ArtifactField]

  ArtifactWalkCallback[T] = proc(
    node: ArtifactNode;
    value, path: NimNode;
    state: var T
  ): NimNode

proc artifact_type_inst(type_node: NimNode): NimNode =
  let type_inst = type_node.getTypeInst
  if type_inst.kind in {nnkTupleTy, nnkTupleConstr}:
    return copyNimTree(type_inst)
  if type_inst.kind == nnkBracketExpr and type_inst.len == 2 and
      is_named(type_inst[0], "typeDesc"):
    return copyNimTree(type_inst[1])
  copyNimTree(type_inst)

proc artifact_unwrapped_type(type_node: NimNode): NimNode =
  result = artifact_type_inst(type_node)
  while result.kind notin {nnkTupleTy, nnkTupleConstr} and
      result.getTypeImpl.kind == nnkDistinctTy:
    result = artifact_type_inst(result.getTypeImpl[0])

proc artifact_is_location(type_node: NimNode): bool =
  var current = artifact_type_inst(type_node)
  while true:
    if is_named(current, "Location"):
      return true
    if current.kind in {nnkTupleTy, nnkTupleConstr}:
      return false
    let type_impl = current.getTypeImpl
    if type_impl.kind != nnkDistinctTy:
      return false
    current = artifact_type_inst(type_impl[0])

proc artifact_is_inline(type_node: NimNode): bool =
  let type_inst = artifact_unwrapped_type(type_node)
  if type_inst.kind in {nnkTupleTy, nnkTupleConstr}:
    return false
  case type_inst.repr
  of "bool", "char", "string", "cstring",
     "int", "int8", "int16", "int32", "int64",
     "uint", "uint8", "uint16", "uint32", "uint64",
     "float32", "float64":
    true
  else:
    let impl = type_inst.getTypeImpl
    impl.kind == nnkEnumTy or
      (impl.kind == nnkBracketExpr and impl.len == 2 and
        is_named(impl[0], "range"))

proc artifact_field_name(field: NimNode; index: int): NimNode =
  if field[index].kind == nnkPostfix:
    field[index][1]
  else:
    field[index]

proc new_artifact_node(kind: ArtifactNodeKind): ArtifactNode =
  new(result)
  result.kind = kind

proc artifact_is_option_shape(shape: NimNode): bool =
  # Alias spelling can disappear in Nim's semantic type implementation. Option
  # keeps canonical `val`/`has` fields; constrain match to that exact shape.
  if shape.kind != nnkObjectTy or shape.len < 3 or shape[2].len != 1:
    return false
  let fields = shape[2][0]
  fields.kind == nnkRecList and fields.len == 2 and
    fields[0].kind == nnkIdentDefs and fields[1].kind == nnkIdentDefs and
    fields[0].len == 3 and fields[1].len == 3 and
    fields[0][0].strVal == "val" and fields[1][0].strVal == "has" and
    fields[1][1].repr == "bool"

proc artifact_array_bounds(index_type: NimNode): tuple[lower, upper: int] =
  ## Nim permits either an explicit ordinal range or an ordinal index type.
  ## Both define contiguous ordinals, so one pair of bounds suffices for
  ## logical paths and fixed-array reconstruction.
  if index_type.kind == nnkInfix and index_type.len == 3 and
      is_named(index_type[0], ".."):
    return (index_type[1].intVal.int, index_type[2].intVal.int)
  case index_type.repr
  of "bool": return (0, 1)
  of "char": return (0, 255)
  of "int8": return (-128, 127)
  of "uint8": return (0, 255)
  of "int16": return (-32768, 32767)
  of "uint16": return (0, 65535)
  of "int32": return (int low(int32), int high(int32))
  of "uint32": return (0, int high(uint32))
  of "int": return (int low(int), int high(int))
  else:
    let impl = index_type.getTypeImpl
    if impl.kind == nnkEnumTy:
      return (0, int(impl.len) - 1)
    if impl.kind == nnkBracketExpr and impl.len == 2 and
        is_named(impl[0], "range"):
      return artifact_array_bounds(impl[1])
  error("artifact walker cannot inspect fixed array index type " &
    index_type.repr, index_type)

proc artifact_tree(type_node: NimNode): ArtifactNode

proc artifact_fields(
    fields: NimNode;
    tuple_fields: bool
): seq[ArtifactField] =
  if tuple_fields and fields.kind in {nnkTupleTy, nnkTupleConstr}:
    for index, field in fields:
      if field.kind == nnkExprColonExpr and field.len == 2:
        result.add(ArtifactField(
          name: field[0].repr,
          selector: copyNimTree(field[0]),
          node: artifact_tree(field[1])))
      elif field.kind == nnkIdentDefs and field.len >= 3:
        # Compiler semantic trees represent named tuple slots as IdentDefs;
        # source tuple constructors represent them as ExprColonExpr. In both
        # cases each slot has one selector and one child artifact node.
        for name_index in 0 ..< field.len - 2:
          let name_node = artifact_field_name(field, name_index)
          let named = name_node.kind notin {nnkEmpty, nnkIdent} or
            name_node.strVal != "_"
          let name = if named: name_node.strVal else: "[" & $index & "]"
          let selector = if named: copyNimTree(name_node) else: newLit(index)
          result.add(ArtifactField(
            name: name,
            selector: selector,
            node: artifact_tree(field[^2])))
      else:
        result.add(ArtifactField(
          name: "[" & $index & "]",
          selector: newLit(index),
          node: artifact_tree(field)))
    return

  var tuple_index = 0
  for field in fields:
    doAssert field.kind == nnkIdentDefs,
      "artifact walker only supports plain fields"
    for index in 0 ..< field.len - 2:
      let name_node = artifact_field_name(field, index)
      let named = name_node.kind notin {nnkEmpty, nnkIdent} or
        name_node.strVal != "_"
      let name = if named: name_node.strVal else: "[" & $tuple_index & "]"
      let selector = if tuple_fields and not named:
        newLit(tuple_index)
      else:
        copyNimTree(name_node)
      result.add(ArtifactField(
        name: name,
        selector: selector,
        node: artifact_tree(field[^2])))
      inc tuple_index

proc artifact_variant_tree(type_node: NimNode): ArtifactNode =
  let type_impl = artifact_unwrapped_type(type_node).getTypeImpl
  let fields = type_impl[2]
  var variant: NimNode
  var common_fields = newStmtList()
  for field in fields:
    if field.kind == nnkRecCase:
      variant = field
    else:
      common_fields.add(field)

  doAssert not variant.isNil and variant.len >= 2 and
      variant[0].kind == nnkIdentDefs,
    "artifact walker cannot inspect object variant"

  result = new_artifact_node(ank_variant)
  result.type_expr = copyNimTree(artifact_unwrapped_type(type_node))
  result.needs_runtime_cast = not sameType(
    artifact_type_inst(type_node), result.type_expr)
  result.tag_name = copyNimTree(artifact_field_name(variant[0], 0))
  result.fields = artifact_fields(common_fields, false)
  for branch in variant[1 .. ^1]:
    case branch.kind
    of nnkOfBranch:
      var branch_fields = artifact_fields(branch[^1], false)
      for tag_index in 0 ..< branch.len - 1:
        result.branches.add(ArtifactBranch(
          tags: @[copyNimTree(branch[tag_index])],
          is_else: false,
          fields: branch_fields))
    of nnkElse:
      result.branches.add(ArtifactBranch(
        tags: @[],
        is_else: true,
        fields: artifact_fields(branch[0], false)))
    else:
      doAssert false, "artifact walker cannot inspect object variant branch"

proc artifact_tree(type_node: NimNode): ArtifactNode =
  let type_inst = artifact_type_inst(type_node)
  if artifact_is_location(type_inst):
    result = new_artifact_node(ank_location)
    # Keep exact distinct wrapper for typed fixed-array/schema reconstruction;
    # Location's wire representation remains string inside Schematic.
    result.type_expr = copyNimTree(artifact_type_inst(type_node))
    return
  let normalized_type = artifact_unwrapped_type(type_inst)
  let shape = normalized_type.getTypeImpl
  let type_repr = normalized_type.repr
  if type_repr in ["char", "cstring"] or shape.repr in ["char", "cstring"]:
    error("cannot use artifact type " & type_inst.repr &
      "; use Location or seq", type_node)
  if is_named(type_inst, "JsonNode") or
      (type_inst.kind == nnkBracketExpr and is_named(type_inst[0], "Table")) or
      (shape.kind == nnkRefTy and shape.len == 1 and
        shape[0].repr == "JsonNodeObj") or
      (shape.kind == nnkObjectTy and shape.repr.contains("KeyValuePairSeq") and
        shape.repr.contains("counter")):
    error("cannot use artifact type " & type_inst.repr &
      "; use Location or seq", type_node)
  if artifact_is_inline(type_inst):
    result = new_artifact_node(ank_inline)
    result.type_expr = copyNimTree(normalized_type)
    # Nim's sameType can collapse a distinct scalar during semantic typing;
    # spelling still proves the wrapper is present and `$` needs the base.
    result.needs_runtime_cast = not sameType(type_inst, normalized_type) or
      type_inst.repr != normalized_type.repr
    result.type_name = normalized_type.repr
    return

  if type_inst.kind == nnkBracketExpr and type_inst.len == 2:
    if is_named(type_inst[0], "seq"):
      result = new_artifact_node(ank_seq)
      result.type_expr = copyNimTree(type_inst)
      result.element = artifact_tree(type_inst[1])
      return
    if is_named(type_inst[0], "Option"):
      result = new_artifact_node(ank_option)
      result.type_expr = copyNimTree(type_inst)
      result.element = artifact_tree(type_inst[1])
      return

  case shape.kind
  of nnkBracketExpr:
    if shape.len == 2 and is_named(shape[0], "set"):
      error("cannot use artifact type " & type_inst.repr &
        "; use seq", type_node)
    if shape.len == 2 and is_named(shape[0], "seq"):
      result = new_artifact_node(ank_seq)
      result.type_expr = copyNimTree(normalized_type)
      result.needs_runtime_cast = not sameType(type_inst, normalized_type)
      result.element = artifact_tree(shape[1])
      return
    if shape.len == 3 and is_named(shape[0], "array"):
      result = new_artifact_node(ank_seq)
      result.type_expr = copyNimTree(normalized_type)
      result.needs_runtime_cast = not sameType(type_inst, normalized_type)
      result.fixed_array = true
      let bounds = artifact_array_bounds(shape[1])
      result.fixed_lower_bound = bounds.lower
      result.fixed_length = bounds.upper - bounds.lower + 1
      result.element = artifact_tree(shape[2])
      return
    if shape.len == 2 and is_named(shape[0], "Option"):
      result = new_artifact_node(ank_option)
      result.type_expr = copyNimTree(normalized_type)
      result.needs_runtime_cast = not sameType(type_inst, normalized_type)
      result.element = artifact_tree(shape[1])
      return
  of nnkRefTy:
    error("cannot use artifact type " & type_inst.repr &
      "; ref objects are forbidden", type_node)
  of nnkPtrTy:
    error("cannot use artifact type " & type_inst.repr &
      "; pointers are forbidden", type_node)
  of nnkProcTy:
    error("cannot use artifact type " & type_inst.repr &
      "; proc values are forbidden", type_node)
  of nnkObjectTy:
    if artifact_is_option_shape(shape):
      result = new_artifact_node(ank_option)
      result.type_expr = copyNimTree(normalized_type)
      result.needs_runtime_cast = not sameType(type_inst, normalized_type)
      result.element = artifact_tree(shape[2][0][0][^2])
      return
    for field in shape[2]:
      if field.kind == nnkRecCase:
        return artifact_variant_tree(type_inst)
    result = new_artifact_node(ank_object)
    result.type_expr = copyNimTree(normalized_type)
    result.needs_runtime_cast = not sameType(type_inst, normalized_type)
    result.fields = artifact_fields(shape[2], false)
    return
  of nnkTupleTy, nnkTupleConstr:
    result = new_artifact_node(ank_tuple)
    result.type_expr = copyNimTree(normalized_type)
    result.needs_runtime_cast = not sameType(type_inst, normalized_type)
    result.fields = artifact_fields(shape, true)
    return
  else:
    discard
  error("cannot walk artifact type " & type_inst.repr, type_node)

proc append_artifact_field_path(path: NimNode; name: string): NimNode =
  if path.kind == nnkStrLit:
    if path.strVal.len == 0:
      return newLit(name)
    if name.len > 0 and name[0] == '[':
      return newLit(path.strVal & name)
    return newLit(path.strVal & "." & name)
  let separator = if name.len > 0 and name[0] == '[': "" else: "."
  let suffix = newLit(separator & name)
  quote do: `path` & `suffix`

proc append_artifact_sequence_path(
    path, index: NimNode; lower_bound: int = 0): NimNode =
  let path_copy = copyNimTree(path)
  let index_copy = copyNimTree(index)
  let position = if lower_bound == 0:
    quote do: int(`index_copy`)
  else:
    let lower = newLit(lower_bound)
    quote do: int(`index_copy`) - `lower`
  quote do:
    `path_copy` & "[" & $(`position` + 1) & "]"

proc artifact_field_value(value, selector: NimNode): NimNode =
  if selector.kind in {nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit,
      nnkInt64Lit}:
    return newTree(nnkBracketExpr, copyNimTree(value), copyNimTree(selector))
  newTree(nnkDotExpr, copyNimTree(value), copyNimTree(selector))

proc artifact_option_value(value: NimNode): NimNode =
  newCall(bindSym("get"), copyNimTree(value))

proc artifact_runtime_value(node: ArtifactNode; value: NimNode): NimNode =
  if not node.needs_runtime_cast:
    return copyNimTree(value)
  newTree(nnkCast, copyNimTree(node.type_expr), copyNimTree(value))

proc walk_artifact_tree*[T](
    node: ArtifactNode;
    value, path: NimNode;
    state: var T;
    callback: ArtifactWalkCallback[T]
): NimNode =
  ## Callback may replace any node. Nil means structural descent continues.
  let replacement = callback(node, value, path, state)
  if not replacement.isNil:
    return replacement

  case node.kind
  of ank_inline, ank_location, ank_option_none:
    error("artifact walker callback did not handle leaf", value)
  of ank_object, ank_tuple:
    result = newStmtList()
    let runtime_value = artifact_runtime_value(node, value)
    for field in node.fields:
      result.add(walk_artifact_tree(
        field.node,
        artifact_field_value(runtime_value, field.selector),
        append_artifact_field_path(path, field.name),
        state,
        callback))
  of ank_variant:
    result = newStmtList()
    let runtime_value = artifact_runtime_value(node, value)
    for field in node.fields:
      result.add(walk_artifact_tree(
        field.node,
        artifact_field_value(runtime_value, field.selector),
        append_artifact_field_path(path, field.name),
        state,
        callback))
    let case_statement = newTree(
      nnkCaseStmt,
      artifact_field_value(runtime_value, node.tag_name))
    for branch in node.branches:
      var branch_body = newStmtList()
      for field in branch.fields:
        branch_body.add(walk_artifact_tree(
          field.node,
          artifact_field_value(runtime_value, field.selector),
          append_artifact_field_path(path, field.name),
          state,
          callback))
      if branch.is_else:
        case_statement.add(newTree(nnkElse, branch_body))
      else:
        var branch_tags = newNimNode(nnkOfBranch)
        for tag in branch.tags:
          branch_tags.add(copyNimTree(tag))
        branch_tags.add(branch_body)
        case_statement.add(branch_tags)
    result.add(case_statement)
  of ank_seq:
    let index = genSym(nskForVar, "artifact_index")
    let item = genSym(nskForVar, "artifact_item")
    let sequence_value = artifact_runtime_value(node, value)
    result = newTree(
      nnkForStmt,
      index,
      item,
      newCall(bindSym("pairs"), sequence_value),
        walk_artifact_tree(
        node.element,
        item,
        append_artifact_sequence_path(path, index,
          if node.fixed_array: node.fixed_lower_bound else: 0),
        state,
        callback))
  of ank_option:
    let option_value = artifact_runtime_value(node, value)
    let value_copy = copyNimTree(option_value)
    let some_body = walk_artifact_tree(
      node.element,
      artifact_option_value(option_value),
      path,
      state,
      callback)
    let none_node = new_artifact_node(ank_option_none)
    let none_body = callback(none_node, value, path, state)
    doAssert not none_body.isNil,
      "artifact walker callback did not handle absent Option"
    result = quote do:
      if isSome(`value_copy`):
        `some_body`
      else:
        `none_body`

type
  MaterializeEmitState = object
    instructions: NimNode
    runtime_dir: NimNode
    artifact_dir: NimNode
    materialized_names: NimNode

proc materialize_callback(
    node: ArtifactNode;
    value, path: NimNode;
    state: var MaterializeEmitState
): NimNode =
  case node.kind
  of ank_inline:
    # Distinct scalar wrappers have no generic `$`; cast to normalized scalar
    # before formatting, matching transparent composite-wrapper descent.
    let value_copy = artifact_runtime_value(node, value)
    let path_copy = copyNimTree(path)
    let type_name = newLit(node.type_name)
    let instructions = copyNimTree(state.instructions)
    quote do:
      `instructions`.add(
        `path_copy` & ": " & `type_name` & " = " & $(`value_copy`) & "\n")
  of ank_location:
    let copied_name = genSym(nskLet, "materialized_location_name")
    let runtime_dir = copyNimTree(state.runtime_dir)
    let artifact_dir = copyNimTree(state.artifact_dir)
    let materialized_names = copyNimTree(state.materialized_names)
    let instructions = copyNimTree(state.instructions)
    let path_copy = copyNimTree(path)
    let location_value = quote do: cast[string](`value`)
    quote do:
      let `copied_name` = copy_location_payload(
        `runtime_dir`, `artifact_dir`, `location_value`, `materialized_names`)
      `instructions`.add(
        `path_copy` & ": location = " & `location_value` &
        " (materialized as " & `copied_name` & ")\n")
  of ank_option_none:
    let instructions = copyNimTree(state.instructions)
    let path_copy = copyNimTree(path)
    quote do:
      `instructions`.add(`path_copy` & ": Option:none\n")
  else:
    nil

proc emit_input_materializer(type_expr: NimNode): NimNode =
  let input = genSym(nskParam, "materializer_input")
  let runtime_dir = genSym(nskParam, "materializer_runtime_dir")
  let artifact_dir = genSym(nskParam, "materializer_artifact_dir")
  let initial_instructions = genSym(nskParam, "materializer_initial_instructions")
  let instructions = genSym(nskVar, "materialized_instructions")
  let materialized_names = genSym(nskVar, "materialized_names")
  var state = MaterializeEmitState(
    instructions: instructions,
    runtime_dir: runtime_dir,
    artifact_dir: artifact_dir,
    materialized_names: materialized_names)
  let body = walk_artifact_tree(
    artifact_tree(type_expr),
    input,
    newLit("input"),
    state,
    materialize_callback)
  let type_copy = copyNimTree(type_expr)
  quote do:
    (proc (`input`: `type_copy`; `runtime_dir`, `artifact_dir`: Path;
        `initial_instructions`: string): string {.nimcall.} =
      var `instructions` = `initial_instructions`
      var `materialized_names`: seq[string] = @[]
      `body`
      `instructions`
    )

type
  VerifyLocationsEmitState = object
    working_dir: NimNode
    errors: NimNode

proc verify_locations_callback(
    node: ArtifactNode;
    value, path: NimNode;
    state: var VerifyLocationsEmitState
): NimNode =
  case node.kind
  of ank_inline, ank_option_none:
    return newStmtList()
  of ank_location:
    let verification_error = genSym(nskLet, "location_verification_error")
    let working_dir = copyNimTree(state.working_dir)
    let errors = copyNimTree(state.errors)
    let path_copy = copyNimTree(path)
    let location_value = quote do: cast[string](`value`)
    quote do:
      let `verification_error` = verify_location_payload(
        `working_dir`, `location_value`)
      if `verification_error`.len != 0:
        `errors`.add(`path_copy` & ": " & `verification_error` & "\n")
  else:
    nil

template output_schema_of[T](): untyped =
  schemaOf(T)

template output_discriminated_schema[T](discriminator: untyped): untyped =
  discriminated(T, discriminator)

proc model_output_kind(
    registry: ArtifactRegistry;
    output_type: NimNode
): NimNode =
  var output_kind_ordinal = -1
  for index, info in registry.types:
    if sameType(info.type_expr, output_type):
      output_kind_ordinal = index
      break
  doAssert output_kind_ordinal >= 0,
    "model output type is missing from Artifact registry: " & output_type.repr
  newLit(output_kind_ordinal)

proc artifact_contains_fixed(node: ArtifactNode): bool =
  if node.isNil:
    return false
  if node.fixed_array or artifact_contains_fixed(node.element):
    return true
  for field in node.fields:
    if artifact_contains_fixed(field.node):
      return true
  for branch in node.branches:
    for field in branch.fields:
      if artifact_contains_fixed(field.node):
        return true
  false

proc model_output_requires_args_wrapper(node: ArtifactNode): bool =
  ## Dynamic function tools receive direct sequence arguments under `args`.
  ## Keep object-root outputs unchanged.
  not node.isNil and node.kind == ank_seq

proc artifact_wire_type(node: ArtifactNode): NimNode =
  ## Schematic has no array extractor. Replace fixed arrays by seqs in a
  ## generated wire type; all other leaves retain their declared type.
  doAssert not node.isNil
  if not artifact_contains_fixed(node):
    return copyNimTree(node.type_expr)

  case node.kind
  of ank_inline, ank_location, ank_option_none:
    copyNimTree(node.type_expr)
  of ank_seq:
    newTree(nnkBracketExpr, ident("seq"), artifact_wire_type(node.element))
  of ank_option:
    newTree(nnkBracketExpr, ident("Option"),
      artifact_wire_type(node.element))
  of ank_object:
    let shape = node.type_expr.getTypeImpl
    doAssert shape.kind == nnkObjectTy
    var fields = newNimNode(nnkRecList)
    var field_index = 0
    for source_field in shape[2]:
      doAssert source_field.kind == nnkIdentDefs,
        "fixed-array wire schema cannot rebuild variant object fields"
      for name_index in 0 ..< source_field.len - 2:
        let source_name = artifact_field_name(source_field, name_index)
        let wire_name = newTree(nnkPostfix, ident("*"),
          copyNimTree(source_name))
        fields.add(newTree(nnkIdentDefs, wire_name,
          artifact_wire_type(node.fields[field_index].node), newEmptyNode()))
        inc field_index
    newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(), fields)
  of ank_tuple:
    let shape = node.type_expr.getTypeImpl
    doAssert shape.kind in {nnkTupleTy, nnkTupleConstr}
    var fields = newNimNode(nnkTupleTy)
    for index, source_field in shape:
      let field_node = node.fields[index].node
      if source_field.kind == nnkIdentDefs:
        for name_index in 0 ..< source_field.len - 2:
          fields.add(newTree(nnkIdentDefs,
            copyNimTree(source_field[name_index]),
            artifact_wire_type(field_node), newEmptyNode()))
      else:
        fields.add(artifact_wire_type(field_node))
    fields
  of ank_variant:
    error("fixed arrays nested in variant output need a discriminated wire schema",
      node.type_expr)

proc artifact_option_element_type(type_expr: NimNode): NimNode =
  let shape = artifact_unwrapped_type(type_expr).getTypeImpl
  if shape.kind == nnkBracketExpr and shape.len == 2 and
      is_named(shape[0], "Option"):
    return copyNimTree(shape[1])
  doAssert artifact_is_option_shape(shape)
  copyNimTree(shape[2][0][0][^2])

proc artifact_sequence_element_type(type_expr: NimNode): NimNode =
  let shape = artifact_unwrapped_type(type_expr).getTypeImpl
  doAssert shape.kind == nnkBracketExpr and shape.len in {2, 3}
  copyNimTree(shape[^1])

proc emit_wire_conversion(
    node: ArtifactNode;
    value, target_type: NimNode
): NimNode =
  ## Convert the generated wire value back to the declared type. Equal schema
  ## bounds prove every fixed-array assignment below is in range.
  if not artifact_contains_fixed(node):
    return copyNimTree(value)

  case node.kind
  of ank_seq:
    let target_element = artifact_sequence_element_type(target_type)
    let converted = genSym(nskVar, "converted_sequence")
    let index = genSym(nskForVar, "wire_index")
    if node.fixed_array:
      let item = newTree(nnkBracketExpr, copyNimTree(value), copyNimTree(index))
      let item_value = emit_wire_conversion(node.element, item, target_element)
      quote do:
        block:
          var `converted`: `target_type`
          for `index` in 0 ..< len(`value`):
            `converted`[low(`converted`) + `index`] = `item_value`
          `converted`
    else:
      let item = genSym(nskForVar, "wire_item")
      let item_value = emit_wire_conversion(node.element, item, target_element)
      let loop = newTree(nnkForStmt, item, value,
        newCall(bindSym("add"), converted, item_value))
      quote do:
        block:
          var `converted`: `target_type`
          `loop`
          `converted`
  of ank_option:
    let target_element = artifact_option_element_type(target_type)
    let option_value = genSym(nskLet, "wire_option")
    let some_value = emit_wire_conversion(node.element,
      newCall(bindSym("get"), option_value), target_element)
    quote do:
      block:
        let `option_value` = `value`
        if isSome(`option_value`):
          some(`some_value`)
        else:
          none(`target_element`)
  of ank_object:
    let shape = node.type_expr.getTypeImpl
    doAssert shape.kind == nnkObjectTy
    let converted = genSym(nskVar, "converted_object")
    let normalized_type = copyNimTree(node.type_expr)
    var body = newStmtList()
    var field_index = 0
    for source_field in shape[2]:
      doAssert source_field.kind == nnkIdentDefs
      for name_index in 0 ..< source_field.len - 2:
        let field = node.fields[field_index]
        let field_value = artifact_field_value(value, field.selector)
        let target_field_type = copyNimTree(source_field[^2])
        body.add(newAssignment(
          artifact_field_value(converted, field.selector),
          emit_wire_conversion(field.node, field_value, target_field_type)))
        inc field_index
    let target = copyNimTree(target_type)
    quote do:
      block:
        var `converted`: `normalized_type`
        `body`
        cast[`target`](`converted`)
  of ank_tuple:
    let shape = node.type_expr.getTypeImpl
    doAssert shape.kind in {nnkTupleTy, nnkTupleConstr}
    let converted = genSym(nskVar, "converted_tuple")
    let normalized_type = copyNimTree(node.type_expr)
    var body = newStmtList()
    for index, source_field in shape:
      let field = node.fields[index]
      let field_value = artifact_field_value(value, field.selector)
      let target_field_type = if source_field.kind == nnkIdentDefs:
        copyNimTree(source_field[^2])
      else:
        copyNimTree(source_field)
      body.add(newAssignment(
        artifact_field_value(converted, field.selector),
        emit_wire_conversion(field.node, field_value, target_field_type)))
    let target = copyNimTree(target_type)
    quote do:
      block:
        var `converted`: `normalized_type`
        `body`
        cast[`target`](`converted`)
  else:
    error("unsupported fixed-array conversion node", node.type_expr)

proc model_output_contract(output_type: NimNode): NimNode =
  let output_tree = artifact_tree(output_type)
  var inner_schema: NimNode
  if artifact_contains_fixed(output_tree):
    let wire_name = genSym(nskType, "ModelOutputWire")
    let wire_def = newTree(nnkTypeSection,
      newTree(nnkTypeDef, wire_name, newEmptyNode(),
        artifact_wire_type(output_tree)))
    var schema = newCall(newTree(nnkBracketExpr,
      bindSym("output_schema_of"), wire_name))
    if output_tree.kind == ank_seq and output_tree.fixed_array:
      schema = newCall(bindSym("min"), schema,
        newLit(output_tree.fixed_length))
      schema = newCall(bindSym("max"), schema,
        newLit(output_tree.fixed_length))
    inner_schema = newTree(nnkBlockStmt, newEmptyNode(),
      newStmtList(wire_def, schema))
  elif output_tree.kind == ank_variant:
    inner_schema = newCall(
      newTree(nnkBracketExpr,
        bindSym"output_discriminated_schema", copyNimTree(output_type)),
      ident(output_tree.tag_name.strVal))
  else:
    inner_schema = newCall(newTree(nnkBracketExpr,
      bindSym"output_schema_of", copyNimTree(output_type)))

  if model_output_requires_args_wrapper(output_tree):
    let inner_name = genSym(nskLet, "model_output_inner_contract")
    let wrapped = quote do:
      block:
        let `inner_name` = `inner_schema`
        schema:
          args: `inner_name`
    return newCall(bindSym("strict"), wrapped)
  inner_schema

proc emit_model_materializer(
    registry: ArtifactRegistry;
    output_type, output_kind_value: NimNode
): NimNode =
  let artifact_name = registry.artifact_name
  let materializer_kind = genSym(nskParam, "model_output_kind")
  let materializer_output = genSym(nskParam, "model_output")
  let output_contract = genSym(nskLet, "model_output_contract")
  let parsed_output = genSym(nskLet, "model_parsed_output")
  let output_tree = artifact_tree(output_type)
  let parsed_value = if model_output_requires_args_wrapper(output_tree):
    newDotExpr(newDotExpr(parsed_output, ident("value")), ident("args"))
  else:
    newDotExpr(parsed_output, ident("value"))
  let packed_value = if artifact_contains_fixed(output_tree):
    emit_wire_conversion(output_tree, parsed_value, output_type)
  else:
    copyNimTree(parsed_value)
  let packed_output = registry.emit_artifact_pack(output_type, packed_value)
  let location_errors = genSym(nskVar, "location_errors")
  var verify_state = VerifyLocationsEmitState(
    working_dir: newDotExpr(
      copyNimTree(materializer_output), ident("working_dir")),
    errors: location_errors)
  let verify_locations_body = walk_artifact_tree(
    output_tree,
    parsed_value,
    newLit("output"),
    verify_state,
    verify_locations_callback)
  let verify_locations = quote do:
    var `location_errors` = ""
    `verify_locations_body`
    if `location_errors`.len != 0:
      return ModelMaterialization[`artifact_name`](
        ok: false,
        error: "invalid finish_work locations: " & `location_errors`)
  let output_contract_expr = model_output_contract(output_type)
  let materializer_body = quote do:
    case `materializer_kind`
    of `output_kind_value`:
      let `output_contract` = `output_contract_expr`
      let `parsed_output` = `output_contract`.tryParse(
        `materializer_output`.arguments)
      if not `parsed_output`.ok:
        return ModelMaterialization[`artifact_name`](
          ok: false,
          error: "invalid finish_work result (" &
            $`parsed_output`.issues.len & " schema issues)")
      `verify_locations`
      return ModelMaterialization[`artifact_name`](
        ok: true,
        value: `packed_output`)
    else:
      return ModelMaterialization[`artifact_name`](
        ok: false,
        error: "unexpected model output kind")
  let materializer = quote do:
    (proc (`materializer_kind`: int; `materializer_output`: LlmOutput):
        ModelMaterialization[`artifact_name`] {.nimcall, noinit.} =
      `materializer_body`
    )

  materializer

proc emit_model_submitter(
    registry: ArtifactRegistry;
    input_type, profile, prompt, prompt_templates,
    output_kind_value, output_contract_expr,
    materializer: NimNode
): NimNode =
  let artifact_name = registry.artifact_name
  let profile_expr = copyNimTree(profile)
  let prompt_expr = copyNimTree(prompt)
  let prompt_templates_expr = copyNimTree(prompt_templates)
  let finish_work_description_expr = newDotExpr(
    copyNimTree(prompt_templates), ident("finish_work_description"))
  let submit_context = genSym(nskParam, "model_context")
  let submit_request_id = genSym(nskParam, "model_request_id")
  let submit_input = genSym(nskParam, "model_input")
  let submit_working_dir = genSym(nskParam, "model_working_dir")
  let typed_input = genSym(nskLet, "model_typed_input")
  let materialized_input = genSym(nskLet, "model_materialized_input")
  let submit_unpacked = if input_type.is_void_type:
    newEmptyNode()
  else:
    registry.emit_artifact_unpack(input_type, submit_input)
  let input_materializer = if input_type.is_void_type:
    newEmptyNode()
  else:
    emit_input_materializer(input_type)
  let materialized_input_call = if input_type.is_void_type:
    newLit("")
  else:
    newCall(
      input_materializer,
      typed_input,
      newDotExpr(copyNimTree(submit_context), ident("runtime_dir")),
      submit_working_dir,
      newLit(""))
  let materialized_input_value = if input_type.is_void_type:
    newLit("")
  else:
    materialized_input
  let output_contract_name = genSym(nskLet, "model_output_contract")
  let output_schema_name = genSym(nskLet, "model_output_schema")
  let materializer_name = genSym(nskLet, "model_materializer")
  let tool_data_name = genSym(nskLet, "model_tool_data")
  let tools_name = genSym(nskVar, "model_tools")
  let callback = quote do:
    (proc (tool_data: pointer; tool_context: ToolCallContext)
      {.nimcall, gcsafe.} =
      {.cast(gcsafe).}:
        let binding = lookup_llm_tool_binding(tool_data)
        if binding.isNone:
          return
        let data = binding.get
        if data.retired:
          if not data.runtime.isNil and not data.liveness.isNil and
              data.liveness.alive:
            data.runtime.fail_server_request(
              tool_context.request_id,
              -32001,
              "stale finish_work callback")
          return
        enqueue_llm_output_event(
          cast[RuntimeContext[`artifact_name`]](data.context),
          data.request_id,
          data.output_kind,
          cast[ModelMaterializer[`artifact_name`]](data.materializer),
          data.id,
          tool_context)
    )
  let protocol_setup = quote do:
    let `output_contract_name` = `output_contract_expr`
    let `output_schema_name` = toJsonSchema(`output_contract_name`)
    let `materializer_name` = `materializer`
    let `tool_data_name` = register_llm_tool_binding(
      cast[pointer](`submit_context`), `submit_context`.codex_runtime,
      `submit_request_id`,
      `output_kind_value`, cast[pointer](`materializer_name`))
    var `tools_name`: DynamicToolRegistry = @[]
    `tools_name`.register_dynamic_tool(
      "finish_work",
      `finish_work_description_expr`,
      `output_schema_name`,
      `tool_data_name`,
      `callback`)
  let llm_spec_name = genSym(nskLet, "llm_spec")
  let llm_spec_value = quote do:
    LlmCallSpec[`artifact_name`](
      profile: `profile_expr`,
      prompt: `prompt_expr`,
      prompt_templates: `prompt_templates_expr`,
      materialized_input: `materialized_input_value`,
      runtime_dir: `submit_context`.runtime_dir,
      working_dir: `submit_working_dir`,
      tools: `tools_name`,
      output_kind: `output_kind_value`,
      materialize: `materializer_name`
    )
  let submit_llm_symbol = bindSym"submit_llm"
  let submit_body = if input_type.is_void_type:
    quote do:
      discard `submit_input`
      `protocol_setup`
      let `llm_spec_name` = `llm_spec_value`
      `submit_llm_symbol`(`submit_context`, `submit_request_id`,
        `llm_spec_name`)
  else:
    quote do:
      let `typed_input` = `submit_unpacked`
      try:
        let `materialized_input` = `materialized_input_call`
        `protocol_setup`
        let `llm_spec_name` = `llm_spec_value`
        `submit_llm_symbol`(`submit_context`, `submit_request_id`,
          `llm_spec_name`)
      except CatchableError as error:
        let event = RuntimeEvent[`artifact_name`](
          kind: rev_model_error,
          request_id: `submit_request_id`,
          error_message: error.msg)
        enqueue_runtime_event(`submit_context`, event)
  let submit = quote do:
    (proc (`submit_context`: RuntimeContext[`artifact_name`];
        `submit_request_id`: RequestId;
        `submit_input`: `artifact_name`;
        `submit_working_dir`: Path) {.nimcall.} =
      `submit_body`
    )
  submit

proc emit_model_flow(artifact_name, submit: NimNode): NimNode =
  quote do:
    Flow[`artifact_name`](
      kind: fk_model,
      submit: `submit`
    )

proc lower_model_call(
    registry: var ArtifactRegistry;
    flow_type, profile, prompt, prompt_templates: NimNode
): NimNode =
  let artifact_name = registry.artifact_name
  let input_type = copyNimTree(flow_type[1])
  let output_type = copyNimTree(flow_type[2])
  let output_kind_value = registry.model_output_kind(output_type)
  let output_contract_expr = model_output_contract(output_type)
  let materializer = registry.emit_model_materializer(
    output_type, output_kind_value)
  let submit = registry.emit_model_submitter(
    input_type, profile, prompt, prompt_templates,
    output_kind_value, output_contract_expr,
    materializer)
  emit_model_flow(artifact_name, submit)

proc lower_it(
    flow_type, ir: NimNode;
    registry: ArtifactRegistry
): NimNode

proc lower_fanout(
    flow_type, branches: NimNode;
    context: var FlowWalkContext
): NimNode

proc lower_so(
    flow_type, lambda: NimNode;
    context: var FlowWalkContext
): NimNode

proc lower_lift(
    flow_type, ir: NimNode;
    context: var FlowWalkContext
): NimNode

proc lower_raw_value(
    value_type, value: NimNode;
    registry: ArtifactRegistry
): NimNode

proc map_nim_tree(node: NimNode; context: var FlowWalkContext): NimNode

proc flow_proc_parts(node: NimNode; name, body: var NimNode): bool =
  if (ProcDef([
      @proc_name is Sym(),
      _,
      _,
      _,
      _,
      _,
      Asgn([_, @proc_body]),
      _
    ]) ?= node):
    name = proc_name
    body = proc_body
    true
  else:
    false

proc flow_proc_info(node: NimNode; info: var FlowProcInfo): bool =
  var id: int
  var name, body: NimNode
  if not flow_ir_proc_id(node, id) or not flow_proc_parts(node, name, body):
    return false
  info = FlowProcInfo(
    id: id,
    body: body,
    flow_type: first_flow_spec_type(body))
  true

proc collect_flow_declarations(
    node: NimNode;
    context: var FlowWalkContext
) =
  var ref_info: FlowRefInfo
  if flow_ref_info(node, ref_info):
    context.flow_refs.add ref_info

  var proc_info: FlowProcInfo
  if flow_proc_info(node, proc_info):
    context.flow_procs.add proc_info

  for child in node:
    collect_flow_declarations(child, context)

proc find_flow_ref(
    refs: seq[FlowRefInfo]; id: int
): int =
  result = -1
  for index, ref_info in refs:
    if ref_info.id == id:
      doAssert result < 0, "duplicate FlowSpec reference id: " & $id
      result = index

proc find_flow_proc(
    procs: seq[FlowProcInfo]; id: int
): int =
  result = -1
  for index, proc_info in procs:
    if proc_info.id == id:
      doAssert result < 0, "duplicate flow_ir id: " & $id
      result = index

proc join_flow_declarations(context: var FlowWalkContext) =
  for ref_info in context.flow_refs:
    let proc_index = find_flow_proc(context.flow_procs, ref_info.id)
    doAssert proc_index >= 0,
      "missing flow_ir proc for FlowSpec reference id: " & $ref_info.id
    let proc_info = context.flow_procs[proc_index]
    doAssert not proc_info.flow_type.isNil and
        sameType(ref_info.flow_type, proc_info.flow_type),
      "FlowSpec reference/proc endpoint mismatch for id: " & $ref_info.id
    context.flow_pairs.add FlowPair(
      ref_info: ref_info,
      proc_info: proc_info)

  for proc_info in context.flow_procs:
    doAssert find_flow_ref(context.flow_refs, proc_info.id) >= 0,
      "missing FlowSpec reference for flow_ir id: " & $proc_info.id

proc find_flow_pair(pairs: seq[FlowPair]; id: int): int =
  for index, pair in pairs:
    if pair.ref_info.id == id:
      return index
  -1

proc find_flow_ref_symbol(refs: seq[FlowRefInfo]; node: NimNode): int =
  for index, ref_info in refs:
    if ref_info.symbol == node:
      return index
  -1

proc lower_flow_ref(
    ref_info: FlowRefInfo;
    registry: ArtifactRegistry
): NimNode =
  let artifact_name = registry.artifact_name
  let name = newLit(ref_info.name)
  quote do:
    Flow[`artifact_name`](
      kind: fk_ref,
      name: `name`
    )

proc flow_composition_parts(
    node: NimNode;
    left, right: var NimNode
): bool =
  if (Infix([
      @infix_operator is Sym(),
      @infix_left,
      @infix_right
    ]) ?= node):
    if eqIdent(infix_operator, ">>>"):
      left = infix_left
      right = infix_right
      return true
  if (Call([
      @call_operator is Sym(),
      @call_left,
      @call_right
    ]) ?= node):
    if eqIdent(call_operator, ">>>"):
      left = call_left
      right = call_right
      return true
  false

proc append_continuation(flow, continuation: NimNode) =
  doAssert flow.field_value("continuation").isNil,
    "flow already has a continuation"
  flow.add newTree(nnkExprColonExpr, ident("continuation"), continuation)

proc lower_flow_expr(
    node: NimNode;
    context: var FlowWalkContext
): LoweredFlow =
  let flow_type = flow_spec_type(node)
  doAssert not flow_type.isNil, "expected FlowSpec expression"
  if node.kind == nnkPar and node.len == 1:
    return lower_flow_expr(node[0], context)

  var pure_value: NimNode
  if pure_parts(node, flow_type, pure_value):
    let value_type = type_inst_or_nil(pure_value)
    doAssert not value_type.isNil, "pure value has no type"
    result.head = lower_raw_value(
      value_type, pure_value, context.artifact_registry)
    result.tail = result.head
    return

  var left, right: NimNode
  if flow_composition_parts(node, left, right):
    if flow_spec_type(left).isNil:
      ## Typed `A >>> FlowSpec[A, B]` already checked endpoint compatibility;
      ## retain its value as a local Artifact seed, then use normal chaining.
      let value_type = type_inst_or_nil(left)
      doAssert not value_type.isNil, "value-seeded >>> left operand has no type"
      let value_flow = lower_raw_value(
        value_type, left, context.artifact_registry)
      let right_flow = lower_flow_expr(right, context)
      value_flow.append_continuation(right_flow.head)
      return LoweredFlow(head: value_flow, tail: right_flow.tail)

    let left_flow = lower_flow_expr(left, context)
    let right_flow = lower_flow_expr(right, context)
    left_flow.tail.append_continuation(right_flow.head)
    return LoweredFlow(head: left_flow.head, tail: right_flow.tail)

  var branches: NimNode
  if fanout_parts(node, flow_type, branches):
    result.head = lower_fanout(flow_type, branches, context)
    result.tail = result.head
    return

  var lambda: NimNode
  if so_parts(node, flow_type, lambda):
    result.head = lower_so(flow_type, lambda, context)
    result.tail = result.head
    return

  if node.kind == nnkSym:
    let ref_index = find_flow_ref_symbol(context.flow_refs, node)
    if ref_index >= 0 and sameType(
        flow_type, context.flow_refs[ref_index].flow_type):
      result.head = lower_flow_ref(context.flow_refs[ref_index],
        context.artifact_registry)
      result.tail = result.head
      return

  let ir = node.field_value("ir")
  if not ir.isNil and ir.is_flow_ir_lift:
    result.head = lower_lift(flow_type, ir, context)
  elif not ir.isNil and ir.is_flow_ir_it:
    result.head = lower_it(flow_type, ir, context.artifact_registry)
  else:
    var profile, prompt: NimNode
    doAssert model_call_parts(node, flow_type, profile, prompt),
      "unsupported FlowSpec expression; expected model call, pure, lift, or >>>"
    result.head = lower_model_call(
      context.artifact_registry, flow_type, profile, prompt,
      context.prompt_templates)
  result.tail = result.head

proc lower_flow_pair(
    pair: FlowPair;
    context: var FlowWalkContext
): NimNode =
  let transformed_body = map_nim_tree(pair.proc_info.body, context)
  let artifact_name = context.artifact_registry.artifact_name
  let root_name = newLit(pair.ref_info.name)
  let entry = newLit(pair.ref_info.entry)
  let top_flow = quote do:
    Flow[`artifact_name`](
      kind: fk_top,
      root: `root_name`,
      entry: `entry`,
      body: `transformed_body`
    )
  top_flow

proc map_nim_tree(node: NimNode; context: var FlowWalkContext): NimNode =
  if node.kind == nnkIdentDefs:
    var ref_info: FlowRefInfo
    if flow_ref_info(node, ref_info):
      let pair_index = find_flow_pair(context.flow_pairs, ref_info.id)
      doAssert pair_index >= 0,
        "unmatched FlowSpec reference id: " & $ref_info.id
      let flow = lower_flow_pair(context.flow_pairs[pair_index], context)
      return newTree(nnkIdentDefs, ident(ref_info.name), newEmptyNode(), flow)

  if node.kind == nnkProcDef:
    var proc_id: int
    if flow_ir_proc_id(node, proc_id):
      doAssert find_flow_pair(context.flow_pairs, proc_id) >= 0,
        "unmatched flow_ir id: " & $proc_id
      return newEmptyNode()

  let flow_type = flow_spec_type(node)
  if not flow_type.isNil:
    return lower_flow_expr(node, context).head

  result = copyNimNode(node)
  for child in node:
    result.add map_nim_tree(child, context)

proc make_vecherinka_artifact_type(
    flow_types: seq[NimNode];
    registry: var ArtifactRegistry
): NimNode =
  let kind_name = genSym(nskType, "VecherinkaArtifactKind")
  let artifact_name = genSym(nskType, "VecherinkaArtifact")
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

proc lower_raw_value(
    value_type, value: NimNode;
    registry: ArtifactRegistry
): NimNode =
  let artifact_name = registry.artifact_name
  let packed = registry.emit_artifact_pack(value_type, value)
  quote do:
    Flow[`artifact_name`](
      kind: fk_raw,
      value: `packed`
    )

proc lower_it(
    flow_type, ir: NimNode;
    registry: ArtifactRegistry
): NimNode =
  let path = ir.field_value("path")
  doAssert not path.isNil, "malformed it IR: missing path"

  let domain = copyNimTree(flow_type[1])
  let codomain = copyNimTree(flow_type[2])
  doAssert not domain.is_void_type and not codomain.is_void_type,
    "it flow endpoints must be non-void"

  let artifact_name = registry.artifact_name
  let input = genSym(nskParam, "it_artifact")
  let typed_input = genSym(nskLet, "it_value")
  let unpacked = registry.emit_artifact_unpack(domain, input)
  let projected = newCall(
    bindSym("project_it"), typed_input, copyNimTree(path))
  let packed = registry.emit_artifact_pack(codomain, projected)
  let projector = quote do:
    proc (`input`: `artifact_name`): `artifact_name` {.nimcall.} =
      let `typed_input` = `unpacked`
      `packed`
  quote do:
    Flow[`artifact_name`](
      kind: fk_it,
      projector: `projector`
    )

proc lower_fanout(
    flow_type, branches: NimNode;
    context: var FlowWalkContext
): NimNode =
  let output_type = flow_type[2]
  doAssert output_type.kind in {nnkTupleConstr, nnkTupleTy} and
      output_type.len == branches.len,
    "fanout output tuple does not match branch count"

  var branch_nodes = newTree(nnkBracket)
  var branch_types: seq[NimNode]
  for index, branch in branches:
    let branch_type = flow_spec_type(branch)
    doAssert not branch_type.isNil, "fanout branch is not a FlowSpec"
    doAssert sameType(branch_type[1], flow_type[1]),
      "fanout branch domain mismatch"
    let output_item = output_type[index]
    let output_item_type = if output_item.kind == nnkExprColonExpr:
      output_item[1]
    else:
      output_item
    doAssert sameType(output_item_type, branch_type[2]),
      "fanout branch codomain mismatch"
    branch_types.add copyNimTree(branch_type[2])
    branch_nodes.add lower_flow_expr(branch, context).head

  let values = genSym(nskParam, "fan_values")
  var tuple_value = newTree(nnkTupleConstr)
  for index, branch_type in branch_types:
    tuple_value.add context.artifact_registry.emit_artifact_unpack(
      branch_type, newTree(nnkBracketExpr, values, newLit(index)))
  let packed = context.artifact_registry.emit_artifact_pack(
    output_type, tuple_value)
  let artifact_name = context.artifact_registry.artifact_name
  let coalesce = quote do:
    proc (`values`: seq[`artifact_name`]): `artifact_name` {.nimcall.} =
      `packed`
  let branch_seq = newTree(nnkPrefix, ident("@"), branch_nodes)
  quote do:
    Flow[`artifact_name`](
      kind: fk_fanout,
      branches: `branch_seq`,
      coalesce: `coalesce`
    )

proc lower_so(
    flow_type, lambda: NimNode;
    context: var FlowWalkContext
): NimNode =
  var parameter, input_type, working_dir_parameter, body: NimNode
  doAssert so_lambda_parts(lambda, parameter, input_type,
    working_dir_parameter, body),
    "malformed so callback"

  let domain = flow_type[1]
  doAssert not domain.is_void_type and sameType(input_type, domain),
    "so callback input does not match FlowSpec domain"

  let artifact_name = context.artifact_registry.artifact_name
  let artifact_input = genSym(nskParam, "so_artifact")
  let so_working_dir = genSym(nskParam, "so_working_dir")
  let typed_input = genSym(nskLet, "so_input")
  let unpacked = context.artifact_registry.emit_artifact_unpack(
    domain, artifact_input)
  let transformed_body = map_nim_tree(body, context)
  var rebound_body = replace_symbol(transformed_body, parameter, typed_input)
  if working_dir_parameter.kind != nnkEmpty:
    rebound_body = replace_symbol(
      rebound_body, working_dir_parameter, so_working_dir)
  let expand = quote do:
    proc (`artifact_input`: `artifact_name`; `so_working_dir`: Path):
        Flow[`artifact_name`] {.nimcall.} =
      let `typed_input` = `unpacked`
      `rebound_body`
  quote do:
    Flow[`artifact_name`](
      kind: fk_so,
      execute: `expand`
    )

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
    let next_index = state.next_index
    let works = state.works
    let source = copyNimTree(value)
    let packed = registry.emit_artifact_pack(input_type, source)
    result = quote do:
      let `index` = `next_index`
      inc `next_index`
      `works`.add (
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

proc lower_lift(
    flow_type, ir: NimNode;
    context: var FlowWalkContext
): NimNode =
  let pattern_node = ir.field_value("pattern")
  let inner_node = ir.field_value("inner")
  doAssert not pattern_node.isNil and not inner_node.isNil and
      pattern_node.kind in {nnkStrLit, nnkRStrLit, nnkTripleStrLit},
    "malformed lift IR"
  doAssert inner_node.kind == nnkDotExpr and inner_node.len == 2 and
      inner_node[1].is_named("ir"),
    "lift inner flow source is unavailable"

  let inner = inner_node[0]
  let inner_type = first_flow_spec_type(inner)
  doAssert not inner_type.isNil, "lift inner flow type is unavailable"
  doAssert not inner_type[1].is_void_type and
      not inner_type[2].is_void_type,
    "lift inner flow must have non-void endpoints"

  let tree = parse_lift_pattern(parseExpr(pattern_node.strVal))
  discard lift_types(tree, inner_type[1], inner_type[2])
  let inner_flow = lower_flow_expr(inner, context).head
  let registry = context.artifact_registry
  let artifact_name = registry.artifact_name
  let outer_domain = copyNimTree(flow_type[1])
  let outer_codomain = copyNimTree(flow_type[2])

  let destructure_input = genSym(nskParam, "lift_destructure_input")
  let destructure_original = genSym(nskLet, "lift_original")
  let destructure_next_index = genSym(nskVar, "lift_next_index")
  let unpack_input = registry.emit_artifact_unpack(
    outer_domain, destructure_input)
  var destructure_state = LiftEmitState(
    next_index: destructure_next_index,
    works: ident("result"))
  let destructure_body = emit_destructure(tree, tree.root_id,
    destructure_original, destructure_state, registry, inner_type[1])
  let destructure = quote do:
    proc (`destructure_input`: `artifact_name`):
        seq[tuple[result_index: int, input: `artifact_name`]] {.nimcall.} =
      let `destructure_original` = `unpack_input`
      var `destructure_next_index` = 0
      `destructure_body`

  let construct_results = genSym(nskParam, "lift_results")
  let construct_input = genSym(nskParam, "lift_construct_input")
  let construct_original = genSym(nskLet, "lift_original_input")
  let construct_next_index = genSym(nskVar, "lift_next_index")
  let unpack_construct_input = registry.emit_artifact_unpack(
    outer_domain, construct_input)
  var construct_state = LiftEmitState(
    next_index: construct_next_index,
    results: construct_results)
  let construct_body = emit_construct(tree, tree.root_id,
    construct_original, construct_state, registry,
    inner_type[1], inner_type[2])
  let packed = registry.emit_artifact_pack(outer_codomain, construct_body)
  let construct = quote do:
    proc (`construct_results`: seq[`artifact_name`];
        `construct_input`: `artifact_name`): `artifact_name` {.nimcall.} =
      let `construct_original` = `unpack_construct_input`
      var `construct_next_index` = 0
      `packed`

  quote do:
    Flow[`artifact_name`](
      kind: fk_lift,
      inner: `inner_flow`,
      destructure: `destructure`,
      construct: `construct`
    )

proc lower_vecherinka_runtime(
    body, solve, prompt_templates: NimNode
): NimNode =
  var context = FlowWalkContext()
  context.prompt_templates = copyNimTree(prompt_templates)
  walk_flow_specs(body, context)

  collect_flow_declarations(body, context)
  join_flow_declarations(context)

  var registry: ArtifactRegistry
  let artifact_type = make_vecherinka_artifact_type(
    context.flow_types, registry)
  context.artifact_registry = registry

  doAssert solve.kind in {nnkStrLit, nnkRStrLit, nnkTripleStrLit},
    "vecherinka proc name must be a string"
  let proc_name = ident(solve.strVal)

  var entry_index = -1
  for index, pair in context.flow_pairs:
    if not pair.ref_info.entry:
      continue
    doAssert entry_index < 0, "vecherinka requires exactly one .entry. flow"
    entry_index = index
  doAssert entry_index >= 0, "vecherinka requires exactly one .entry. flow"

  let entry_type = context.flow_pairs[entry_index].ref_info.flow_type
  doAssert not entry_type[1].is_void_type,
    "vecherinka entry flow domain must be non-void"
  let entry_domain = copyNimTree(entry_type[1])
  let entry_codomain = copyNimTree(entry_type[2])

  # Every pair lowers to one fk_top node. Pair order follows source declaration
  # order, so sequence order stays deterministic and name-independent.
  var top_flows = newTree(nnkBracket)
  for pair in context.flow_pairs:
    top_flows.add lower_flow_pair(pair, context)
  let flow_sequence = newTree(nnkPrefix, ident("@"), top_flows)
  let artifact_name = context.artifact_registry.artifact_name
  let data_type = quote do:
    seq[Flow[`artifact_name`]]
  let input_name = genSym(nskParam, "input")
  let transport_name = genSym(nskParam, "transport")
  let logger_name = genSym(nskParam, "logger")
  let data_name = genSym(nskLet, "data")
  let input_artifact_name = genSym(nskLet, "input_artifact")
  let input_artifact = context.artifact_registry.emit_artifact_pack(
    entry_domain, input_name)
  let execute_flows = bindSym"execute_flows"
  let lookup_artifact = bindSym"lookup_artifact"
  let work_plan_name = genSym(nskLet, "work_plan")
  let final_artifact = quote do:
    `lookup_artifact`(`work_plan_name`.context,
      `work_plan_name`.output.get).data
  let returned_value = context.artifact_registry.emit_artifact_unpack(
    entry_codomain, final_artifact)
  let proc_body = quote do:
    let `data_name`: `data_type` = `flow_sequence`
    let `input_artifact_name` = `input_artifact`
    let `work_plan_name` = `execute_flows`(`data_name`, `input_artifact_name`,
      transport = `transport_name`,
      logger = `logger_name`)
    if `work_plan_name`.output.isNone:
      if `work_plan_name`.failure_message.isSome:
        raise newException(ValueError, `work_plan_name`.failure_message.get)
      raise newException(ValueError,
        "vecherinka execution completed without output")
    return `returned_value`
  let generated_proc = quote do:
    proc `proc_name`(`input_name`: `entry_domain`;
        `transport_name`: LlmTransport[`artifact_name`] = nil;
        `logger_name`: StructuredLogger = nil): `entry_codomain` =
      `proc_body`
  var generated = newStmtList()
  generated.add(artifact_type)
  generated.add(generated_proc)
  generated

macro vecherinka_runtime*(solve: untyped; body: typed): untyped =
  lower_vecherinka_runtime(body, solve,
    bindSym("default_agent_prompt_templates"))

macro vecherinka_runtime*(solve, prompt_templates: untyped;
    body: typed): untyped =
  lower_vecherinka_runtime(body, solve, prompt_templates)

proc make_vecherinka(
    body, solve, prompt_templates: NimNode
): NimNode =
  var refs, procs = newStmtList()

  doAssert solve.isNil or solve.kind in {nnkIdent, nnkSym, nnkAccQuoted},
    "vecherinka proc name must be an identifier"

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
          id: `id`,
          entry: `entry`
        ))

      let proc_name = genSym(nskProc, "flow")
      procs.add quote do:
        proc `proc_name`: `domain` ~> `codomain` {.flow_ir(`id`, `entry`).} =
          `flow_body`
    else: doAssert false, "Malformed vecherinka flow"

  for node in procs:
    refs.add node

  let solve_name = newLit(solve.strVal)
  result = quote do:
    vecherinka_runtime(`solve_name`, `prompt_templates`):
      `refs`

macro vecherinka*(solve, body: untyped): untyped =
  make_vecherinka(body, solve,
    bindSym("default_agent_prompt_templates"))

macro vecherinka*(solve, prompt_templates: untyped;
    body: untyped): untyped =
  make_vecherinka(body, solve, prompt_templates)
