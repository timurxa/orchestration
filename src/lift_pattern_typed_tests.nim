## Formal-specification foundation for `lift_pattern_typed`.
##
## Executable compile-time tests below encode these observable contracts.
##
## == `parse_lift_pattern` input contract ==
##
## `parse_lift_pattern(root)` accepts one Nim AST node. `without_parens` strips
## every outer `nnk_par` layer from each pattern node; each layer must contain
## exactly one child. These pattern-level parentheses are not stored. A
## one-child `nnk_par` nested inside a type argument is separately valid and
## is preserved inside the copied type-expression AST. Object-constructor
## heads are checked directly with `is_type_expr` and are not unwrapped.
##
## Accepted pattern grammar:
##
##   pattern ::= type-expression
##             | `here`
##             | `seq`[`pattern`]
##             | `Option`[`pattern`]
##             | wrapper-call-pattern
##             | tuple-pattern
##             | object-pattern
##
##   wrapper-call-pattern ::= `[]`(`seq`, `pattern`)
##                          | `[]`(`Option`, `pattern`)
##
## At AST level, wrapper patterns are either `nnk_bracket_expr` with head
## `seq`/`Option` and one child, or `nnk_call` with child 0 as the `[]`
## bracket operator, child 1 as wrapper head, and child 2 as the pattern.
##   tuple-pattern ::= (`pattern`, ...)
##                   | (`name`: `pattern`, ...)
##
##   object-pattern ::= `type-expression`(`name`: `pattern`, ...)
##
## A tuple pattern is `nnk_tuple_constr` with length >= 1. Named entries are
## `nnk_expr_colon_expr` nodes with length 2; all entries must be named or all
## unnamed. An object pattern is `nnk_obj_constr` with length >= 2. Child 0 is
## the type expression; children 1.. are `nnk_expr_colon_expr` members of
## length 2.
##
## Tuple and object patterns must contain at least one item. Tuple labels
## must be either absent from every item or present on every item. Labels and
## object field names are identifiers, symbols, or non-empty acc-quoted names;
## duplicate names are rejected case/style-insensitively. Pattern labels and
## object field names have no reserved-name exclusions: plain `here`, `_`,
## `seq`, and `Option` are valid names in these positions.
## For tuple labels and object field names, a non-empty acc-quoted name means
## `nnk_acc_quoted` length > 0 with every child an `nnk_ident` or `nnk_sym`;
## all other acc-quoted shapes are rejected.
##
## Plain identifiers/symbols named `here` become `lpk_here`. Acc-quoted
## `here` is an ordinary type name. Plain identifiers/symbols named `_` are
## rejected; acc-quoted `_` is an ordinary type name.
##
## Wrapper heads are recognized only as plain identifiers/symbols named `seq`
## or `Option`, with exactly one pattern argument. Acc-quoted `seq` and
## `Option` are type names. Wrapper syntax has two AST forms: a bracket
## expression with wrapper head plus one child, or a call whose child 0 is the
## `[]` bracket operator, child 1 is wrapper head, and child 2 is the pattern.
## While `parse_pattern_node` classifies a pattern node, wrapper recognition
## precedes generic type-expression recognition. Thus a bracket/call form with
## wrapper head `seq` or `Option` is subject to wrapper arity and pattern
## validation, even when its children could otherwise match type-expression
## rules. During nested type-argument validation, wrapper heads are not
## special; valid `seq[...]` and `Option[...]` forms are ordinary type
## expressions.
## Wrapper special-casing applies only when `parse_pattern_node` dispatches a
## pattern node. Object-constructor child 0 is checked directly with
## `is_type_expr`; `seq[...]`, `Option[...]`, and bracket-operator call forms
## are ordinary object-head type expressions there.
##
## A type expression is recognized syntactically; no symbol resolution or
## semantic type checking occurs. It is:
##
## * a plain identifier or symbol, except exact spellings `here` and `_`;
## * a non-empty acc-quoted name whose parts are all identifiers or symbols,
##   including acc-quoted `here` and `_`;
## * a dotted expression with exactly two children: left is a type expression
##   and right is a type name. Nested dotted expressions permit longer chains;
## * a bracket expression whose child 0 is a type-expression head and every
##   child from index 1 is a valid type argument; or
## * a call whose child 0 is the `[]` bracket operator, child 1 is a
##   type-expression head, and every child from index 2 is a valid type
##   argument.
## A bracket operator is either an `nnk_bracket` whose `repr` is `[]`, or an
## `nnk_open_sym_choice`/`nnk_closed_sym_choice` node containing an
## `nnk_ident`/`nnk_sym` candidate whose `repr` is `[]`.
## Signed numeric operators use the same spelling predicate for `+`/`-`;
## range operators use it for `..`.
## Any bare `nnk_sym` is a valid type name unless its spelling is plain `here`
## or `_`; this includes operator spellings. Other expression AST kinds reject
## unless explicitly listed as type-argument forms.
##
## Valid type arguments are type expressions, supported literals, signed
## numeric literals, ranges with `..`, non-empty tuple constructions, or
## one-child parenthesized arguments. Literal type arguments are exactly
## `nnk_int_lit`, `nnk_int8_lit`, `nnk_int16_lit`, `nnk_int32_lit`,
## `nnk_int64_lit`, `nnk_uint_lit`, `nnk_uint8_lit`, `nnk_uint16_lit`,
## `nnk_uint32_lit`, `nnk_uint64_lit`, `nnk_float_lit`, `nnk_float32_lit`,
## `nnk_float64_lit`, `nnk_float128_lit`, `nnk_str_lit`, `nnk_rstr_lit`,
## `nnk_triple_str_lit`, `nnk_char_lit`, or `nnk_nil_lit`. No other literal
## AST kind is valid. Tuple-construction children may be
## unnamed type arguments or `name: type-argument` entries in any mixture;
## duplicate tuple-argument names are accepted. Parenthesized type arguments
## may nest arbitrarily; every `nnk_par` layer must contain exactly one child
## that is a valid type argument, and all such layers remain in the stored
## type-expression AST.
## A named type-argument tuple child requires `nnk_expr_colon_expr` length 2,
## a name satisfying `is_name` (`nnk_ident`, `nnk_sym`, or non-empty
## `nnk_acc_quoted` containing only identifiers/symbols), and a valid
## type-argument value. Reserved spellings are accepted; duplicate names are
## accepted.
## A signed numeric argument is `nnk_prefix` length 2, with operator `+` or
## `-` and a numeric-literal child. A range is `nnk_infix` length 3, with
## operator `..` and two valid type-argument children.
##
## All malformed forms are rejected with a compile-time error. Future tests
## should assert rejection for empty tuples/objects, malformed wrappers,
## inconsistent pattern-tuple naming, duplicate pattern names, invalid names,
## plain `_`, empty acc-quoted names, invalid type arguments, and arbitrary
## expressions. A nil root or nil child pattern is also rejected with a
## compile-time error.
##
## == `LiftPatternTree` output contract ==
##
## Successful parsing returns a non-empty tree with a valid `root_id`. Node
## IDs are contiguous, zero-based `LiftPatternId` values. Nodes are appended
## after their children have been parsed; therefore every child ID is smaller
## than its parent ID, every node is reachable from root, and root is the
## final node (`root_id == nodes.len - 1`).
##
## Every stored Nim AST type expression is an independent `copyNimTree` copy.
##
## Node semantics:
##
## * `lpk_type`: stores one type expression.
## * `lpk_here`: stores no child or type expression.
## * `lpk_seq` / `lpk_option`: stores exactly one child ID.
## * `lpk_tuple`: stores ordered items; each item stores an optional name and
##   one child ID. Unnamed items have `name == ""`.
## * `lpk_object`: stores one object type expression and ordered named members;
##   each member stores a name and one child ID.
##
## Stored item/member names are normalized by `name_text`: plain
## identifier/symbol names use `repr`; acc-quoted names concatenate each
## part's `str_val` without separators. Original name AST and quoting are not
## retained. Duplicate detection is exactly
## `cmp_ignore_style(left, right) == 0`.
##
## `root_id(tree)` returns the valid root. `node(tree, id)` requires a valid
## ID and returns the corresponding node. `child_id(pattern)` is valid only
## for `lpk_seq`/`lpk_option`. `type_expression(pattern)` is valid only for
## `lpk_type`/`lpk_object`, returning a copied type AST.
##
## `tuple_item_count`/`tuple_item` are valid only for `lpk_tuple`; item indexes
## must be in range. `object_member_count`/`object_member` are valid only for
## `lpk_object`; member indexes must be in range. Invalid node IDs, pattern
## kinds, and indexes violate accessor preconditions. Implementations enforce
## these with Nim `assert`; behavior with assertions disabled is unspecified.
##
## == `lift_types` contract used by `vecherinka_comptime` ==
##
## `lift_types(tree, flow_domain, flow_codomain)` derives the outer flow
## endpoints while preserving pattern shape:
##
## * type node: input and output are the stored type expression;
## * `here`: input is `flow_domain`, output is `flow_codomain`;
## * `seq`/`Option`: same wrapper around recursively derived endpoints;
## * tuple: same ordered arity and labels, recursively derived per item;
## * object: input and output are the stored object type expression; object
##   members, labels, and nested `here` nodes are opaque and do not affect
##   endpoint types.
##
## Results are structurally equal to fresh AST copies, not identity aliases.
## `lpk_here` copies both flow endpoints. Named tuple endpoint fields use new
## `ident(item.name)` nodes; they need not preserve original name AST. Wrapper
## endpoint nodes likewise use newly constructed `seq`/`Option` bracket AST.
##
## Direct-overload equivalence is structural: `lift_types(pattern,
## flow_domain, flow_codomain)` must produce structurally equal outputs to
## `lift_types(parse_lift_pattern(pattern), flow_domain, flow_codomain)`.
## Tree-dependent operations require valid root and child IDs; parser-produced
## trees satisfy these invariants. Pattern-only accessors require only their
## stated kind/index
## preconditions and do not require parser provenance. Behavior for invalid IDs
## or malformed hand-constructed trees is unspecified beyond asserted
## preconditions. Copy isolation applies to parser input versus stored type AST,
## `type_expression` results, and `lift_types` results. `node` returns a value
## copy of `LiftPattern`; no deep-copy guarantee applies to its private
## reference fields.
##
## == Test-family checklist ==
##
## Compile-time tests below cover one representative of every accepted grammar
## form, nested wrappers/tuples/objects, named and unnamed aggregates, all
## type-argument forms, node-ID topology, accessor preconditions, endpoint
## derivation, AST-copy isolation, and every rejection listed above.

import std/macros
import lift_pattern_typed

type here = object

proc parse_pattern(spelling: string): LiftPatternTree {.compileTime.} =
  parse_lift_pattern(parseExpr(spelling))

macro parse_probe(spelling: static[string]): untyped =
  let tree = parse_lift_pattern(parseExpr(spelling))
  result = newLit(tree.node_count)

macro parse_source_probe(spelling: static[string]): untyped =
  ## Prove source spelling parses before testing lift-parser rejection.
  let root = parseExpr(spelling)
  result = newLit($root.kind)

macro parse_bad_probe(case_id: static[int]): untyped =
  var root: NimNode
  case case_id
  of 0:
    root = newTree(nnk_par)
  of 1:
    root = newTree(nnk_par, ident("int"), ident("string"))
  of 2:
    root = newNimNode(nnk_acc_quoted)
  of 3:
    root = newTree(nnk_call, newTree(nnk_open_sym_choice, ident("()")),
      ident("Widget"), ident("int"))
  of 4:
    let bad_name = newTree(nnk_acc_quoted, ident("field"), newIntLitNode(1))
    root = newTree(nnk_tuple_constr,
      newTree(nnk_expr_colon_expr, bad_name, ident("int")))
  of 5:
    root = newTree(nnk_tuple_constr,
      newTree(nnk_expr_colon_expr, ident("x")))
  of 6:
    root = newTree(nnk_obj_constr, ident("Record"),
      newTree(nnk_expr_colon_expr, ident("x")))
  of 7:
    root = newTree(nnk_bracket_expr, ident("Box"),
      newTree(nnk_call, ident("f")))
  of 8:
    root = nil
  of 9:
    root = newTree(nnk_acc_quoted, ident("bad"), newIntLitNode(1))
  of 10:
    root = newTree(nnk_dot_expr, ident("pkg"))
  of 11:
    root = newTree(nnk_bracket_expr, ident("seq"), nil)
  of 12:
    root = newTree(nnk_call, newTree(nnk_open_sym_choice, ident("[]")),
      ident("Widget"), newTree(nnk_call, ident("f")))
  of 13:
    root = newTree(nnk_bracket_expr, ident("Box"), newTree(nnk_par))
  of 14:
    root = newTree(nnk_bracket_expr, ident("Box"),
      newTree(nnk_par, ident("int"), ident("string")))
  of 15:
    root = newTree(nnk_bracket_expr, ident("Box"),
      newTree(nnk_tuple_constr,
        newTree(nnk_expr_colon_expr, ident("field"))))
  of 16:
    root = newTree(nnk_bracket_expr, ident("Box"),
      newTree(nnk_prefix, newTree(nnk_acc_quoted, ident("-")),
        newIntLitNode(3)))
  of 17:
    let bad_name = newTree(nnk_acc_quoted, ident("field"), newIntLitNode(1))
    root = newTree(nnk_obj_constr, ident("Record"),
      newTree(nnk_expr_colon_expr, bad_name, ident("int")))
  of 18:
    root = newTree(nnk_call, newTree(nnk_bracket, ident("not")),
      ident("Widget"), ident("string"))
  else:
    doAssert false
  discard parse_lift_pattern(root)
  result = newLit(0)

macro accessor_bad_probe(case_id: static[int]): untyped =
  case case_id
  of 0:
    let int_tree = parse_pattern("int")
    discard int_tree.node(LiftPatternId(-1))
  of 1:
    let int_tree = parse_pattern("int")
    discard int_tree.node(int_tree.root_id).child_id
  of 2:
    let here_tree = parse_pattern("here")
    discard here_tree.node(here_tree.root_id).type_expression
  of 3:
    let here_tree = parse_pattern("here")
    discard here_tree.node(here_tree.root_id).tuple_item_count
  of 4:
    let tuple_tree = parse_pattern("(int,)")
    discard tuple_tree.node(tuple_tree.root_id).tuple_item(1)
  of 5:
    let tuple_tree = parse_pattern("(int,)")
    discard tuple_tree.node(tuple_tree.root_id).tuple_item(-1)
  of 6:
    let object_tree = parse_pattern("Record(value: int)")
    discard object_tree.node(object_tree.root_id).object_member(1)
  of 7:
    var invalid_tree: LiftPatternTree
    discard invalid_tree.root_id
  of 8:
    let int_tree = parse_pattern("int")
    discard int_tree.node(int_tree.root_id).object_member_count
  else:
    doAssert false
  result = newLit(0)

template assert_rejected(spelling: static[string]) =
  doAssert compiles(parse_source_probe(spelling))
  doAssert not compiles(parse_probe(spelling))

template assert_rejected_ast(case_id: static[int]) =
  doAssert not compiles(parse_bad_probe(case_id))

proc bracket_operator_call(head, child: string): NimNode {.compileTime.} =
  newTree(nnk_call, newTree(nnk_open_sym_choice, ident("[]")),
    ident(head), parseExpr(child))

proc assert_tree_invariants(
    tree: LiftPatternTree;
    id: LiftPatternId;
    visited: var seq[bool]
)
    {.compileTime.} =
  let index = int(id)
  doAssert index in 0 ..< visited.len
  doAssert not visited[index]
  visited[index] = true
  let pattern = tree.node(id)
  case pattern.kind
  of lpk_type, lpk_here:
    discard
  of lpk_seq, lpk_option:
    let child = pattern.child_id
    doAssert int(child) < int(id)
    tree.assert_tree_invariants(child, visited)
  of lpk_tuple:
    for index in 0 ..< pattern.tuple_item_count:
      let child = pattern.tuple_item(index).pattern_id
      doAssert int(child) < int(id)
      tree.assert_tree_invariants(child, visited)
  of lpk_object:
    for index in 0 ..< pattern.object_member_count:
      let child = pattern.object_member(index).pattern_id
      doAssert int(child) < int(id)
      tree.assert_tree_invariants(child, visited)

proc assert_tree_is_well_formed(tree: LiftPatternTree) {.compileTime.} =
  doAssert tree.node_count > 0
  let root = tree.root_id
  doAssert int(root) == tree.node_count - 1
  var visited = newSeq[bool](tree.node_count)
  tree.assert_tree_invariants(root, visited)
  for reached in visited:
    doAssert reached

proc assert_root_kind(spelling: string; expected: LiftPatternKind)
    {.compileTime.} =
  let tree = parse_pattern(spelling)
  tree.assert_tree_is_well_formed()
  doAssert tree.node(tree.root_id).kind == expected

proc assert_type_pattern(spelling: string) {.compileTime.} =
  let tree = parse_pattern(spelling)
  tree.assert_tree_is_well_formed()
  let pattern = tree.node(tree.root_id)
  doAssert pattern.kind == lpk_type
  doAssert tree.node_count == 1
  doAssert pattern.type_expression.treeRepr == parseExpr(spelling).treeRepr

proc leaf_pattern_kind(spelling: string): LiftPatternKind {.compileTime.} =
  if spelling == "here":
    lpk_here
  elif spelling == "(int, here)":
    lpk_tuple
  else:
    lpk_type

proc assert_mutated_shape(leaf: string) {.compileTime.} =
  let expected_leaf = leaf_pattern_kind(leaf)
  for wrapper in ["seq", "Option"]:
    let tree = parse_pattern(wrapper & "[" & leaf & "]")
    let root = tree.node(tree.root_id)
    doAssert root.kind == (if wrapper == "seq": lpk_seq else: lpk_option)
    doAssert tree.node(root.child_id).kind == expected_leaf

  let tuple_tree = parse_pattern("(" & leaf & ", " & leaf & ")")
  let tuple_root = tuple_tree.node(tuple_tree.root_id)
  doAssert tuple_root.kind == lpk_tuple
  doAssert tuple_root.tuple_item_count == 2
  doAssert tuple_tree.node(tuple_root.tuple_item(0).pattern_id).kind ==
    expected_leaf
  doAssert tuple_tree.node(tuple_root.tuple_item(1).pattern_id).kind ==
    expected_leaf

  let object_tree = parse_pattern(
    "Record(left: " & leaf & ", right: " & leaf & ")")
  let object_root = object_tree.node(object_tree.root_id)
  doAssert object_root.kind == lpk_object
  doAssert object_root.object_member_count == 2
  doAssert object_root.object_member(0).name == "left"
  doAssert object_root.object_member(1).name == "right"
  doAssert object_tree.node(object_root.object_member(0).pattern_id).kind ==
    expected_leaf
  doAssert object_tree.node(object_root.object_member(1).pattern_id).kind ==
    expected_leaf

proc assert_ast_root_kind(root: NimNode; expected: LiftPatternKind)
    {.compileTime.} =
  let tree = parse_lift_pattern(root)
  tree.assert_tree_is_well_formed()
  doAssert tree.node(tree.root_id).kind == expected

static:
  doAssert not compiles(parse_probe("_"))

  # Basic names, exact reserved-name handling, and AST-copy isolation.
  assert_root_kind("Widget", lpk_type)
  assert_root_kind("Here", lpk_type)
  assert_root_kind("`here`", lpk_type)
  assert_root_kind("`_`", lpk_type)
  assert_root_kind("`seq`", lpk_type)
  assert_root_kind("`Option`[int]", lpk_type)
  assert_root_kind("`seq`[int]", lpk_type)
  assert_root_kind("pkg.sub.Type", lpk_type)
  assert_root_kind("pkg.outer.Box[pkg.inner.T]", lpk_type)
  assert_root_kind("pkg.`here`", lpk_type)
  assert_root_kind("`pkg`.`Type`", lpk_type)
  assert_root_kind("αType", lpk_type)

  let source = parseExpr("Box[array[0..255, uint8]]")
  let copied = parse_lift_pattern(source)
  let copied_type = copied.node(copied.root_id).type_expression
  doAssert copied_type.treeRepr == source.treeRepr
  copied_type[0] = ident("Changed")
  doAssert source.repr == "Box[array[0 .. 255, uint8]]"
  doAssert copied.node(copied.root_id).type_expression.treeRepr ==
    source.treeRepr

  # Every pattern node kind, both wrapper AST forms, nested shape, and tuple
  # ordering. `seq[...]` inside a type argument stays an ordinary type AST.
  assert_root_kind("here", lpk_here)
  assert_root_kind("(((here)))", lpk_here)
  assert_root_kind("seq[here]", lpk_seq)
  assert_root_kind("((seq[here]))", lpk_seq)
  assert_root_kind("Option[seq[(int, here)]]", lpk_option)
  assert_root_kind("[](seq, here)", lpk_seq)
  assert_root_kind("[](Option, (left: int, right: here))", lpk_option)
  assert_type_pattern("[](Widget, string)")
  assert_type_pattern("[](Map, string, int)")
  assert_ast_root_kind(bracket_operator_call("seq", "here"), lpk_seq)
  assert_ast_root_kind(
    bracket_operator_call("Option", "(left: int, right: here)"), lpk_option)
  let sym_type = bindSym("int")
  assert_ast_root_kind(sym_type, lpk_type)
  let sym_here = bindSym("here")
  assert_ast_root_kind(sym_here, lpk_here)
  let sym_seq = bindSym("seq")
  assert_ast_root_kind(newTree(nnk_bracket_expr, sym_seq, ident("here")), lpk_seq)
  assert_root_kind("Box[seq[int]]", lpk_type)

  let unnamed_tuple = parse_pattern("(int, seq[here], Option[char])")
  let unnamed_root = unnamed_tuple.node(unnamed_tuple.root_id)
  doAssert unnamed_root.kind == lpk_tuple
  doAssert unnamed_root.tuple_item_count == 3
  doAssert unnamed_root.tuple_item(0).name == ""
  doAssert unnamed_root.tuple_item(1).name == ""
  doAssert unnamed_root.tuple_item(2).name == ""

  let named_tuple = parse_pattern("(`type`: int, `_`: here, `seq`: Option[char])")
  let named_root = named_tuple.node(named_tuple.root_id)
  doAssert named_root.kind == lpk_tuple
  doAssert named_root.tuple_item_count == 3
  doAssert named_root.tuple_item(0).name == "type"
  doAssert named_root.tuple_item(1).name == "_"
  doAssert named_root.tuple_item(2).name == "seq"
  let reserved_labels = parse_pattern("(_ : here, here: int)")
  doAssert reserved_labels.node(reserved_labels.root_id).tuple_item_count == 2
  doAssert parse_pattern("(int,)").node_count == 2

  let object_pattern = parse_pattern(
    "Packet(header: Header, payload: seq[here], meta: (flag: here))")
  let object_root = object_pattern.node(object_pattern.root_id)
  doAssert object_root.kind == lpk_object
  doAssert object_root.object_member_count == 3
  doAssert object_root.object_member(0).name == "header"
  doAssert object_root.object_member(1).name == "payload"
  doAssert object_root.object_member(2).name == "meta"
  let parenthesized_member = parse_pattern("Record(value: (((here))))")
  doAssert parenthesized_member.here_count == 1
  doAssert parenthesized_member.node(
    parenthesized_member.node(parenthesized_member.root_id).object_member(0).
      pattern_id).kind == lpk_here

  # Exact node topology, labels, and child semantics for mixed nesting.
  let exact = parse_pattern(
    "Record(left: seq[here], right: (x: int, y: Option[here]))")
  doAssert exact.node_count == 7
  doAssert exact.root_id == LiftPatternId(6)
  doAssert exact.node(LiftPatternId(0)).kind == lpk_here
  doAssert exact.node(LiftPatternId(1)).kind == lpk_seq
  doAssert exact.node(LiftPatternId(1)).child_id == LiftPatternId(0)
  doAssert exact.node(LiftPatternId(2)).kind == lpk_type
  doAssert exact.node(LiftPatternId(3)).kind == lpk_here
  doAssert exact.node(LiftPatternId(4)).kind == lpk_option
  doAssert exact.node(LiftPatternId(4)).child_id == LiftPatternId(3)
  doAssert exact.node(LiftPatternId(5)).kind == lpk_tuple
  doAssert exact.node(LiftPatternId(5)).tuple_item_count == 2
  doAssert exact.node(LiftPatternId(5)).tuple_item(0).name == "x"
  doAssert exact.node(LiftPatternId(5)).tuple_item(0).pattern_id ==
    LiftPatternId(2)
  doAssert exact.node(LiftPatternId(5)).tuple_item(1).name == "y"
  doAssert exact.node(LiftPatternId(5)).tuple_item(1).pattern_id ==
    LiftPatternId(4)
  doAssert exact.node(LiftPatternId(6)).kind == lpk_object
  doAssert exact.node(LiftPatternId(6)).object_member_count == 2
  doAssert exact.node(LiftPatternId(6)).object_member(0).name == "left"
  doAssert exact.node(LiftPatternId(6)).object_member(0).pattern_id ==
    LiftPatternId(1)
  doAssert exact.node(LiftPatternId(6)).object_member(1).name == "right"
  doAssert exact.node(LiftPatternId(6)).object_member(1).pattern_id ==
    LiftPatternId(5)
  assert_root_kind("seq[int](value: here)", lpk_object)
  let reserved_object = parse_pattern("Record(_: here, here: int, seq: Option)")
  doAssert reserved_object.node(reserved_object.root_id).object_member_count == 3
  doAssert reserved_object.node(reserved_object.root_id).object_member(0).name == "_"
  doAssert reserved_object.node(reserved_object.root_id).object_member(1).name == "here"
  doAssert reserved_object.node(reserved_object.root_id).object_member(2).name == "seq"

  let multipart_name = newTree(nnk_acc_quoted, ident("foo"), ident("Bar"))
  let multipart_tuple = newTree(nnk_tuple_constr,
    newTree(nnk_expr_colon_expr, multipart_name, ident("here")))
  let multipart_tree = parse_lift_pattern(multipart_tuple)
  doAssert multipart_tree.node(multipart_tree.root_id).tuple_item(0).name ==
    "fooBar"

  # Nim type-expression grammar representatives accepted by the parser.
  assert_root_kind("array[0..255, uint8]", lpk_type)
  assert_root_kind("`static`[Option[int]]", lpk_type)
  assert_root_kind("range[-10..10]", lpk_type)
  assert_root_kind("typeDesc[Widget]", lpk_type)
  assert_ast_root_kind(bracket_operator_call("Widget", "string"), lpk_type)
  assert_ast_root_kind(
    newTree(nnk_call, newTree(nnk_open_sym_choice, ident("[]")),
      ident("Map"), ident("string"), ident("int")), lpk_type)
  assert_ast_root_kind(
    newTree(nnk_call, newTree(nnk_closed_sym_choice, ident("[]")),
      ident("Map"), ident("string")), lpk_type)
  assert_ast_root_kind(
    newTree(nnk_call, newTree(nnk_open_sym_choice,
      ident("()"), ident("[]")), ident("Map"), ident("string")), lpk_type)
  assert_root_kind("Box[(left: int, string, right: Option[char]) ]", lpk_type)
  assert_root_kind("Box[(left: int, left: string)]", lpk_type)
  assert_root_kind("Box[(((int)))]", lpk_type)
  assert_ast_root_kind(
    newTree(nnk_bracket_expr, ident("Range"),
      newTree(nnk_infix, ident(".."),
        newTree(nnk_prefix, ident("-"), newIntLitNode(1)),
        newTree(nnk_prefix, ident("+"), newIntLitNode(127)))), lpk_type)
  assert_ast_root_kind(
    newTree(nnk_bracket_expr, ident("Box"),
      newTree(nnk_prefix, ident("+"), newIntLitNode(1))), lpk_type)

  # Bounded mutation-like cross-product: mutate leaf shape through every wrapper and
  # aggregate shell, then mutate type-argument shell and representative args.
  for leaf in ["int", "here", "(int)", "(int, here)", "`type`"]:
    assert_mutated_shape(leaf)
  for head in ["Box", "pkg.Box", "array", "`static`", "typeDesc"]:
    for argument in ["int", "seq[int]", "0..3", "(left: int, string)", "nil"]:
      assert_type_pattern(head & "[" & argument & "]")

  for literal in [
      "0", "0xFF", "0o77", "0b1010", "1_000", "1.25", "1e3",
      "1'i8", "2'i16", "3'i32", "4'i64", "5'u", "6'u8", "7'u16",
      "8'u32", "9'u64", "1'f", "2'f32", "3'd", "4'f64", "\"text\"",
      "r\"raw\\ntext\"", "\"\"\"triple text\"\"\"", "'x'", "nil"]:
    assert_type_pattern("Box[" & literal & "]")

  # `here` endpoint substitution; wrappers and tuple labels survive shape.
  let flow_tree = parse_pattern("(int, here, seq[Option[here]])")
  let endpoints = lift_types(flow_tree, parseExpr("Input"), parseExpr("Output"))
  doAssert endpoints.input_type.treeRepr ==
    parseExpr("(int, Input, seq[Option[Input]])").treeRepr
  doAssert endpoints.output_type.treeRepr ==
    parseExpr("(int, Output, seq[Option[Output]])").treeRepr

  let object_endpoints = lift_types(
    parse_pattern("Record(left: here, right: seq[here])"),
    parseExpr("Input"), parseExpr("Output"))
  doAssert object_endpoints.input_type.treeRepr == parseExpr("Record").treeRepr
  doAssert object_endpoints.output_type.treeRepr == parseExpr("Record").treeRepr
  let named_endpoints = lift_types(parse_pattern("(left: here, right: int)"),
    parseExpr("Input"), parseExpr("Output"))
  doAssert named_endpoints.input_type.treeRepr ==
    parseExpr("(left: Input, right: int)").treeRepr
  doAssert named_endpoints.output_type.treeRepr ==
    parseExpr("(left: Output, right: int)").treeRepr

  let direct_spelling = parseExpr("(here, seq[int])")
  let direct = lift_types(direct_spelling, parseExpr("Input"), parseExpr("Output"))
  let via_tree = lift_types(parse_lift_pattern(direct_spelling),
    parseExpr("Input"), parseExpr("Output"))
  doAssert direct.input_type.treeRepr == via_tree.input_type.treeRepr
  doAssert direct.output_type.treeRepr == via_tree.output_type.treeRepr

  let topology = parse_pattern("(here, seq[int])")
  doAssert topology.node_count == 4
  doAssert topology.node(LiftPatternId(0)).kind == lpk_here
  doAssert topology.node(LiftPatternId(1)).kind == lpk_type
  doAssert topology.node(LiftPatternId(2)).kind == lpk_seq
  doAssert topology.node(LiftPatternId(3)).kind == lpk_tuple
  doAssert topology.root_id == LiftPatternId(topology.node_count - 1)

  let object_type = parse_pattern("Record(value: here)")
  let object_node = object_type.node(object_type.root_id)
  doAssert object_node.type_expression.repr == "Record"
  let object_member = object_node.object_member(0)
  doAssert object_member.object_member_pattern_id == LiftPatternId(0)
  doAssert object_member.pattern_id == LiftPatternId(0)
  doAssert object_type.node(object_member.object_member_pattern_id).kind ==
    lpk_here
  doAssert parse_pattern("Record(a: here, b: seq[here])").here_count == 2

  let endpoint_tree = parse_pattern("(here, int)")
  let endpoint_copy = lift_types(endpoint_tree,
    parseExpr("Input"), parseExpr("Output"))
  endpoint_copy.input_type[0] = ident("Changed")
  doAssert endpoint_tree.node(endpoint_tree.root_id).tuple_item(0).
    pattern_id == LiftPatternId(0)
  doAssert lift_types(endpoint_tree, parseExpr("Input"), parseExpr("Output")).
    input_type.treeRepr == parseExpr("(Input, int)").treeRepr
  let object_copy_tree = parse_pattern("Record[int](value: here)")
  let object_head = object_copy_tree.node(object_copy_tree.root_id)
  let object_head_copy = object_head.type_expression
  object_head_copy[1] = ident("Changed")
  doAssert object_head.type_expression.treeRepr ==
    parseExpr("Record[int]").treeRepr
  let object_copy = lift_types(object_copy_tree,
    parseExpr("Input"), parseExpr("Output"))
  object_copy.input_type[1] = ident("Changed")
  doAssert object_copy.output_type.treeRepr == parseExpr("Record[int]").treeRepr
  doAssert object_copy_tree.node(object_copy_tree.root_id).
    type_expression.treeRepr == parseExpr("Record[int]").treeRepr
  doAssert parse_pattern("Box[`here`]").here_count == 0
  let type_tree = parse_pattern("Box[int]")
  let type_endpoints = lift_types(type_tree, parseExpr("Input"), parseExpr("Output"))
  type_endpoints.input_type[1] = ident("Changed")
  doAssert type_endpoints.output_type.treeRepr == parseExpr("Box[int]").treeRepr
  doAssert type_tree.node(type_tree.root_id).type_expression.treeRepr ==
    parseExpr("Box[int]").treeRepr
  let domain = parseExpr("Input")
  let codomain = parseExpr("Output")
  var here_endpoints = lift_types(parse_pattern("here"), domain, codomain)
  here_endpoints.input_type = ident("Changed")
  here_endpoints.output_type = ident("Changed")
  doAssert domain.repr == "Input"
  doAssert codomain.repr == "Output"

  # Rejection boundary: valid Nim syntax outside this restricted lift grammar,
  # malformed pattern AST, wrapper precedence, and invalid type arguments.
  assert_rejected("_")
  assert_rejected("seq[_]")
  assert_rejected("Option[()]")
  assert_rejected("seq[int, string]")
  assert_rejected("Option[int, string]")
  assert_rejected("seq[]")
  assert_rejected("Option[]")
  assert_rejected("[](seq, here, int)")
  assert_rejected("[](seq)")
  assert_rejected("[]()")
  assert_rejected("()")
  assert_rejected("Record()")
  assert_rejected("Record(int)")
  assert_rejected("(int, named: here)")
  assert_rejected("(foo_bar: int, fooBar: here)")
  assert_rejected("Record(foo_bar: int, fooBar: here)")
  assert_rejected("Record(left: int, left: here)")
  assert_rejected("array[]")
  assert_rejected("array[foo()]")
  assert_rejected("array[1 + 2]")
  assert_rejected("array[{}]")
  assert_rejected("array[[]]")
  assert_rejected("ref Widget")
  assert_rejected("ptr Widget")
  assert_rejected("proc(x: int): string")
  assert_rejected("int|string")
  assert_rejected("tuple[left: string, right: seq[char]]")
  assert_rejected("Box[5'u4]")
  assert_rejected("Box[(int,)]()")
  assert_rejected("a.here")
  assert_rejected("a._")
  assert_rejected("Box[(--1)]")
  assert_rejected("1")
  assert_rejected("1..3")
  assert_rejected("(1..3)")
  assert_rejected("here(value: int)")
  assert_rejected("_ (value: int)")

  # Nim permits this object-constructor type syntax, but object-pattern heads
  # intentionally require direct `is_type_expr` shape and reject `nnk_par`.
  assert_rejected("(ref Widget)(value: here)")

  # Direct malformed AST cases unreachable through valid source text.
  assert_rejected_ast(0)
  assert_rejected_ast(1)
  assert_rejected_ast(2)
  assert_rejected_ast(3)
  assert_rejected_ast(4)
  assert_rejected_ast(5)
  assert_rejected_ast(6)
  assert_rejected_ast(7)
  assert_rejected_ast(8)
  assert_rejected_ast(9)
  assert_rejected_ast(10)
  assert_rejected_ast(11)
  assert_rejected_ast(12)
  assert_rejected_ast(13)
  assert_rejected_ast(14)
  assert_rejected_ast(15)
  assert_rejected_ast(16)
  assert_rejected_ast(17)
  assert_rejected_ast(18)

  # Accessor assertions are compile-time failures, not ordinary parse rejects.
  doAssert not compiles(accessor_bad_probe(0))
  doAssert not compiles(accessor_bad_probe(1))
  doAssert not compiles(accessor_bad_probe(2))
  doAssert not compiles(accessor_bad_probe(3))
  doAssert not compiles(accessor_bad_probe(4))
  doAssert not compiles(accessor_bad_probe(5))
  doAssert not compiles(accessor_bad_probe(6))
  doAssert not compiles(accessor_bad_probe(7))
  doAssert not compiles(accessor_bad_probe(8))
