## Formal specification for `parseItPath`.
##
## Executable compile-time tests follow specification. Cases cover distinct
## AST and lexical boundaries.
##
## == Input contract ==
##
## `parseItPath(node)` accepts exactly one outer `nnkBracket` node with
## `node.len > 0`. Each direct child of that node is one selector group,
## represented by a nonempty `nnkBracket` node. Empty or non-bracket outer
## input, and empty or non-bracket groups, are rejected with a compile-time
## error. Grammar notation below describes AST shape; no syntax sugar,
## evaluation, constant folding, or implicit unwrapping is performed.
##
## Group selector grammar:
##
##   path       ::= `[` group+ `]`
##   group      ::= `[` selector+ `]`
##   selector   ::= integer-literal
##               | name
##               | integer-literal `..` integer-literal
##   name       ::= `nnkIdent` | `nnkSym`
##               | `nnkAccQuoted`(`nnkIdent` | `nnkSym`)+
##
## Accepted integer literals are exactly these Nim integer literal node kinds:
## `nnkIntLit`, `nnkInt8Lit`, `nnkInt16Lit`, `nnkInt32Lit`, and `nnkInt64Lit`.
## Unsigned literal kinds and all other AST kinds are rejected. Negative values
## are accepted when represented by one of the accepted literal kinds; a
## manually represented `nnkPrefix` negative expression is rejected. Index
## values and range bounds equal the source literal node's `intVal` result;
## parser does not normalize, clamp, or otherwise transform that value.
##
## A plain `nnkIdent` or `nnkSym` name has spelling `node.strVal`. An
## `nnkAccQuoted` name is valid for successful parsing only when it has at
## least one child and every child is `nnkIdent` or `nnkSym`; its field spelling
## is concatenation of each child `strVal` (not recursive `nameText`
## expansion). Empty acc-quoted names and empty resulting field spellings are
## rejected. Output preserves child `strVal` case, punctuation, and order only;
## raw source spelling and whitespace are not reconstructed. Nested acc-quoted
## children are malformed and must never produce a successful selector.
##
## Range syntax requires `node.kind == nnkInfix`, `node.len == 3`, and an
## operator child of kind `nnkIdent` or `nnkSym` whose `strVal == ".."`. Both
## bound children must be accepted integer literals. `first` and `last` equal
## their bound `intVal` results. `first` must be less than or equal to `last`;
## reversed ranges are rejected. Range bounds may be negative when represented
## by accepted literal nodes. Other operator-node kinds are not Nim's ordinary
## infix AST representation and are rejected, even when they expose `strVal`.
##
## == Group constraints ==
##
## A group is numeric when every selector is an index or range; it is a field
## group when every selector is a field. Numeric and field selectors may not
## appear together in one group. A range may not appear with any other
## selector, including another range. Thus a group contains either one range,
## one or more indexes, or one or more fields. Duplicate indexes and duplicate
## field names are valid and remain duplicated in output.
##
## Invalid selector nodes, malformed ranges, invalid names, empty groups, and
## all constraint violations are rejected with a compile-time failure. No
## selector is evaluated, resolved, or checked against a Nim type. Malformed
## nested accquoted names or range operators have no successful-return or
## diagnostic-message contract beyond producing no `ItPath`.
##
## == Output contract ==
##
## Successful parsing returns `ItPath(groups: groups)` satisfying:
##
## * `groups.len == node.len` and `groups.len >= 1`;
## * `groups[i].selectors.len == input_group[i].len` and is at least 1;
## * one output group exists for each outer input child, in exact order;
## * one output selector exists for each group child, in exact order;
## * integer selector becomes `ItSelector(kind: itsIndex, index: value)`;
## * name selector becomes `ItSelector(kind: itsField, field: spelling)`;
## * range selector becomes `ItSelector(kind: itsRange, first: first,
##   last: last)`;
## * selector kind and case payload agree by `ItSelector` construction.
##
## No input group or selector is dropped, duplicated, reordered, evaluated, or
## type-resolved. Result contains only syntax and literal payloads. Parsing
## reads, but does not mutate, input AST. Parser invariants are established on
## every successful return; malformed input does not return an `ItPath`.

## == Traversal ==
##
## Parser visits outer groups in AST child order and selectors within each group
## in AST child order. Positive output-order tests pin this observable part of
## the contract. Diagnostic precedence is intentionally not a contract: Nim's
## `compiles` predicate exposes only success/failure, not stable error text.

## == Rejection diagnostics ==
##
## Future negative tests may match these current diagnostic messages:
##
## * invalid outer shape: `it path must contain at least one selector group`;
## * invalid group shape: `it selector group must be a nonempty bracket group`;
## * malformed acc-quoted name: `malformed accquoted it field selector`;
## * empty field spelling: `it field selector cannot be empty`;
## * non-integer range bound: `it index and range bounds require integer literals`;
## * reversed range: `it range must have nondecreasing bounds`;
## * any other invalid selector: `invalid it selector: expected integer, field, or integer range`;
## * mixed numeric/field group: `it selector group cannot mix indexes and fields`;
## * range combined with another selector: `it range cannot be combined with other selectors`.
##
## Nested accquoted children and invalid range-operator nodes have no
## successful-return contract; tests do not pin compiler diagnostic wording.
##
## == Test families ==
##
## Test one valid path for each selector kind; exact group/selector cardinality;
## multiple ordered groups; multiple and duplicate indexes; multiple and
## duplicate fields; plain, symbol, and nonempty acc-quoted names; preserved
## spelling; singleton ranges; ranges in separate groups; boundary int64
## literals; standalone non-integer selector rejection; negative literal acceptance
## and manually built negative-prefix rejection; output order and payloads; no
## AST mutation; rejection classes;
## and every rejection listed above, including
## unsigned literals, mixed group kinds, range combinations, reversed ranges,
## malformed names/ranges, empty groups, and invalid outer shapes.

import std/macros
import it_projection

proc assert_selector_equal(actual, expected: ItSelector) {.compileTime.} =
  doAssert actual.kind == expected.kind
  case expected.kind
  of itsIndex:
    doAssert actual.index == expected.index
  of itsField:
    doAssert actual.field == expected.field
  of itsRange:
    doAssert actual.first == expected.first
    doAssert actual.last == expected.last

macro assert_index(path: untyped; expected: static[int64]): untyped =
  let parsed = parseItPath(path)
  doAssert parsed.groups.len == 1
  doAssert parsed.groups[0].selectors.len == 1
  parsed.groups[0].selectors[0].assert_selector_equal(ItSelector(
    kind: itsIndex, index: expected))
  result = newEmptyNode()

macro assert_range(path: untyped; expected_first, expected_last: static[int64]): untyped =
  let parsed = parseItPath(path)
  doAssert parsed.groups.len == 1
  doAssert parsed.groups[0].selectors.len == 1
  parsed.groups[0].selectors[0].assert_selector_equal(ItSelector(
    kind: itsRange, first: expected_first, last: expected_last))
  result = newEmptyNode()

macro assert_source_layout(path: untyped): untyped =
  ## Independent oracle for source AST group and selector order.
  let parsed = parseItPath(path)
  doAssert parsed.groups.len == 3
  doAssert parsed.groups[0].selectors.len == 3
  doAssert parsed.groups[0].selectors[0].kind == itsIndex
  doAssert parsed.groups[0].selectors[0].index == 1
  doAssert parsed.groups[0].selectors[1].kind == itsIndex
  doAssert parsed.groups[0].selectors[1].index == 2
  doAssert parsed.groups[0].selectors[2].kind == itsIndex
  doAssert parsed.groups[0].selectors[2].index == 3
  doAssert parsed.groups[1].selectors.len == 2
  doAssert parsed.groups[1].selectors[0].kind == itsField
  doAssert parsed.groups[1].selectors[0].field == "first"
  doAssert parsed.groups[1].selectors[1].kind == itsField
  doAssert parsed.groups[1].selectors[1].field == "second"
  doAssert parsed.groups[2].selectors.len == 1
  doAssert parsed.groups[2].selectors[0].kind == itsRange
  doAssert parsed.groups[2].selectors[0].first == 4
  doAssert parsed.groups[2].selectors[0].last == 7
  result = newEmptyNode()

macro assert_field(path: untyped; expected: static[string]): untyped =
  let parsed = parseItPath(path)
  doAssert parsed.groups.len == 1
  doAssert parsed.groups[0].selectors.len == 1
  parsed.groups[0].selectors[0].assert_selector_equal(ItSelector(
    kind: itsField, field: expected))
  result = newEmptyNode()

macro parse_only(path: untyped): untyped =
  discard parseItPath(path)
  result = newEmptyNode()

macro assert_symbol_path(): untyped =
  let symbol = genSym(nskLet, "field_symbol")
  let path = newTree(nnkBracket, newTree(nnkBracket, symbol))
  let parsed = parseItPath(path)
  doAssert parsed.groups.len == 1
  doAssert parsed.groups[0].selectors.len == 1
  doAssert parsed.groups[0].selectors[0].kind == itsField
  doAssert parsed.groups[0].selectors[0].field == symbol.strVal
  result = newEmptyNode()

macro assert_literal_kind(kind: static[NimNodeKind]; value: static[int64]): untyped =
  let literal = newNimNode(kind)
  literal.intVal = value
  let parsed = parseItPath(newTree(nnkBracket, newTree(nnkBracket, literal)))
  parsed.groups[0].selectors[0].assert_selector_equal(ItSelector(
    kind: itsIndex, index: value))
  result = newEmptyNode()

macro assert_accquoted_parts(): untyped =
  let quoted = newTree(nnkAccQuoted, ident("left"), ident("-"), ident("right"))
  let parsed = parseItPath(newTree(nnkBracket, newTree(nnkBracket, quoted)))
  parsed.groups[0].selectors[0].assert_selector_equal(ItSelector(
    kind: itsField, field: "left-right"))
  result = newEmptyNode()

macro assert_accquoted_symbol_part(): untyped =
  let quoted = newTree(nnkAccQuoted, genSym(nskLet, "sym_part"), ident("tail"))
  let parsed = parseItPath(newTree(nnkBracket, newTree(nnkBracket, quoted)))
  let expected = quoted[0].strVal & "tail"
  parsed.groups[0].selectors[0].assert_selector_equal(ItSelector(
    kind: itsField, field: expected))
  result = newEmptyNode()

macro assert_symbol_range_operator(range: typed): untyped =
  # Typed Nim AST resolves an overloaded infix operator to `nnkSym`; this
  # exercises that accepted representation without fabricating an invalid
  # symbol node (`strVal=` is unavailable for `nnkSym`).
  doAssert range.kind == nnkInfix
  doAssert range[0].kind == nnkSym
  let parsed = parseItPath(newTree(nnkBracket, newTree(nnkBracket, range)))
  parsed.groups[0].selectors[0].assert_selector_equal(ItSelector(
    kind: itsRange, first: 2, last: 4))
  result = newEmptyNode()

macro assert_explicit_payloads(): untyped =
  ## Independent oracle: expected values are constructed here, never reparsed.
  let range = newTree(nnkInfix, ident(".."), newIntLitNode(1),
    newIntLitNode(3))
  let path = newTree(nnkBracket,
    newTree(nnkBracket, newIntLitNode(7), newIntLitNode(7)),
    newTree(nnkBracket, ident("alpha"), ident("same"), ident("same"),
      ident("beta")),
    newTree(nnkBracket, range))
  let parsed = parseItPath(path)
  doAssert parsed.groups.len == 3
  doAssert parsed.groups[0].selectors.len == 2
  doAssert parsed.groups[0].selectors[0].kind == itsIndex
  doAssert parsed.groups[0].selectors[0].index == 7
  doAssert parsed.groups[0].selectors[1].kind == itsIndex
  doAssert parsed.groups[0].selectors[1].index == 7
  doAssert parsed.groups[1].selectors.len == 4
  doAssert parsed.groups[1].selectors[0].kind == itsField
  doAssert parsed.groups[1].selectors[0].field == "alpha"
  doAssert parsed.groups[1].selectors[1].kind == itsField
  doAssert parsed.groups[1].selectors[1].field == "same"
  doAssert parsed.groups[1].selectors[2].kind == itsField
  doAssert parsed.groups[1].selectors[2].field == "same"
  doAssert parsed.groups[1].selectors[3].kind == itsField
  doAssert parsed.groups[1].selectors[3].field == "beta"
  doAssert parsed.groups[2].selectors.len == 1
  doAssert parsed.groups[2].selectors[0].kind == itsRange
  doAssert parsed.groups[2].selectors[0].first == 1
  doAssert parsed.groups[2].selectors[0].last == 3
  result = newEmptyNode()

macro assert_ast_unchanged(path: untyped): untyped =
  let before = copyNimTree(path)
  discard parseItPath(path)
  doAssert path == before
  result = newEmptyNode()

macro reject_generated(case_id: static[int]): untyped =
  var bad: NimNode
  case case_id
  of 0:
    bad = newTree(nnkBracket)
  of 1:
    bad = newTree(nnkPar)
  of 2:
    bad = newTree(nnkBracket, newTree(nnkBracket))
  of 3:
    bad = newTree(nnkBracket, newTree(nnkBracket, newTree(nnkPar)))
  of 4:
    bad = newTree(nnkBracket, newTree(nnkBracket, newFloatLitNode(1.0)))
  of 5:
    bad = newTree(nnkBracket, newTree(nnkBracket, newStrLitNode("field")))
  of 6:
    bad = newTree(nnkBracket, newTree(nnkBracket, newNimNode(nnkUInt8Lit)))
  of 7:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident(".."), newIntLitNode(2), newIntLitNode(1))))
  of 8:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident("+"), newIntLitNode(1), newIntLitNode(2))))
  of 9:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident(".."), newIntLitNode(1), newIntLitNode(2),
        newIntLitNode(3))))
  of 10:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident(".."), newFloatLitNode(1.0), newIntLitNode(2))))
  of 11:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident(".."), newIntLitNode(1),
        newNimNode(nnkUInt8Lit))))
  of 12:
    bad = newTree(nnkBracket, newTree(nnkBracket, ident("field"),
      newIntLitNode(0)))
  of 13:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident(".."), newIntLitNode(1), newIntLitNode(2)),
      newIntLitNode(3)))
  of 14:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident(".."), newIntLitNode(1), newIntLitNode(2)),
      ident("field")))
  of 15:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkAccQuoted, newNimNode(nnkAccQuoted))))
  of 16:
    # A negative literal written as an expression is not an integer literal
    # node, even though its source spelling looks numeric.
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkPrefix, ident("-"), newIntLitNode(1))))
  of 17:
    # Range parsing must not accept an operator node without strVal.
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, newNimNode(nnkEmpty), newIntLitNode(1),
        newIntLitNode(2))))
  of 18:
    # Accquoted children are flat name parts, not recursively quoted names.
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkAccQuoted, newTree(nnkAccQuoted, ident("x")))))
  of 19:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident(".."), newIntLitNode(1))))
  of 20:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkCall, ident("f"), newIntLitNode(1))))
  of 21:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkCurly, newIntLitNode(1))))
  of 22:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkBracketExpr, ident("a"), newIntLitNode(1))))
  of 23:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkDotExpr, ident("a"), ident("b"))))
  of 24:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkAccQuoted, newIntLitNode(1))))
  of 25:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkAsgn, ident("field"), newIntLitNode(1))))
  of 26:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkObjConstr, ident("T"))))
  of 27:
    bad = newTree(nnkBracket, newTree(nnkBracket, newNimNode(nnkUInt64Lit)))
  of 28:
    bad = newTree(nnkBracket, newTree(nnkBracket, newNimNode(nnkCharLit)))
  of 29:
    bad = newTree(nnkBracket, newTree(nnkBracket, newNimNode(nnkNilLit)))
  of 30:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkRange, newIntLitNode(1), newIntLitNode(2))))
  of 31:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkPostfix, ident("!"), newIntLitNode(1))))
  of 32:
    bad = newTree(nnkBracket, newTree(nnkBracket, newTree(nnkAccQuoted)))
  of 33:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkPragmaExpr, newIntLitNode(1), newTree(nnkPragma))))
  of 34:
    # A string literal is not Nim's ordinary infix-operator AST node.
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, newStrLitNode(".."), newIntLitNode(1),
        newIntLitNode(2))))
  else:
    bad = newTree(nnkBracket, newTree(nnkBracket,
      newTree(nnkInfix, ident(".."), newIntLitNode(1), newIntLitNode(2),
        newIntLitNode(3))))
  discard parseItPath(bad)
  result = newEmptyNode()

# Positive: actual Nim expression grammar, lexical forms, and AST payloads.
assert_index([[0]], 0)
assert_source_layout([[1, 2, 3], [first, second], [4 .. 7]])
assert_index([[1_000]], 1000)
assert_index([[0x2A]], 42)
assert_index([[0o52]], 42)
assert_index([[0b101010]], 42)
assert_index([[42'i8]], 42)
assert_index([[42'i16]], 42)
assert_index([[42'i32]], 42)
assert_index([[42'i64]], 42)
assert_index([[42i8]], 42)
assert_index([[0X2A]], 42)
assert_index([[0B1010]], 10)
assert_index([[42'I8]], 42)
assert_index([[42'I16]], 42)
assert_index([[42'I32]], 42)
assert_index([[42'I64]], 42)
assert_index([[0x7f'i8]], 127)
assert_index([[0o10'i16]], 8)
assert_index([[0b11'i32]], 3)
assert_index([[4'i64]], 4)
assert_index([[-1]], -1)
assert_index([[-0x2]], -2)
assert_index([[-128'i8]], -128)
assert_index([[-9223372036854775807'i64]], -9223372036854775807'i64)
assert_index([[-9223372036854775808'i64]], -9223372036854775808'i64)
assert_index([[9223372036854775807'i64]], 9223372036854775807'i64)
assert_range([[1 .. 3]], 1, 3)
assert_range([[-3 .. 2]], -3, 2)
assert_range([[-9223372036854775808'i64 .. 9223372036854775807'i64]],
  -9223372036854775808'i64, 9223372036854775807'i64)
assert_range([[-128'i8 .. 127'i8]], -128, 127)
assert_range([[-32768'i16 .. 32767'i16]], -32768, 32767)
assert_range([[-2147483648'i32 .. 2147483647'i32]], -2147483648, 2147483647)
assert_field([[`field-name`]], "field-name")
assert_field([[`var`]], "var")
assert_field([[`a b`]], "ab")
assert_field([[`a+b*c`]], "a+b*c")
assert_field([[`left/right`]], "left/right")
assert_field([[snake_case]], "snake_case")
assert_field([[Δ]], "Δ")
assert_accquoted_parts()
assert_accquoted_symbol_part()
assert_symbol_range_operator(2 .. 4)
assert_explicit_payloads()
assert_symbol_path()
assert_ast_unchanged([[0, 3], [`x-y`], [2 .. 4], [field]])

# Positive: every accepted integer-literal AST kind, including negative value.
assert_literal_kind(nnkIntLit, 0)
assert_literal_kind(nnkInt8Lit, -128)
assert_literal_kind(nnkInt16Lit, -32768)
assert_literal_kind(nnkInt32Lit, -2147483648'i64)
assert_literal_kind(nnkInt64Lit, -9223372036854775807'i64)

# Negative parser cases: synthetic ASTs exercise parseItPath directly. The
# compiler boolean proves rejection only; it deliberately does not prove exact
# diagnostic text or distinguish clean error from malformed-node failure.
static:
  # Keep case ids literal: `compiles` does not instantiate a macro reached
  # only through a static loop variable, so an apparent loop can silently
  # leave this generated rejection helper unused.
  doAssert not compiles(reject_generated(0))
  doAssert not compiles(reject_generated(1))
  doAssert not compiles(reject_generated(2))
  doAssert not compiles(reject_generated(3))
  doAssert not compiles(reject_generated(4))
  doAssert not compiles(reject_generated(5))
  doAssert not compiles(reject_generated(6))
  doAssert not compiles(reject_generated(7))
  doAssert not compiles(reject_generated(8))
  doAssert not compiles(reject_generated(9))
  doAssert not compiles(reject_generated(10))
  doAssert not compiles(reject_generated(11))
  doAssert not compiles(reject_generated(12))
  doAssert not compiles(reject_generated(13))
  doAssert not compiles(reject_generated(14))
  doAssert not compiles(reject_generated(15))
  doAssert not compiles(reject_generated(16))
  doAssert not compiles(reject_generated(17))
  doAssert not compiles(reject_generated(18))
  doAssert not compiles(reject_generated(19))
  doAssert not compiles(reject_generated(20))
  doAssert not compiles(reject_generated(21))
  doAssert not compiles(reject_generated(22))
  doAssert not compiles(reject_generated(23))
  doAssert not compiles(reject_generated(24))
  doAssert not compiles(reject_generated(25))
  doAssert not compiles(reject_generated(26))
  doAssert not compiles(reject_generated(27))
  doAssert not compiles(reject_generated(28))
  doAssert not compiles(reject_generated(29))
  doAssert not compiles(reject_generated(30))
  doAssert not compiles(reject_generated(31))
  doAssert not compiles(reject_generated(32))
  doAssert not compiles(reject_generated(33))
  doAssert not compiles(reject_generated(34))
  doAssert not compiles(parse_only([[1'u8]]))
  doAssert not compiles(parse_only([[1'u]]))
  doAssert not compiles(parse_only([[1'u16]]))
  doAssert not compiles(parse_only([[1'u32]]))
  doAssert not compiles(parse_only([[1'u64]]))
  doAssert not compiles(parse_only([[1.0]]))
  doAssert not compiles(parse_only([[1.0'f32]]))
  doAssert not compiles(parse_only([[1.0'f64]]))
  doAssert not compiles(parse_only([[1e3]]))
  doAssert not compiles(parse_only([[x - 1]]))
  doAssert not compiles(parse_only([[+1]]))
  doAssert not compiles(parse_only([[1 ..< 2]]))
  doAssert not compiles(parse_only([[1'custom]]))
  doAssert not compiles(parse_only([["field"]]))
  doAssert not compiles(parse_only([[r"field"]]))
  doAssert not compiles(parse_only([["""field"""]]))
  doAssert not compiles(parse_only([['x']]))
  doAssert not compiles(parse_only([['\n']]))
  doAssert not compiles(parse_only([[nil]]))
  doAssert not compiles(parse_only([[(1, 2)]]))
  doAssert not compiles(parse_only([[{1, 2}]]))
  doAssert not compiles(parse_only([[(1 + 2)]]))
  doAssert not compiles(parse_only([[1 .. 2, 3 .. 4]]))
  doAssert not compiles(parse_only([[1 .. 2, field]]))
  doAssert not compiles(parse_only([[field, 1]]))
  doAssert not compiles(parse_only([[1 .. 2, 3 .. 4, 5]]))
  doAssert not compiles(parse_only([[1, `field`]]))
  doAssert not compiles(parse_only([[`field`, `other`], [1 .. 2, 3]]))
