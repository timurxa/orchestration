{.experimental: "callOperator".}

import std/[macros, options]
import vecherinka_ir
import it_projection
import lift_pattern_typed

type
  First = object
  Second = object
  Third = object
    first: First

let cheap = ProfileSpec()

expandMacros: vecherinka:
  > first_second First ~> Second:
    cheap[First, Second]("")

  > first_third First ~> Third:
    cheap[First, Third]("")

  > second_third Second ~> Third:
    cheap[Second, Third]("")
  
  > first_third_1 First ~> Third:
    first_second >>> cheap[Second, Third]("")

  > first_third_2 First ~> Third:
    first_second >>> second_third

  > first_second_third_fanout_2 First ~> (Second, Third):
    fan first_second, first_third

  > so_test First ~> Second:
    so(First, Second, input) do:
      let e = (First()) >>> fan(first_second, first_third_1)
      echo "hi"
      discard input
      pure(Second())
  
  > lens_multiple (First, Third) ~> First:
    it((First, Third))[1][first]

  > lift_identity (First, Second) ~> (First, Second):
    lift((here, Second))[it(First)]

  > entry_flow First ~> Second {.entry.}:
    cheap[First, Second]("entry")

when defined(vecherinka_ir_tests):
  type
    Box[T] = object
      value: T
    LiftRecord = object
      name: string
      count: int
    LiftEnvelope = object
      payload: LiftRecord
    MessageKind = enum
      textMessage
      codeMessage
    Message = object
      case kind: MessageKind
      of textMessage:
        text: string
      of codeMessage:
        code: int
  
    ProjectionLeaf = object
      name: string
      `field-name`: string
    ProjectionRecord = object
      leaf: ProjectionLeaf
      backup: ProjectionLeaf
    ProjectionPair = tuple[first, second: ProjectionRecord]
    ProjectionTriple = tuple[first, second, third: ProjectionRecord]
    ProjectionLeafPair = tuple[first, second: ProjectionLeaf]
    ProjectionStringPair = tuple[first, second: string]
  
  macro parse_it_only(path: untyped): untyped =
    discard parseItPath(path)
    result = new_empty_node()
  
  macro parse_lift_only(pattern: untyped): untyped =
    discard parse_lift_pattern(pattern)
    result = new_empty_node()
  
  macro assert_lift_types(
      pattern, flow_domain, flow_codomain, expected_input, expected_output: untyped
  ): untyped =
    let tree = parse_lift_pattern(pattern)
    let types = lift_types(tree, flow_domain, flow_codomain)
    doAssert types.input_type.repr == expected_input.str_val
    doAssert types.output_type.repr == expected_output.str_val
    result = new_empty_node()
  
  # Positive section: vecherinka expansion, flow typing, projections, lifts.
  
  doAssert first_second is FlowSpec[First, Second]
  doAssert first_second.ir.id == 0
  doAssert first_third.ir.id == 1
  doAssert second_third.ir.id == 2
  doAssert first_third_1 is FlowSpec[First, Third]
  doAssert first_third_2 is FlowSpec[First, Third]
  doAssert first_second_third_fanout_2 is FlowSpec[First, (Second, Third)]
  doAssert so_test is FlowSpec[First, Second]
  doAssert lens_multiple is FlowSpec[(First, Third), First]
  doAssert lift_identity is FlowSpec[(First, Second), (First, Second)]
  doAssert entry_flow.ir.id == 9
  
  let composed = first_second >>> second_third
  doAssert composed is FlowSpec[First, Third]
  
  let fanned = fan(first_second, first_third)
  doAssert fanned is FlowSpec[First, (Second, Third)]
  let fanned_three = fan(first_second, first_third, first_third_2)
  doAssert fanned_three is FlowSpec[First, (Second, Third, Third)]
  
  let direct_so = so(int, string, value): $value
  doAssert direct_so is FlowSpec[int, string]
  doAssert direct_so.ir.fn != nil
  
  let projection_identity = it(ProjectionPair)
  doAssert projection_identity is FlowSpec[ProjectionPair, ProjectionPair]
  doAssert projection_identity.ir.path.groups.len == 0
  
  let projection_name = it(ProjectionPair)[0][leaf][name]
  doAssert projection_name is FlowSpec[ProjectionPair, string]
  doAssert projection_name.ir.path.groups.len == 3
  doAssert projection_name.ir.path.groups[0].selectors[0].kind == itsIndex
  doAssert projection_name.ir.path.groups[0].selectors[0].index == 0
  doAssert projection_name.ir.path.groups[1].selectors[0].kind == itsField
  doAssert projection_name.ir.path.groups[1].selectors[0].field == "leaf"
  doAssert projection_name.ir.path.groups[2].selectors[0].field == "name"
  
  let projection_fields = it(ProjectionPair)[0, 1][leaf, backup][name]
  doAssert projection_fields is FlowSpec[ProjectionPair,
    ((string, string), (string, string))]
  doAssert projection_fields.ir.path.groups[0].selectors.len == 2
  doAssert projection_fields.ir.path.groups[0].selectors[1].index == 1
  doAssert projection_fields.ir.path.groups[1].selectors[1].field == "backup"
  
  let projection_leafs = it(ProjectionPair)[0, 1][leaf]
  doAssert projection_leafs is FlowSpec[ProjectionPair, ProjectionLeafPair]
  
  let projection_range = it(ProjectionTriple)[1 .. 2][leaf][`field-name`]
  doAssert projection_range is FlowSpec[ProjectionTriple, (string, string)]
  doAssert projection_range.ir.path.groups[0].selectors[0].kind == itsRange
  doAssert projection_range.ir.path.groups[0].selectors[0].first == 1
  doAssert projection_range.ir.path.groups[0].selectors[0].last == 2
  doAssert projection_range.ir.path.groups[2].selectors[0].field == "field-name"
  
  let projection_named: FlowSpec[ProjectionPair, ProjectionStringPair] =
    it(ProjectionPair)[0, 1][leaf][name]
  doAssert projection_named.ir.path.groups[0].selectors.len == 2
  
  let projection_duplicates = it(ProjectionPair)[1, 0, 1][leaf][name]
  doAssert projection_duplicates is FlowSpec[ProjectionPair,
    (string, string, string)]
  
  let projection_quoted = it(ProjectionLeaf)[`field-name`]
  doAssert projection_quoted is FlowSpec[ProjectionLeaf, string]
  
  let stringify = so(int, string, input): $input
  let wrapper_lift = lift(seq[Option[here]])[stringify]
  doAssert wrapper_lift is FlowSpec[seq[Option[int]], seq[Option[string]]]
  doAssert wrapper_lift.ir.pattern == "seq[Option[here]]"
  doAssert wrapper_lift.ir.inner.fn != nil
  
  let object_step = so(LiftRecord, LiftRecord, input): input
  let object_lift = lift(LiftRecord(name: here, count: int))[object_step]
  doAssert object_lift is FlowSpec[LiftRecord, LiftRecord]
  doAssert object_lift.ir.inner.fn != nil
  
  let envelope_step = so(LiftEnvelope, LiftEnvelope, input): input
  let nested_object_lift = lift(
    LiftEnvelope(payload: LiftRecord(name: here, count: int)))[envelope_step]
  doAssert nested_object_lift is FlowSpec[LiftEnvelope, LiftEnvelope]
  
  let variant_step = so(Message, Message, input): input
  let variant_lift = lift(Message(kind: textMessage, text: here))[variant_step]
  doAssert variant_lift is FlowSpec[Message, Message]
  
  let reference_lift = lift(seq[here])[first_second]
  doAssert reference_lift is FlowSpec[seq[First], seq[Second]]
  doAssert reference_lift.ir.inner.id == 0
  
  let second_to_record = so(Second, LiftRecord, input): LiftRecord()
  let lift_composed = first_second >>> lift(here)[second_to_record]
  doAssert lift_composed is FlowSpec[First, LiftRecord]
  
  assert_lift_types(string, int, bool, "string", "string")
  assert_lift_types(here, int, bool, "int", "bool")
  assert_lift_types((string, here), int, bool, "(string, int)", "(string, bool)")
  assert_lift_types((left: string, right: here), int, bool,
    "(left: string, right: int)", "(left: string, right: bool)")
  assert_lift_types(seq[Option[(string, here)]], int, bool,
    "seq[Option[(string, int)]]", "seq[Option[(string, bool)]]")
  assert_lift_types(Box[int], int, bool, "Box[int]", "Box[int]")
  assert_lift_types(LiftRecord(name: here, count: int), int, bool,
    "LiftRecord", "LiftRecord")
  
  macro assert_lift_shape(pattern: untyped; expected_kind: static[string];
      expected_here_count: static[int]): untyped =
    let tree = parse_lift_pattern(pattern)
    doAssert $tree.node(tree.root_id).kind == expected_kind
    doAssert tree.here_count == expected_here_count
    result = new_empty_node()
  
  assert_lift_shape(seq[Option[(string, here)]], "lpk_seq", 1)
  assert_lift_shape(LiftRecord(name: here, count: int), "lpk_object", 1)
  assert_lift_shape(LiftRecord(name: "literal", count: -1), "lpk_object", 0)
  assert_lift_shape(Message(kind: textMessage, text: here), "lpk_object", 1)
  assert_lift_shape(Message(kind: MessageKind.textMessage, text: "literal"),
    "lpk_object", 0)
  assert_lift_shape(LiftEnvelope(
    payload: LiftRecord(name: here, count: int)), "lpk_object", 1)
  
  # Negative section: parser rejection and typed projection rejection.
  
  static:
    doAssert compiles(parse_it_only([[0]]))
    doAssert compiles(parse_it_only([[field_name]]))
    doAssert compiles(parse_it_only([[`field-name`]]))
    doAssert compiles(parse_it_only([[0, 1], [leaf]]))
    doAssert compiles(parse_it_only([[1 .. 2]]))
    doAssert compiles(parse_it_only([[1'i64]]))
    doAssert not compiles(parse_it_only([]))
    doAssert not compiles(parse_it_only([[]]))
    doAssert not compiles(parse_it_only([[0, leaf]]))
    doAssert not compiles(parse_it_only([[0 .. 1, 2]]))
    doAssert not compiles(parse_it_only([[1 .. 0]]))
    doAssert not compiles(parse_it_only([[1'u64]]))
    doAssert not compiles(parse_it_only([[0 .. -1]]))
    doAssert not compiles(parse_it_only([[0.5]]))
    doAssert not compiles(parse_it_only([[0 .. 1.5]]))
  
    doAssert not compiles(it(ProjectionPair)[])
    doAssert not compiles(it(ProjectionPair)[-1])
    doAssert not compiles(it(ProjectionPair)[2])
    doAssert not compiles(it(ProjectionPair)[missing])
    doAssert not compiles(it(ProjectionPair)[0, leaf])
    doAssert not compiles(it(ProjectionPair)[0 .. 1, 0])
    doAssert not compiles(it(ProjectionPair)[1 .. 0])
    doAssert not compiles(it(ProjectionPair)[0 .. 2])
    doAssert not compiles(it(ProjectionPair)[0 .. 9223372036854775807])
    doAssert not compiles(it(ProjectionRecord)[0 .. 0])
  
    doAssert compiles(parse_lift_only(string))
    doAssert compiles(parse_lift_only(here))
    doAssert compiles(parse_lift_only((string, here)))
    doAssert compiles(parse_lift_only((left: string, right: here)))
    doAssert compiles(parse_lift_only(seq[Option[(string, here)]]))
    doAssert compiles(parse_lift_only(Box[int]))
    doAssert compiles(parse_lift_only(LiftRecord(name: here, count: int)))
    doAssert compiles(parse_lift_only(Message(kind: textMessage, text: here)))
    doAssert not compiles(parse_lift_only(_))
    doAssert not compiles(parse_lift_only(()))
    doAssert not compiles(parse_lift_only(seq[string, int]))
    doAssert not compiles(parse_lift_only(Option[string, int]))
    doAssert not compiles(parse_lift_only((left: here, string)))
    doAssert not compiles(parse_lift_only((left: here, left: string)))
    doAssert not compiles(parse_lift_only(LiftRecord()))
    doAssert not compiles(parse_lift_only(LiftRecord(name = here)))
    doAssert not compiles(parse_lift_only(LiftRecord(name: _)))
    doAssert not compiles(parse_lift_only(LiftRecord(name: string(1))))
    doAssert not compiles(parse_lift_only(seq[here, string]))
    doAssert not compiles(parse_lift_only(seq[]))
    doAssert not compiles(parse_lift_only(string + here))
  
    doAssert not compiles(lift(_)[stringify])
    doAssert not compiles(lift(seq[string, int])[stringify])
    doAssert not compiles(lift((left: here, left: string))[stringify])
    doAssert not compiles(lift(string)[12])
    doAssert not compiles(fan())
    doAssert not compiles(fan(first_second, second_third))
    doAssert not compiles(first_second >>> first_third)
    doAssert not compiles(12 >>> first_second)
