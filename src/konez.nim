{.experimental: "callOperator".}

import std/[macros, strutils, sequtils, tables, sugar]
import fusion/matching
import codex_json
import it_projection
import lift_pattern

type
  Location* = distinct string
  Model* = enum
    luna, terra, sol
  Profile = object
    model: Model
    effort: ReasoningEffort

proc minimal*(model: Model): Profile = Profile(model: model, effort: re_minimal)
proc low*(model: Model): Profile = Profile(model: model, effort: re_low)
proc medium*(model: Model): Profile = Profile(model: model, effort: re_medium)
proc high*(model: Model): Profile = Profile(model: model, effort: re_high)
proc xhigh*(model: Model): Profile = Profile(model: model, effort: re_xhigh)

type
  FlowRef* = object
    id: int
  ArrowSyntax*[A, B] = object
  PartialModelCallSyntax* = object
  ModelCallSyntax* = object
  ItSyntax* = object
  FanoutSyntax* = object
  ComposeSyntax* = object
  SoSyntax* = object
  SoCarrier*[T] = object
  ItProjectionSyntax* = object
  LiftSyntax* = object
  LiftPartialSyntax* = object
  ArrowlikeObject* =
    ItSyntax | ItProjectionSyntax | FlowRef | FanoutSyntax | ComposeSyntax |
      SoSyntax | LiftSyntax | ModelCallSyntax

const
  flow_keyword = ">"
  arrow_keyword = "~>"
  entry_pragma = "entry"

template flow*(id: int, entry: bool) {.pragma.}
template `~>`*(A, B: untyped): untyped = ArrowSyntax[A, B]
proc `[]`*[A, B](profile: Profile; _: typedesc[A]; _: typedesc[B]): PartialModelCallSyntax = PartialModelCallSyntax()
proc `()`*(partial: PartialModelCallSyntax; prompt: string): ModelCallSyntax = ModelCallSyntax()
const it* = ItSyntax()
proc `&&&`*(left, right: distinct ArrowlikeObject): FanoutSyntax = FanoutSyntax()
proc `>>>`*(left, right: distinct ArrowlikeObject): ComposeSyntax = ComposeSyntax()
proc pure[T](v: T) = discard

template it_data*(path: untyped) {.pragma.}

proc itSelectorGroup(selectors: NimNode): NimNode =
  result = newNimNode(nnkBracket)
  for selector in selectors:
    result.add selector

proc itPathFromMarker(base, dataSym, markerSym: NimNode): NimNode =
  ## Structural match keeps nested `[]` independent of incidental child
  ## offsets. Only markers emitted by makeItProjectionMarker are accepted.
  case base:
  of BlockExpr([_, StmtListExpr([LetSection([IdentDefs([
      PragmaExpr([
        _, Pragma([Call([
          @data == dataSym,
          @path
        ])])
      ]), _, ObjConstr([@marker == markerSym])
    ])]), _])]):
    result = copyNimTree(path)
  else:
    error("malformed it projection marker", base)

proc makeItProjectionMarker(path: NimNode): NimNode =
  result = quote do:
    block:
      let marker {.it_data(`path`).} = ItProjectionSyntax()
      marker

macro `[]`*(base: ItSyntax; selectors: varargs[untyped]): untyped =
  var path = newNimNode(nnkBracket)
  path.add itSelectorGroup(selectors)
  result = makeItProjectionMarker(path)

macro `[]`*(base: ItProjectionSyntax; selectors: varargs[untyped]): untyped =
  var path = itPathFromMarker(
    base, bindSym "it_data", bindSym "ItProjectionSyntax")
  path.add itSelectorGroup(selectors)
  result = makeItProjectionMarker(path)

template so_data*(result_type, param, body: untyped) {.pragma.}
template so*[A](param, body: untyped): untyped =
  so_impl(SoCarrier[A], param, body)
macro so_impl*(tag: typedesc; param, body: untyped): untyped =
  let result_type = tag.getTypeInst[1][1]
  result = quote do:
    block:
      let marker {.so_data(`result_type`, `param`, `body`).} = SoSyntax()
      marker

template lift_data*(pattern, body: untyped) {.pragma.}

template lift_pattern_data*(pattern: untyped) {.pragma.}

proc liftPatternFromMarker(base, dataSym, markerSym: NimNode): NimNode =
  ## Same marker proof as it projection: only our own block shape can carry
  ## a pattern, so a user expression cannot be mistaken for parser input.
  case base:
  of BlockExpr([_, StmtListExpr([LetSection([IdentDefs([
      PragmaExpr([
        _, Pragma([Call([
          @data == dataSym,
          @pattern
        ])])
      ]), _, ObjConstr([@marker == markerSym])
    ])]), _])]):
    result = copyNimTree(pattern)
  else:
    error("malformed lift pattern marker", base)

proc makeLiftPatternMarker(pattern: NimNode): NimNode =
  result = quote do:
    block:
      let marker {.lift_pattern_data(`pattern`).} = LiftPartialSyntax()
      marker

proc makeLiftMarker(pattern, body: NimNode): NimNode =
  result = quote do:
    block:
      let marker {.lift_data(`pattern`, `body`).} = LiftSyntax()
      marker

const lift* = LiftSyntax()

macro `[]`*(base: LiftSyntax; pattern: untyped): untyped =
  result = makeLiftPatternMarker(pattern)

macro `()`*(base: LiftPartialSyntax; body: untyped): untyped =
  let pattern = liftPatternFromMarker(
    base, bindSym "lift_pattern_data", bindSym "LiftPartialSyntax")
  result = makeLiftMarker(pattern, body)

iterator walk(node: NimNode): tuple[p_i, i: int; n: NimNode] {.inline.} =
  var idx = 0
  var node_stack = @[node]
  var len_stack = @[-1]
  var idx_stack = @[-1]
  while node_stack.len > 0:
    let peep_len = len_stack[^1]

    if node_stack.len == peep_len:
      discard len_stack.pop()
      discard idx_stack.pop()
      continue
    
    let peep_idx = idx_stack[^1]
    let next_node = node_stack.pop()

    yield (peep_idx, idx, next_node)

    len_stack.add node_stack.len
    idx_stack.add idx

    inc idx

    let child_buffer = collect(newSeq):
      for child in next_node.children:
        child
    for i in countdown(child_buffer.high, 0):
      node_stack.add child_buffer[i]

type
  AttachedNodeKind = enum
    ank_flow,
    ank_model
  AttachedNode = object
    case kind: AttachedNodeKind
    of ank_flow: discard
    of ank_model: discard

macro konez_semantic*(body: typed): untyped =
  dump body.astGenRepr

  let bound_compose = bindSym ">>>"
  let bound_fanout = bindSym "&&&"
  let bound_model_call = bindSym "()"
  let bound_partial_model_call = bindSym "[]"
  let bound_it = bindSym "it"
  let bound_it_projection_syntax = bindSym "ItProjectionSyntax"
  let bound_it_data = bindSym "it_data"
  let bound_pure = bindSym "pure"
  let bound_so_syntax = bindSym "SoSyntax"
  let bound_so_data = bindSym "so_data"
  let bound_lift_syntax = bindSym "LiftSyntax"
  let bound_lift_data = bindSym "lift_data"

  var flow_refs: seq[NimNode]
  for section in body:
    if section.kind == nnkConstSection:
      for def in section:
        if def.kind == nnkConstDef and def[0].kind == nnkSym:
          flow_refs.add def[0]

  var idx_relations: Table[int, seq[int]]
  var attached_nodes: Table[int, AttachedNode]

  for (p_i, i, n) in body.walk:
    idx_relations.mgetOrPut(p_i, @[]).add i
    case n:
      # top level proc
      of ProcDef([
          _, _, _,
          FormalParams([Infix([_, @domain, @codomain])]),
          Pragma([Call([_, @id, _])]),
          _,
          Asgn([_, Cast([_, @body]) ]),
          _]):
        attached_nodes[i] = AttachedNode(
          kind: ank_flow
        )
        echo """
          proc= $#, i= $#,
          domain: $#,
          codomain: $#
        """.dedent() % [$id.intVal, $i, domain.repr, codomain.repr]
      # it
      of bound_it:
        echo """
          it, i= $#
        """.dedent() % [$i]
      # it projection
      of BlockExpr([_, StmtListExpr([LetSection([IdentDefs([
          PragmaExpr([
            _, Pragma([Call([
              @it_data == bound_it_data,
              @path
            ])])
          ]), _, ObjConstr([@it_projection_syntax == bound_it_projection_syntax])
        ])]), _])]):
        let parsed = parseItPath(path)
        echo """
          it projection, i= $#, path= $#, groups= $#
        """.dedent() % [$i, path.repr, $parsed]
      # pure
      of bound_pure:
        echo """
          pure, i= $#
        """.dedent() % [$i]
      # flow ref
      of @captured in flow_refs:
        echo """
          flow ref= $#, i= $#
        """.dedent() % [captured.repr, $i]
      # >>>, &&&
      of Infix([@sym is Sym(), @left, @right]):
        if sym.isInstantiationOf bound_compose:
          echo """
            >>>, i= $#,
            left: $#,
            right: $#
          """.dedent() % [$i, left.repr, right.repr]
        elif sym.isInstantiationOf bound_fanout:
          echo """
            &&&, i= $#,
            left: $#,
            right: $#
          """.dedent() % [$i, left.repr, right.repr]
        else: discard
      # model calls
      of Call([@a is Sym(), Call([@b is Sym(), _, @domain, @codomain]), _]):
        if bound_model_call.anyIt(a == it) and
            bound_partial_model_call.anyIt(b.isInstantiationOf it):
          echo """
            model call, i= $#,
            domain: $#,
            codomain: $#
          """.dedent() % [$i, domain.repr, codomain.repr]
          attached_nodes[i] = AttachedNode(
            kind: ank_model
          )
      # `so`
      of BlockExpr([_, StmtListExpr([LetSection([IdentDefs([
          PragmaExpr([
            _, Pragma([Call([
              @so_data == bound_so_data,
              @codomain is Sym(),
              .._
            ])])
            ]), _, ObjConstr([@so_syntax == bound_so_syntax])
          ])]), _])]):
        echo """
          so, i= $#,
          codomain: $#
        """.dedent() % [$i, codomain.repr]
      # `lift`
      of BlockExpr([_, StmtListExpr([LetSection([IdentDefs([
          PragmaExpr([
            _, Pragma([Call([
              @lift_data == bound_lift_data,
              @pattern,
              @body
            ])])
          ]), _, ObjConstr([@lift_syntax == bound_lift_syntax])
          ])]), _])]):
        let parsed = parseLiftPattern(pattern)
        echo """
          lift, i= $#, 
          pattern: $#, 
          hereCount: $#, 
          body: $#
        """.dedent() % [$i, pattern.repr, $parsed.hereCount, body.repr]

  echo "======================================="

  for i, attached_node in attached_nodes:
    case attached_node.kind:
    of ank_flow:
      echo "flow at $#" % [$i]
      echo "child at $#" % [$idx_relations[idx_relations[idx_relations[i][6]][1]][1]]
    of ank_model:
      echo "model at $#" % [$i]
  result = body

macro konez*(body: untyped): untyped =
  var refs, procs = newStmtList()

  for id, child in body:
    case child:
    of Prefix([@prefix, Command([@name, Infix([@arrow, @domain, @raw_codomain]), .._]), @flow_body]):
      expectIdent prefix, flow_keyword
      expectIdent arrow, arrow_keyword
      expectKind flow_body, nnkStmtList

      let (codomain, entry) = case raw_codomain:
        of PragmaExpr([@bare_codomain, Pragma([@pragma])]):
          (bare_codomain, pragma.strVal == entry_pragma)
        else: (raw_codomain, false)

      refs.add quote do:
        const `name` = FlowRef(id: `id`)

      let proc_name = ident("flow_" & $id)
      procs.add quote do:
        proc `proc_name`: `domain` ~> `codomain` {.flow(`id`, `entry`).} =
          cast[`domain` ~> `codomain`](`flow_body`)
    else: error("Malformed konez flow", child)

  for node in procs:
    refs.add node

  result = quote do:
    konez_semantic:
      `refs`
