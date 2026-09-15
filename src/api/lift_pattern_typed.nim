import std/[macros, strutils]

type
  LiftPatternKind* = enum
    lpk_type
    lpk_here
    lpk_seq
    lpk_option
    lpk_tuple
    lpk_object

  LiftPatternId* = distinct int

  LiftPatternItem* = object
    name*: string
    pattern_id*: LiftPatternId

  LiftPattern* = object
    case kind*: LiftPatternKind
    of lpk_type:
      type_expr: NimNode
    of lpk_here:
      discard
    of lpk_seq, lpk_option:
      child_id: LiftPatternId
    of lpk_tuple:
      items: seq[LiftPatternItem]
    of lpk_object:
      object_type_expr: NimNode
      members: seq[LiftPatternItem]

  LiftPatternTree* = object
    root_id: LiftPatternId
    nodes: seq[LiftPattern]

proc `==`*(left, right: LiftPatternId): bool {.borrow.}

const invalid_id = LiftPatternId(-1)
const name_kinds = {nnk_ident, nnk_sym}

proc is_name(node: NimNode): bool =
  if node.kind in name_kinds:
    return true
  if node.kind != nnk_acc_quoted or node.len == 0:
    return false
  for part in node:
    if part.kind notin name_kinds:
      return false
  true

proc name_text(node: NimNode): string =
  if not node.is_name:
    error("lift pattern expects an identifier", node)
  if node.kind == nnk_acc_quoted:
    for part in node:
      result.add part.str_val
  else:
    result = node.repr

proc is_here(node: NimNode): bool =
  node.kind in name_kinds and node.repr == "here"

proc is_underscore(node: NimNode): bool =
  node.kind in name_kinds and node.repr == "_"

proc without_parens(node: NimNode): NimNode =
  result = node
  while result.kind == nnk_par:
    if result.len != 1:
      error("parenthesized lift pattern expects one child", result)
    result = result[0]

proc is_numeric_literal(node: NimNode): bool =
  node.kind in {
    nnk_int_lit, nnk_int8_lit, nnk_int16_lit, nnk_int32_lit, nnk_int64_lit,
    nnk_uint_lit, nnk_uint8_lit, nnk_uint16_lit, nnk_uint32_lit,
    nnk_uint64_lit, nnk_float_lit, nnk_float32_lit, nnk_float64_lit,
    nnk_float128_lit
  }

proc is_literal(node: NimNode): bool =
  node.is_numeric_literal or node.kind in {
    nnk_str_lit, nnk_rstr_lit, nnk_triple_str_lit, nnk_char_lit, nnk_nil_lit
  }

proc is_operator(node: NimNode; spelling: string): bool =
  case node.kind
  of nnk_ident, nnk_sym, nnk_acc_quoted:
    node.repr == spelling
  of nnk_open_sym_choice, nnk_closed_sym_choice:
    for candidate in node:
      if candidate.kind in name_kinds and candidate.repr == spelling:
        return true
    false
  else:
    false

proc is_bracket_operator(node: NimNode): bool =
  ## Source `[](T, P)` parses as `nnkBracket`; resolved macro ASTs may use
  ## open/closed symbol choices. Both denote bracket operator here. The
  ## spelling check keeps arbitrary bracket-shaped nodes out.
  if node.kind == nnk_bracket:
    return node.repr == "[]"
  node.kind in {nnk_open_sym_choice, nnk_closed_sym_choice} and
    node.is_operator("[]")

proc is_signed_numeric(node: NimNode): bool =
  node.len == 2 and
    (node[0].is_operator("+") or node[0].is_operator("-")) and
    node[1].is_numeric_literal

proc is_type_name(node: NimNode): bool =
  node.is_name and not node.is_here and not node.is_underscore

proc is_type_expr(node: NimNode): bool
proc is_type_argument(node: NimNode): bool

proc all_type_arguments(node: NimNode; first: int): bool =
  for index in first ..< node.len:
    if not node[index].is_type_argument:
      return false
  true

proc is_type_expr(node: NimNode): bool =
  case node.kind
  of nnk_ident, nnk_sym, nnk_acc_quoted:
    node.is_type_name
  of nnk_dot_expr:
    node.len == 2 and node[0].is_type_expr and node[1].is_type_name
  of nnk_bracket_expr:
    node.len >= 2 and node[0].is_type_expr and node.all_type_arguments(1)
  of nnk_call:
    node.len >= 3 and node[0].is_bracket_operator and
      node[1].is_type_expr and node.all_type_arguments(2)
  else:
    false

proc is_type_argument(node: NimNode): bool =
  if node.is_type_expr or node.is_literal:
    return true
  case node.kind
  of nnk_prefix:
    node.is_signed_numeric
  of nnk_infix:
    node.len == 3 and node[0].is_operator("..") and
      node[1].is_type_argument and node[2].is_type_argument
  of nnk_tuple_constr:
    if node.len == 0:
      return false
    for child in node:
      if child.kind == nnk_expr_colon_expr:
        if child.len != 2 or not child[0].is_name or
            not child[1].is_type_argument:
          return false
      elif not child.is_type_argument:
        return false
    true
  of nnk_par:
    node.len == 1 and node[0].is_type_argument
  else:
    false

proc same_name(left, right: string): bool =
  cmp_ignore_style(left, right) == 0

proc has_node(tree: LiftPatternTree; id: LiftPatternId): bool =
  int(id) in 0 ..< tree.nodes.len

proc add_node(tree: var LiftPatternTree; value: LiftPattern): LiftPatternId =
  ## Append-only allocation makes IDs contiguous. A caller receives the new
  ## final index; recursive parsers therefore always reference older IDs.
  result = LiftPatternId(tree.nodes.len)
  tree.nodes.add value
  assert tree.has_node(result)
  assert int(result) == tree.nodes.len - 1

proc new_type(tree: var LiftPatternTree; node: NimNode): LiftPatternId =
  var value: LiftPattern
  value.kind = lpk_type
  value.type_expr = copyNimTree(node)
  tree.add_node(value)

proc new_here(tree: var LiftPatternTree): LiftPatternId =
  var value: LiftPattern
  value.kind = lpk_here
  tree.add_node(value)

proc new_unary(
    tree: var LiftPatternTree;
    kind: LiftPatternKind;
    child_id: LiftPatternId
): LiftPatternId =
  assert kind in {lpk_seq, lpk_option} and tree.has_node(child_id)
  var value: LiftPattern
  value.kind = kind
  value.child_id = child_id
  tree.add_node(value)

proc new_tuple(
    tree: var LiftPatternTree;
    items: seq[LiftPatternItem]
): LiftPatternId =
  assert items.len > 0
  for item in items:
    assert tree.has_node(item.pattern_id)
  var value: LiftPattern
  value.kind = lpk_tuple
  value.items = items
  tree.add_node(value)

proc new_object(
    tree: var LiftPatternTree;
    type_expr: NimNode;
    members: seq[LiftPatternItem]
): LiftPatternId =
  assert members.len > 0
  for member in members:
    assert tree.has_node(member.pattern_id)
  var value: LiftPattern
  value.kind = lpk_object
  value.object_type_expr = copyNimTree(type_expr)
  value.members = members
  tree.add_node(value)

proc parse_pattern_node(node: NimNode; tree: var LiftPatternTree): LiftPatternId

proc is_wrapper_head(node: NimNode): bool =
  node.kind in name_kinds and node.repr in ["seq", "Option"]

proc parse_wrapper(
    head, child: NimNode;
    tree: var LiftPatternTree
): LiftPatternId =
  assert head.is_wrapper_head
  let child_id = parse_pattern_node(child, tree)
  new_unary(tree, if head.repr == "seq": lpk_seq else: lpk_option, child_id)

proc parse_tuple(node: NimNode; tree: var LiftPatternTree): LiftPatternId =
  if node.len == 0:
    error("lift tuple pattern cannot be empty", node)
  var items: seq[LiftPatternItem]
  var named = false
  for child in node:
    if child.kind == nnk_expr_colon_expr:
      if child.len != 2 or (items.len > 0 and not named):
        error("lift tuple names must be used consistently", child)
      named = true
      let name = name_text(child[0])
      for item in items:
        if item.name.same_name(name):
          error("duplicate lift tuple label: " & name, child[0])
      items.add LiftPatternItem(name: name,
        pattern_id: parse_pattern_node(child[1], tree))
    else:
      if named:
        error("lift tuple names must be used consistently", child)
      items.add LiftPatternItem(pattern_id: parse_pattern_node(child, tree))
  new_tuple(tree, items)

proc parse_object(node: NimNode; tree: var LiftPatternTree): LiftPatternId =
  if node.len < 2:
    error("lift object pattern needs at least one field", node)
  if not node[0].is_type_expr:
    error("lift object head must be a type expression", node[0])
  var members: seq[LiftPatternItem]
  for index in 1 ..< node.len:
    let member = node[index]
    if member.kind != nnk_expr_colon_expr or member.len != 2:
      error("lift object members require `field: pattern`", member)
    let name = name_text(member[0])
    for prior in members:
      if prior.name.same_name(name):
        error("duplicate lift object field: " & name, member[0])
    let value = member[1].without_parens
    members.add LiftPatternItem(name: name,
      pattern_id: parse_pattern_node(value, tree))
  new_object(tree, node[0], members)

proc parse_pattern_node(node: NimNode; tree: var LiftPatternTree): LiftPatternId =
  if node.is_nil:
    error("nil is not a lift pattern")
  let value = node.without_parens
  case value.kind
  of nnk_ident, nnk_sym, nnk_acc_quoted, nnk_dot_expr:
    if value.is_here:
      return new_here(tree)
    if value.is_underscore:
      error("lift patterns no longer accept `_`", value)
    if value.is_type_expr:
      return new_type(tree, value)
  of nnk_bracket_expr:
    if value.len > 0 and value[0].is_wrapper_head:
      if value.len != 2:
        error("lift wrapper expects exactly one pattern argument", value)
      return parse_wrapper(value[0], value[1], tree)
    if value.is_type_expr:
      return new_type(tree, value)
  of nnk_call:
    if value.len > 1 and value[0].is_bracket_operator and
        value[1].is_wrapper_head:
      if value.len != 3:
        error("lift wrapper expects exactly one pattern argument", value)
      return parse_wrapper(value[1], value[2], tree)
    if value.is_type_expr:
      return new_type(tree, value)
  of nnk_tuple_constr:
    return parse_tuple(value, tree)
  of nnk_obj_constr:
    return parse_object(value, tree)
  else:
    discard
  error("invalid lift pattern node: " & $value.kind, value)

proc parse_lift_pattern*(root: NimNode): LiftPatternTree =
  result.root_id = invalid_id
  ## Every aggregate parses children before appending its own node. Thus the
  ## returned root is the final node and all stored child IDs precede it.
  result.root_id = parse_pattern_node(root, result)
  assert result.has_node(result.root_id)
  assert int(result.root_id) == result.nodes.len - 1

proc root_id*(tree: LiftPatternTree): LiftPatternId =
  assert tree.has_node(tree.root_id)
  tree.root_id

proc node_count*(tree: LiftPatternTree): int = tree.nodes.len

proc node*(tree: LiftPatternTree; id: LiftPatternId): LiftPattern =
  assert tree.has_node(id)
  tree.nodes[int(id)]

proc child_id*(pattern: LiftPattern): LiftPatternId =
  assert pattern.kind in {lpk_seq, lpk_option}
  pattern.child_id

proc type_expression*(pattern: LiftPattern): NimNode =
  case pattern.kind
  of lpk_type:
    result = copyNimTree(pattern.type_expr)
  of lpk_object:
    result = copyNimTree(pattern.object_type_expr)
  else:
    assert false

proc tuple_item_count*(pattern: LiftPattern): int =
  assert pattern.kind == lpk_tuple
  pattern.items.len

proc tuple_item*(pattern: LiftPattern; index: int): LiftPatternItem =
  assert pattern.kind == lpk_tuple and index in 0 ..< pattern.items.len
  pattern.items[index]

proc object_member_count*(pattern: LiftPattern): int =
  assert pattern.kind == lpk_object
  pattern.members.len

proc object_member*(pattern: LiftPattern; index: int): LiftPatternItem =
  assert pattern.kind == lpk_object and index in 0 ..< pattern.members.len
  pattern.members[index]

proc object_member_pattern_id*(member: LiftPatternItem): LiftPatternId =
  member.pattern_id

proc count_here(tree: LiftPatternTree; id: LiftPatternId): int =
  let pattern = tree.node(id)
  case pattern.kind
  of lpk_here:
    result = 1
  of lpk_type:
    result = 0
  of lpk_seq, lpk_option:
    result = tree.count_here(pattern.child_id)
  of lpk_tuple:
    for item in pattern.items:
      result += tree.count_here(item.pattern_id)
  of lpk_object:
    for member in pattern.members:
      result += tree.count_here(member.pattern_id)

proc here_count*(tree: LiftPatternTree): int =
  tree.count_here(tree.root_id)

proc derive_lift_types(
    tree: LiftPatternTree;
    id: LiftPatternId;
    flow_domain, flow_codomain: NimNode
): tuple[input_type, output_type: NimNode] {.compileTime.} =
  let pattern = tree.node(id)
  case pattern.kind
  of lpk_type:
    result = (pattern.type_expression, pattern.type_expression)
  of lpk_here:
    result = (copyNimTree(flow_domain), copyNimTree(flow_codomain))
  of lpk_seq, lpk_option:
    let child = derive_lift_types(tree, pattern.child_id,
      flow_domain, flow_codomain)
    let wrapper = if pattern.kind == lpk_seq: "seq" else: "Option"
    result = (
      newTree(nnk_bracket_expr, ident(wrapper), child.input_type),
      newTree(nnk_bracket_expr, ident(wrapper), child.output_type)
    )
  of lpk_tuple:
    result.input_type = newTree(nnk_tuple_constr)
    result.output_type = newTree(nnk_tuple_constr)
    for item in pattern.items:
      let child = derive_lift_types(tree, item.pattern_id,
        flow_domain, flow_codomain)
      if item.name.len == 0:
        result.input_type.add child.input_type
        result.output_type.add child.output_type
      else:
        result.input_type.add newTree(nnk_expr_colon_expr,
          ident(item.name), child.input_type)
        result.output_type.add newTree(nnk_expr_colon_expr,
          ident(item.name), child.output_type)
  of lpk_object:
    result = (pattern.type_expression, pattern.type_expression)

proc lift_types*(
    tree: LiftPatternTree;
    flow_domain, flow_codomain: NimNode
): tuple[input_type, output_type: NimNode] {.compileTime.} =
  derive_lift_types(tree, tree.root_id, flow_domain, flow_codomain)

proc lift_types*(
    pattern: NimNode;
    flow_domain, flow_codomain: NimNode
): tuple[input_type, output_type: NimNode] {.compileTime.} =
  lift_types(parse_lift_pattern(pattern), flow_domain, flow_codomain)

proc debug_lift_pattern_node(
    tree: LiftPatternTree;
    id: LiftPatternId;
    depth: int
) {.compileTime.} =
  let indent = "  ".repeat(depth)
  let pattern = tree.node(id)
  case pattern.kind
  of lpk_type:
    echo indent, "type ", pattern.type_expression.repr
  of lpk_here:
    echo indent, "here"
  of lpk_seq, lpk_option:
    echo indent, if pattern.kind == lpk_seq: "seq" else: "Option"
    debug_lift_pattern_node(tree, pattern.child_id, depth + 1)
  of lpk_tuple:
    echo indent, "tuple"
    for index in 0 ..< pattern.tuple_item_count:
      let item = pattern.tuple_item(index)
      let label = if item.name.len == 0: "[" & $index & "]" else: item.name
      echo indent, "  ", label
      debug_lift_pattern_node(tree, item.pattern_id, depth + 2)
  of lpk_object:
    echo indent, "object ", pattern.type_expression.repr
    for index in 0 ..< pattern.object_member_count:
      let member = pattern.object_member(index)
      echo indent, "  ", member.name, ":"
      debug_lift_pattern_node(tree, member.object_member_pattern_id,
        depth + 2)

proc debug_lift_pattern*(tree: LiftPatternTree) {.compileTime.} =
  echo "lift_pattern nodes=", tree.node_count,
    " here_count=", tree.here_count
  debug_lift_pattern_node(tree, tree.root_id, 1)

when is_main_module:
  macro check(pattern: untyped): untyped =
    let parsed = parse_lift_pattern(pattern)
    echo pattern.repr, " => ", $parsed.node(parsed.root_id).kind,
      ", here_count=", parsed.here_count
    result = new_empty_node()

  check(String)
  check((String, here))
  check(seq[Option[(String, here)]])
  check(Record(left: String, right: here))
  check(Message(kind: MessageKind, text: here))
