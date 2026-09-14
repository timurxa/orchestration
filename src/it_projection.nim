import std/macros

## Syntax-only representation of the `it` projection grammar.
##
## Proof boundary:
## * this module parses only the raw path stored in `it_data`;
## * no selector is evaluated or resolved against a Nim symbol here;
## * type-aware elaboration must later validate the path against its input type.

type
  ItSelectorKind* = enum
    itsIndex
    itsField
    itsRange

  ItSelector* = object
    ## Case payload makes selector kind and payload agree by construction.
    case kind*: ItSelectorKind
    of itsIndex:
      index*: int64
    of itsField:
      field*: string
    of itsRange:
      first*, last*: int64

  ItSelectorGroup* = object
    ## Parser invariant: selectors is never empty.
    selectors*: seq[ItSelector]

  ItPath* = object
    ## Parser invariant: groups is never empty; each group is nonempty.
    groups*: seq[ItSelectorGroup]

proc isIntegerLiteral(node: NimNode): bool =
  node.kind in {
    nnkIntLit, nnkInt8Lit, nnkInt16Lit, nnkInt32Lit, nnkInt64Lit
  }

proc isNameNode(node: NimNode): bool =
  node.kind in {nnkIdent, nnkSym, nnkAccQuoted}

proc nameText(node: NimNode): string =
  if not node.isNameNode:
    error("it field selector expects an identifier", node)
  ## Accquoted identifiers are wrappers around a flat sequence of identifier
  ## parts. Restricting parts here prevents malformed nested wrappers from
  ## being mistaken for field spelling and keeps successful output exact.
  if node.kind == nnkAccQuoted:
    if node.len == 0:
      error("malformed accquoted it field selector", node)
    for part in node:
      if part.kind notin {nnkIdent, nnkSym}:
        error("malformed accquoted it field selector", part)
      result.add part.strVal
  else:
    ## `nnkIdent`/`nnkSym` nodes supplied by Nim carry their spelling in
    ## `strVal`; no normalization is allowed by the syntax-only contract.
    result = node.strVal
  if result.len == 0:
    error("it field selector cannot be empty", node)

proc integerValue(node: NimNode): int64 =
  ## Every accepted signed integer literal has one scalar value. Deliberately
  ## excluding unsigned literal nodes prevents Nim's signed intVal conversion
  ## from silently wrapping values above int64.max.
  if not node.isIntegerLiteral:
    error("it index and range bounds require integer literals", node)
  result = node.intVal

proc parseSelector(node: NimNode): ItSelector =
  if node.isIntegerLiteral:
    return ItSelector(kind: itsIndex, index: node.integerValue)

  if node.isNameNode:
    return ItSelector(kind: itsField, field: node.nameText)

  ## Nim represents an ordinary infix operator with an identifier/symbol
  ## child. Check its kind before reading `strVal`, so arbitrary synthetic
  ## nodes cannot be accepted merely because they expose the same text.
  if node.kind == nnkInfix and node.len == 3 and
      node[0].kind in {nnkIdent, nnkSym} and node[0].strVal == "..":
    let first = node[1].integerValue
    let last = node[2].integerValue
    if first > last:
      error("it range must have nondecreasing bounds", node)
    return ItSelector(kind: itsRange, first: first, last: last)

  error("invalid it selector: expected integer, field, or integer range", node)

proc parseGroup(node: NimNode): ItSelectorGroup =
  if node.kind != nnkBracket or node.len == 0:
    error("it selector group must be a nonempty bracket group", node)

  var selectors: seq[ItSelector]
  for child in node:
    let selector = child.parseSelector

    if selectors.len > 0:
      let priorKind = selectors[0].kind
      let numeric = selector.kind in {itsIndex, itsRange}
      let priorNumeric = priorKind in {itsIndex, itsRange}
      if numeric != priorNumeric:
        error("it selector group cannot mix indexes and fields", child)
      if priorKind == itsRange or selector.kind == itsRange:
        error("it range cannot be combined with other selectors", child)

    selectors.add selector

  ## Loop consumes every child once; the nonempty input precondition therefore
  ## makes the output group nonempty and preserves selector cardinality/order.
  result = ItSelectorGroup(selectors: selectors)

proc parseItPath*(node: NimNode): ItPath =
  ## Structural recursion is finite: this parser descends only through the
  ## finite outer bracket and its immediate group children.
  if node.kind != nnkBracket or node.len == 0:
    error("it path must contain at least one selector group", node)

  var groups: seq[ItSelectorGroup]
  for child in node:
    groups.add child.parseGroup

  ## Every outer child becomes exactly one group; no group is dropped or
  ## duplicated. The nonempty input precondition therefore preserves group
  ## cardinality/order and establishes the output invariant.
  result = ItPath(groups: groups)
