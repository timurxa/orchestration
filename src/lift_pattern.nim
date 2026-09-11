import std/[macros, strutils]

## Syntax-only representation of the first lift-pattern grammar.
##
## Correctness contract:
## * every accepted NimNode maps to exactly one LiftPattern tree;
## * every tree node corresponds to one grammar production;
## * hereCount equals the number of `here` leaves in that tree;
## * malformed nodes produce a compiler error instead of an ambiguous tree.
##
## Object `_` needs one deliberate deferral. In `T(caseField: _)`, `_` can
## mean either "preserve ordinary field" or "accept any variant tag". The
## parser records Wildcard; type-aware elaboration resolves that ambiguity.
##
## LiftPattern is one regular node. LiftPatternTree owns all nodes in an
## append-only arena; recursive edges store LiftPatternId indexes, never
## pointers into the arena. This keeps IDs stable when the node sequence grows.

type
  LiftPatternKind* = enum
    lpkKeep
    lpkHere
    lpkSeq
    lpkOption
    lpkTuple
    lpkObject

  LiftPatternId* = distinct int

  LiftTag* = object
    ## Original, non-executable spelling. Later code can turn this back into
    ## an expression after type resolution; parser never evaluates tags. The
    ## NimNode retains symbol identity lost by text alone.
    text*: string
    expression: NimNode

  LiftObjectMemberKind* = enum
    lomPattern
    lomTag
    lomWildcard

  LiftPattern* = object
    ## Case discriminator makes invalid payload combinations unrepresentable;
    ## all payload fields stay private, so callers cannot forge the count or an
    ## invalid child ID through an object constructor.
    case patternKind: LiftPatternKind
    of lpkKeep, lpkHere:
      discard
    of lpkSeq, lpkOption:
      child: LiftPatternId
    of lpkTuple:
      items: seq[LiftTupleItem]
    of lpkObject:
      typeName: string
      typeExpr: NimNode
      members: seq[LiftObjectMember]
    hereCount: int

  LiftTupleItem* = object
    ## Empty name means positional tuple item.
    name*: string
    patternId*: LiftPatternId

  LiftObjectMember* = object
    name*: string
    case kind*: LiftObjectMemberKind
    of lomPattern:
      patternId*: LiftPatternId
    of lomTag:
      tag*: LiftTag
    of lomWildcard:
      discard

  LiftPatternTree* = object
    ## Root and node IDs belong to this tree. IDs are sequence indexes and
    ## remain valid while nodes are appended; nodes are never removed/reordered.
    root: LiftPatternId
    nodes: seq[LiftPattern]

proc `==`*(left, right: LiftPatternId): bool {.borrow.}

const invalidLiftPatternId = LiftPatternId(-1)

proc hasNode(tree: LiftPatternTree; id: LiftPatternId): bool =
  int(id) >= 0 and int(id) < tree.nodes.len

proc node*(tree: LiftPatternTree; id: LiftPatternId): LiftPattern =
  assert tree.hasNode(id)
  tree.nodes[int(id)]

proc appendNode(tree: var LiftPatternTree; value: LiftPattern): LiftPatternId =
  ## ID equals append position. Appending cannot change any existing ID.
  result = LiftPatternId(tree.nodes.len)
  tree.nodes.add(value)
  assert tree.hasNode(result)

const nameKinds = {nnkIdent, nnkSym}

proc nameNode(node: NimNode): bool =
  case node.kind
  of nnkIdent, nnkSym:
    true
  of nnkAccQuoted:
    ## Accquoted names may contain several identifier-shaped parts, such as
    ## `field-name`; accepting only one child would reject valid field names.
    if node.len == 0:
      return false
    for part in node:
      if part.kind notin nameKinds:
        return false
    true
  else:
    false

proc nameText(node: NimNode): string =
  ## Only identifier-shaped nodes enter names. Thus stored names cannot carry
  ## calls, operators, or hidden evaluation; they are safe field selectors.
  if not node.nameNode:
    error("lift pattern expects an identifier", node)
  if node.kind == nnkAccQuoted:
    for part in node:
      if part.kind notin nameKinds:
        error("malformed backtick identifier", part)
      ## Each part contributes literal spelling; repr would reinsert operator
      ## spacing and lose the original field name.
      result.add part.strVal
  else:
    result = node.repr

proc isWildcard(node: NimNode): bool =
  node.kind in nameKinds and node.repr == "_"

proc isHere(node: NimNode): bool =
  node.kind in nameKinds and node.repr == "here"

proc withoutParens(node: NimNode): NimNode =
  result = node
  ## Each loop iteration removes one concrete nnkPar node. Finite AST depth
  ## therefore proves termination; grouping cannot alter pattern meaning.
  while result.kind == nnkPar:
    if result.len != 1:
      error("parenthesized lift pattern expects one child", result)
    result = result[0]

proc isNumericLiteral(node: NimNode): bool =
  node.kind in {
    nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit,
    nnkUIntLit, nnkUInt8Lit, nnkUInt16Lit, nnkUInt32Lit, nnkUInt64Lit,
    nnkFloatLit, nnkFloat32Lit, nnkFloat64Lit, nnkFloat128Lit
  }

proc isLiteral(node: NimNode): bool =
  node.isNumericLiteral or node.kind in {
    nnkStrLit, nnkRStrLit, nnkTripleStrLit, nnkCharLit, nnkNilLit
  }

proc isQualifiedName(node: NimNode): bool =
  ## Tag names stay intentionally narrower than arbitrary Nim expressions.
  ## Recursive descent follows only dotted-name children, so this predicate
  ## cannot accidentally admit calls or operators.
  case node.kind
  of nnkIdent, nnkSym, nnkAccQuoted:
    node.nameNode
  of nnkDotExpr:
    node.len == 2 and node[0].isQualifiedName and node[1].nameNode
  else:
    false

proc isOperator(node: NimNode; spelling: string): bool

proc isSignedNumeric(node: NimNode): bool =
  node.len == 2 and (node[0].isOperator("+") or node[0].isOperator("-")) and
    node[1].isNumericLiteral

proc isTagAtom(node: NimNode): bool =
  if node.isLiteral:
    return true
  case node.kind
  of nnkIdent, nnkSym, nnkAccQuoted, nnkDotExpr:
    node.isQualifiedName
  of nnkPrefix:
    ## Permit signed numeric tags, e.g. `kind: -1`, without admitting a
    ## general prefix expression.
    node.isSignedNumeric
  of nnkPar:
    ## Parentheses do not add semantic structure to a scalar tag.
    ## Reserved pattern leaves remain patterns, never tags.
    node.len == 1 and not node[0].isWildcard and not node[0].isHere and
      node[0].isTagAtom
  else:
    false

proc newLeaf(tree: var LiftPatternTree; kind: LiftPatternKind): LiftPatternId =
  assert kind in {lpkKeep, lpkHere}
  var value: LiftPattern
  value.patternKind = kind
  value.hereCount = ord(kind == lpkHere)
  appendNode(tree, value)

proc newUnary(
    tree: var LiftPatternTree;
    kind: LiftPatternKind;
    child: LiftPatternId
): LiftPatternId =
  assert kind in {lpkSeq, lpkOption}
  assert tree.hasNode(child)
  var value: LiftPattern
  value.patternKind = kind
  value.child = child
  ## Unary constructors neither create nor remove holes; induction gives the
  ## count equality below directly from child.hereCount.
  value.hereCount = tree.node(child).hereCount
  appendNode(tree, value)

proc newTuple(
    tree: var LiftPatternTree;
    items: seq[LiftTupleItem]
): LiftPatternId =
  assert items.len > 0
  var value: LiftPattern
  value.patternKind = lpkTuple
  value.items = items
  value.hereCount = 0
  ## Loop visits every child exactly once. Sum therefore equals tuple hole
  ## count by induction over items.
  for item in items:
    assert tree.hasNode(item.patternId)
    value.hereCount += tree.node(item.patternId).hereCount
  appendNode(tree, value)

proc newObject(
    tree: var LiftPatternTree;
    typeName: string;
    typeExpr: NimNode;
    members: seq[LiftObjectMember]
): LiftPatternId =
  assert typeName.len > 0
  assert not typeExpr.isNil
  assert members.len > 0
  var value: LiftPattern
  value.patternKind = lpkObject
  value.typeName = typeName
  value.typeExpr = typeExpr
  value.members = members
  value.hereCount = 0
  ## Tags and wildcards contain no recursive pattern. Only lomPattern
  ## contributes, so this sum is exactly object-tree hole count.
  for member in members:
    if member.kind == lomPattern:
      assert tree.hasNode(member.patternId)
      value.hereCount += tree.node(member.patternId).hereCount
  appendNode(tree, value)

proc parseLiftPatternNode(
    root: NimNode;
    tree: var LiftPatternTree
): LiftPatternId

proc isTypeArgument(node: NimNode): bool

proc parseWrapper(
    tree: var LiftPatternTree;
    constructor, value: NimNode
): LiftPatternId =
  if constructor.kind notin nameKinds:
    error("lift wrapper name must be `seq` or `Option`", constructor)
  let child = parseLiftPatternNode(value, tree)
  case constructor.repr
  of "seq":
    newUnary(tree, lpkSeq, child)
  of "Option":
    newUnary(tree, lpkOption, child)
  else:
    error("unknown lift wrapper: " & constructor.repr, constructor)

proc isTypeName(node: NimNode): bool =
  ## Compare normalized full spelling. Checking only the first quoted part
  ## would mistake a valid multi-part type name for the `_` wildcard.
  node.nameNode and node.nameText != "_"

proc isBracketOperator(node: NimNode): bool =
  if node.kind notin {nnkOpenSymChoice, nnkClosedSymChoice}:
    return false
  ## Source semantic ASTs keep all overload candidates in this choice node;
  ## candidate count is compiler-version dependent. Membership of `[]`, not
  ## length, proves this is the generic-instantiation operator.
  node.isOperator("[]")

proc isOperator(node: NimNode; spelling: string): bool =
  case node.kind
  of nnkIdent, nnkSym, nnkAccQuoted:
    node.repr == spelling
  of nnkOpenSymChoice, nnkClosedSymChoice:
    ## Overloaded source operators use the same choice representation as `[]`.
    for candidate in node:
      if candidate.kind in nameKinds and candidate.repr == spelling:
        return true
    false
  else:
    false

proc typeExpressionText(node: NimNode): string =
  ## `repr` cannot render some compiler-generated `[](T, A)` nodes. Render
  ## that one normalized form explicitly; all other admitted heads are safe
  ## source-shaped nodes and retain normal Nim spelling.
  if node.kind == nnkCall and node.len >= 3 and node[0].isBracketOperator:
    result = node[1].repr & "["
    for index in 2 ..< node.len:
      if index > 2:
        result.add(", ")
      result.add(node[index].repr)
    result.add("]")
  else:
    result = node.repr

proc allTypeArguments(node: NimNode; first: int): bool =
  ## First-failure scan visits each argument once; true means all satisfy the
  ## same recursive predicate used by both generic-head encodings.
  for index in first ..< node.len:
    if not node[index].isTypeArgument:
      return false
  true

proc isTypeExpr(node: NimNode): bool =
  ## Type head grammar: name, dotted name, or generic type expression. This
  ## excludes `(foo)`, calls, and operators while still accepting `Box[int]`
  ## and static literal arguments such as `Foo[3, int]`.
  case node.kind
  of nnkIdent, nnkSym, nnkAccQuoted:
    node.isTypeName
  of nnkDotExpr:
    node.len == 2 and node[0].isTypeExpr and node[1].isTypeName
  of nnkBracketExpr:
    node.len >= 2 and node[0].isTypeExpr and node.allTypeArguments(1)
  of nnkCall:
    ## Semantic NimNode trees may encode `Foo[int]` as `[](Foo, int)`.
    ## Admit only that compiler-generated spelling, never an ordinary call.
    node.len >= 3 and node[0].isBracketOperator and node[1].isTypeExpr and
      node.allTypeArguments(2)
  else:
    false

proc isTypeArgument(node: NimNode): bool =
  if node.isTypeExpr:
    return true
  if node.isLiteral:
    return true
  case node.kind
  of nnkPrefix:
    node.isSignedNumeric
  of nnkInfix:
    node.len == 3 and node[0].isOperator("..") and
      node[1].isTypeArgument and node[2].isTypeArgument
  of nnkTupleConstr:
    var itemsOk = node.len > 0
    for child in node:
      if child.kind == nnkExprColonExpr:
        itemsOk = itemsOk and child.len == 2 and child[0].nameNode and
          child[1].isTypeArgument
      else:
        itemsOk = itemsOk and child.isTypeArgument
    itemsOk
  of nnkPar:
    node.len == 1 and node[0].isTypeArgument
  else:
    false

proc sameName(left, right: string): bool =
  ## Nim identifier equality ignores underscores and internal case changes.
  cmpIgnoreStyle(left, right) == 0

proc parseTuple(
    tree: var LiftPatternTree;
    node: NimNode
): LiftPatternId =
  if node.len == 0:
    error("lift tuple pattern cannot be empty", node)

  var items: seq[LiftTupleItem]
  var sawNamed = false

  for child in node:
    if child.kind == nnkExprColonExpr:
      if child.len != 2:
        error("malformed named lift tuple item", child)
      if items.len > 0 and not sawNamed:
        error("lift tuple cannot mix named and positional items", child)
      sawNamed = true
      let itemName = nameText(child[0])
      for prior in items:
        if sameName(prior.name, itemName):
          error("duplicate lift tuple label: " & itemName, child[0])
      items.add(LiftTupleItem(
        name: itemName,
        patternId: parseLiftPatternNode(child[1], tree)
      ))
    else:
      if sawNamed:
        error("lift tuple cannot mix named and positional items", child)
      items.add(LiftTupleItem(patternId: parseLiftPatternNode(child, tree)))

  ## The loop consumed each nnkTupleConstr child once; newTuple then proves
  ## the structural count invariant for the completed result.
  newTuple(tree, items)

proc parseObject(
    tree: var LiftPatternTree;
    node: NimNode
): LiftPatternId =
  ## `T(field: S)` is nnkObjConstr. Empty `T()` and `T(field = S)` are
  ## nnkCall, intentionally rejected by parseLiftPattern.
  if node.len < 2:
    error("lift object pattern needs at least one field", node)
  if not node[0].isTypeExpr:
    error("lift object head must be a type expression", node[0])

  var members: seq[LiftObjectMember]
  for index in 1 ..< node.len:
    let member = node[index]
    if member.kind != nnkExprColonExpr or member.len != 2:
      error("lift object members require `field: pattern`", member)

    let fieldName = nameText(member[0])
    for prior in members:
      if sameName(prior.name, fieldName):
        error("duplicate lift object field: " & fieldName, member[0])

    let value = withoutParens(member[1])
    if value.isWildcard:
      ## Keep ambiguity for type-aware elaboration: ordinary field keep versus
      ## variant discriminator wildcard.
      members.add(LiftObjectMember(name: fieldName, kind: lomWildcard))
    elif value.isHere:
      members.add(LiftObjectMember(
        name: fieldName,
        kind: lomPattern,
        patternId: newLeaf(tree, lpkHere)
      ))
    elif value.isTagAtom:
      members.add(LiftObjectMember(
        name: fieldName,
        kind: lomTag,
        tag: LiftTag(text: value.repr, expression: copyNimTree(value))
      ))
    else:
      members.add(LiftObjectMember(
        name: fieldName,
        kind: lomPattern,
        patternId: parseLiftPatternNode(value, tree)
      ))

  ## Every source member has one output member, in source order. No member
  ## can disappear or be duplicated after this point.
  newObject(tree, typeExpressionText(node[0]), copyNimTree(node[0]), members)

proc parseLiftPatternNode(
    root: NimNode;
    tree: var LiftPatternTree
): LiftPatternId =
  if root.isNil:
    error("nil is not a lift pattern")

  let node = withoutParens(root)

  ## Termination proof: every recursive call below receives a strict child of
  ## node. NimNode trees are finite, so structural descent terminates.
  case node.kind
  of nnkIdent, nnkSym:
    if node.isWildcard:
      newLeaf(tree, lpkKeep)
    elif node.isHere:
      newLeaf(tree, lpkHere)
    else:
      error("unknown lift pattern identifier: " & node.repr, node)
  of nnkBracketExpr:
    if node.len != 2:
      error("lift wrapper expects exactly one pattern argument", node)
    parseWrapper(tree, node[0], node[1])
  of nnkCall:
    if node.len != 3 or not node[0].isBracketOperator:
      error("invalid lift pattern node: nnkCall", node)
    ## Type-context semantic analysis may normalize `C[S]` to
    ## `[](C, S)`. It carries the same one-child wrapper proof as brackets.
    parseWrapper(tree, node[1], node[2])
  of nnkTupleConstr:
    parseTuple(tree, node)
  of nnkObjConstr:
    parseObject(tree, node)
  else:
    error("invalid lift pattern node: " & $node.kind, node)

proc parseLiftPattern*(root: NimNode): LiftPatternTree =
  var tree = LiftPatternTree(root: invalidLiftPatternId)
  tree.root = parseLiftPatternNode(root, tree)
  ## Root is assigned only after successful structural parsing. Every returned
  ## child ID was validated when its parent node was appended.
  assert tree.hasNode(tree.root)
  tree

proc rootId*(tree: LiftPatternTree): LiftPatternId =
  assert tree.hasNode(tree.root)
  tree.root

proc nodeCount*(tree: LiftPatternTree): int =
  tree.nodes.len

proc rootPattern*(tree: LiftPatternTree): LiftPattern =
  tree.node(tree.root)

proc patternKind*(pattern: LiftPattern): LiftPatternKind =
  pattern.patternKind

proc patternKind*(tree: LiftPatternTree): LiftPatternKind =
  tree.rootPattern.patternKind

proc hereCount*(pattern: LiftPattern): int =
  pattern.hereCount

proc hereCount*(tree: LiftPatternTree): int =
  tree.rootPattern.hereCount

proc childId*(pattern: LiftPattern): LiftPatternId =
  assert pattern.patternKind in {lpkSeq, lpkOption}
  pattern.child

proc child*(tree: LiftPatternTree; parent: LiftPatternId): LiftPattern =
  let node = tree.node(parent)
  tree.node(node.childId)

proc tupleItemCount*(pattern: LiftPattern): int =
  assert pattern.patternKind == lpkTuple
  pattern.items.len

proc tupleItem*(pattern: LiftPattern; index: int): LiftTupleItem =
  assert pattern.patternKind == lpkTuple
  assert index in 0 ..< pattern.items.len
  pattern.items[index]

proc objectTypeName*(pattern: LiftPattern): string =
  assert pattern.patternKind == lpkObject
  pattern.typeName

proc objectTypeExpr*(pattern: LiftPattern): NimNode =
  assert pattern.patternKind == lpkObject
  copyNimTree(pattern.typeExpr)

proc objectMemberCount*(pattern: LiftPattern): int =
  assert pattern.patternKind == lpkObject
  pattern.members.len

proc objectMember*(pattern: LiftPattern; index: int): LiftObjectMember =
  assert pattern.patternKind == lpkObject
  assert index in 0 ..< pattern.members.len
  pattern.members[index]

proc tupleItemPatternId*(item: LiftTupleItem): LiftPatternId =
  item.patternId

proc tupleItemPattern*(tree: LiftPatternTree; item: LiftTupleItem): LiftPattern =
  tree.node(item.patternId)

proc objectMemberName*(member: LiftObjectMember): string =
  member.name

proc objectMemberKind*(member: LiftObjectMember): LiftObjectMemberKind =
  member.kind

proc objectMemberPatternId*(member: LiftObjectMember): LiftPatternId =
  assert member.kind == lomPattern
  member.patternId

proc objectMemberPattern*(
    tree: LiftPatternTree;
    member: LiftObjectMember
): LiftPattern =
  assert member.kind == lomPattern
  tree.node(member.patternId)

proc objectMemberTag*(member: LiftObjectMember): LiftTag =
  assert member.kind == lomTag
  member.tag

proc tagExpression*(tag: LiftTag): NimNode =
  assert not tag.expression.isNil
  copyNimTree(tag.expression)

when isMainModule:
  ## Sanity checks only. Correctness comes from grammar coverage, strict node
  ## admission, recursive-descent termination, and count invariants above.
  macro check(pattern: untyped): untyped =
    let parsed = parseLiftPattern(pattern)
    echo pattern.repr, " => ", $parsed.patternKind,
      ", hereCount=", $parsed.hereCount
    result = newEmptyNode()

  check(here)
  check((here, here))
  check((x: _, y: Option[seq[here]]))
  check(User(name: _, address: here))
  check(User(`field-name`: here))
  check(`_ - Foo`(value: here))
  check(Message(kind: text, body: here))
