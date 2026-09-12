import std/macros
import lift_pattern_typed

macro check_types(pattern: untyped): untyped =
  let tree = parse_lift_pattern(pattern)
  let root = tree.node(tree.root_id)
  doAssert root.kind == lpk_tuple
  doAssert tree.here_count == 1
  doAssert root.tuple_item_count == 2
  let first = tree.node(root.tuple_item(0).pattern_id)
  let second = tree.node(root.tuple_item(1).pattern_id)
  doAssert first.kind == lpk_type
  doAssert first.type_expression.repr == "String"
  doAssert second.kind == lpk_here
  let types = lift_types(tree, ident("Int"), ident("Bool"))
  doAssert types.input_type.repr == "(String, Int)"
  doAssert types.output_type.repr == "(String, Bool)"
  result = new_empty_node()

macro check_type(pattern: untyped): untyped =
  let tree = parse_lift_pattern(pattern)
  let root = tree.node(tree.root_id)
  doAssert root.kind == lpk_type
  doAssert root.type_expression.repr == "Box[int]"
  result = new_empty_node()

macro check_nested(pattern: untyped): untyped =
  let tree = parse_lift_pattern(pattern)
  let root = tree.node(tree.root_id)
  doAssert root.kind == lpk_seq
  let option = tree.node(root.child_id)
  doAssert option.kind == lpk_option
  let tuple_node = tree.node(option.child_id)
  doAssert tuple_node.kind == lpk_tuple
  doAssert tuple_node.tuple_item_count == 2
  doAssert tree.here_count == 1
  let types = lift_types(pattern, ident("Int"), ident("Bool"))
  doAssert types.input_type.repr == "seq[Option[(String, Int)]]"
  doAssert types.output_type.repr == "seq[Option[(String, Bool)]]"
  result = new_empty_node()

macro check_object(pattern: untyped): untyped =
  let tree = parse_lift_pattern(pattern)
  let object_node = tree.node(tree.root_id)
  doAssert object_node.kind == lpk_object
  doAssert object_node.object_member_count == 2
  let first = tree.node(object_node.object_member(0).pattern_id)
  doAssert first.kind == lpk_type
  doAssert first.type_expression.repr == "String"
  let second = tree.node(object_node.object_member(1).pattern_id)
  doAssert second.kind == lpk_here
  doAssert tree.here_count == 1
  result = new_empty_node()

macro parse_only(pattern: untyped): untyped =
  discard parse_lift_pattern(pattern)
  result = new_empty_node()

macro check_debug(pattern: untyped): untyped =
  debug_lift_pattern(parse_lift_pattern(pattern))
  result = new_empty_node()

check_types((String, here))
check_type(Box[int])
check_nested(seq[Option[(String, here)]])
check_object(Message(value: String, text: here))
check_debug((String, seq[Option[here]]))

static:
  doAssert compiles(parse_only(String))
  doAssert compiles(parse_only((String, here)))
  doAssert not compiles(parse_only(_))
  doAssert not compiles(parse_only(seq[String, int]))
  doAssert not compiles(parse_only((value: String, int)))
  doAssert not compiles(parse_only((value: String, v_alue: here)))
  doAssert not compiles(parse_only(Record(value = String)))
