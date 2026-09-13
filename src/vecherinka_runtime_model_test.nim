{.experimental: "callOperator".}

import vecherinka
import codex_json
import std/options

type
  First = object
  Second = object
  Third = object
  Fourth = object
  ProjectionLeaf = object
    name: string
  ProjectionInput = tuple[first, second: ProjectionLeaf]
  ProjectionTriple = tuple[first, second, third: ProjectionLeaf]

const profile = "gpt-5.6-luna".minimal

proc run_projector[A](flow: Flow[A]): A =
  flow.projector(default(A))

vecherinka:
  > model_flow First ~> Second:
    profile[First, Second]("hello")
  > model_flow_2 First ~> Second:
    model_flow

doAssert model_flow.kind == fk_top
doAssert model_flow.root == "model_flow"
doAssert model_flow.body.kind == fk_model
doAssert model_flow.body.profile.model == "gpt-5.6-luna"
doAssert model_flow.body.profile.effort == re_minimal
doAssert model_flow.body.prompt == "hello"
doAssert model_flow_2.kind == fk_top
doAssert model_flow_2.root == "model_flow_2"
doAssert model_flow_2.body.kind == fk_ref
doAssert model_flow_2.body.name == "model_flow"

vecherinka:
  > void_second void ~> Second:
    profile[void, Second]("void second")
  > void_third void ~> Third:
    profile[void, Third]("void third")
  > so_model First ~> Second:
    so(First, Second, input) do:
      discard input
      void_second
  > so_raw First ~> Third:
    so(First, Third, input) do:
      let local = input
      local >>> profile[First, Third]("raw third")
  > so_inner_composed First ~> Fourth:
    so(First, Fourth, input) do:
      discard input
      void_third >>> profile[Third, Fourth]("inner third")
  > so_fanned First ~> (Second, Third):
    so(First, (Second, Third), input) do:
      discard input
      fan(void_second, void_third)
  > so_outer First ~> Fourth:
    (so(First, Second, input) do:
      discard input
      void_second) >>> profile[Second, Third]("outer second") >>>
        profile[Third, Fourth]("outer third")

doAssert so_model.kind == fk_top
doAssert so_model.body.kind == fk_so
doAssert so_model.body.execute != nil
doAssert so_raw.kind == fk_top
doAssert so_raw.body.kind == fk_so
doAssert so_raw.body.execute != nil
doAssert so_inner_composed.body.kind == fk_so
doAssert so_fanned.body.kind == fk_so
doAssert so_fanned.body.execute != nil
doAssert so_outer.body.kind == fk_so
doAssert so_outer.body.continuation.kind == fk_model
doAssert so_outer.body.continuation.prompt == "outer second"
doAssert so_outer.body.continuation.continuation.kind == fk_model
doAssert so_outer.body.continuation.continuation.prompt == "outer third"

vecherinka:
  > first First ~> Second:
    profile[First, Second]("first")
  > first_third First ~> Third:
    profile[First, Third]("first third")
  > second Second ~> Third:
    profile[Second, Third]("second")
  > third Third ~> Fourth:
    profile[Third, Fourth]("third")
  > pair_to_fourth (Second, Third) ~> Fourth:
    profile[(Second, Third), Fourth]("pair")
  > identity First ~> First:
    profile[First, First]("identity")
  > chained First ~> Fourth:
    first >>> second >>> third
  > inline_chained First ~> Fourth:
    profile[First, Second]("inline first") >>>
      profile[Second, Third]("inline second") >>>
        profile[Third, Fourth]("inline third")
  > right_chained First ~> Fourth:
    first >>> (second >>> third)
  > fanned First ~> (Second, Third):
    fan(first, first_third)
  > fanned_then First ~> Fourth:
    fan(first, first_third) >>> pair_to_fourth
  > prefix_fanned First ~> (Second, Third):
    identity >>> fan(first, first_third)
  > branch_composed First ~> (Third, Third):
    fan(first >>> second, first_third)
  > nested_fanned First ~> ((Second, Third), Third):
    fan(fan(first, first_third), first_third)

doAssert chained.kind == fk_top
doAssert chained.body.kind == fk_ref
doAssert chained.body.name == "first"
doAssert chained.body.continuation.kind == fk_ref
doAssert chained.body.continuation.name == "second"
doAssert chained.body.continuation.continuation.kind == fk_ref
doAssert chained.body.continuation.continuation.name == "third"
doAssert chained.body.continuation.continuation.continuation.isNil
doAssert inline_chained.body.kind == fk_model
doAssert inline_chained.body.prompt == "inline first"
doAssert inline_chained.body.continuation.kind == fk_model
doAssert inline_chained.body.continuation.prompt == "inline second"
doAssert inline_chained.body.continuation.continuation.kind == fk_model
doAssert inline_chained.body.continuation.continuation.prompt == "inline third"
doAssert inline_chained.body.continuation.continuation.continuation.isNil
doAssert right_chained.body.kind == fk_ref
doAssert right_chained.body.continuation.kind == fk_ref
doAssert right_chained.body.continuation.continuation.kind == fk_ref
doAssert right_chained.body.continuation.continuation.continuation.isNil
doAssert fanned.body.kind == fk_fanout
doAssert fanned.body.branches.len == 2
doAssert fanned.body.branches[0].kind == fk_ref
doAssert fanned.body.branches[0].name == "first"
doAssert fanned.body.branches[1].kind == fk_ref
doAssert fanned.body.branches[1].name == "first_third"
doAssert fanned.body.coalesce != nil
doAssert fanned.body.continuation.isNil
doAssert fanned_then.body.kind == fk_fanout
doAssert fanned_then.body.continuation.kind == fk_ref
doAssert fanned_then.body.continuation.name == "pair_to_fourth"
doAssert prefix_fanned.body.kind == fk_ref
doAssert prefix_fanned.body.name == "identity"
doAssert prefix_fanned.body.continuation.kind == fk_fanout
doAssert prefix_fanned.body.continuation.branches.len == 2
doAssert branch_composed.body.kind == fk_fanout
doAssert branch_composed.body.branches[0].kind == fk_ref
doAssert branch_composed.body.branches[0].continuation.kind == fk_ref
doAssert branch_composed.body.branches[0].continuation.name == "second"
doAssert nested_fanned.body.kind == fk_fanout
doAssert nested_fanned.body.branches[0].kind == fk_fanout
doAssert nested_fanned.body.branches[0].coalesce != nil

vecherinka:
  > projection_identity ProjectionInput ~> ProjectionInput:
    it(ProjectionInput)
  > projection_name ProjectionInput ~> string:
    it(ProjectionInput)[0][name]

doAssert projection_identity.kind == fk_top
doAssert projection_identity.body.kind == fk_it
doAssert projection_identity.body.projector != nil
doAssert projection_name.kind == fk_top
doAssert projection_name.body.kind == fk_it
doAssert projection_name.body.projector != nil
discard run_projector(projection_identity.body)
discard run_projector(projection_name.body)

vecherinka:
  > projection_range ProjectionTriple ~> (string, string):
    it(ProjectionTriple)[1 .. 2][name]

doAssert projection_range.kind == fk_top
doAssert projection_range.body.kind == fk_it
doAssert projection_range.body.projector != nil
discard run_projector(projection_range.body)

vecherinka:
  > lift_first First ~> Second:
    profile[First, Second]("lift first")
  > lift_second Second ~> Third:
    profile[Second, Third]("lift second")
  > lifted_seq seq[First] ~> seq[Second]:
    lift(seq[here])[lift_first]
  > lifted_tuple (First, string) ~> (Second, string):
    lift((here, string))[lift_first]
  > lifted_option Option[First] ~> Option[Second]:
    lift(Option[here])[lift_first]
  > lifted_nested seq[seq[First]] ~> seq[seq[Second]]:
    lift(seq[seq[here]])[lift_first]
  > lifted_so First ~> Second:
    lift(here)[
      so(First, Second, input) do:
        discard input
        profile[void, Second]("lift so")]
  > lifted_chain seq[First] ~> seq[Third]:
    lift(seq[here])[lift_first] >>> lift(seq[here])[lift_second]

doAssert lifted_seq.kind == fk_top
doAssert lifted_seq.body.kind == fk_lift
doAssert lifted_seq.body.inner.kind == fk_ref
doAssert lifted_seq.body.destructure != nil
doAssert lifted_seq.body.construct != nil
doAssert lifted_seq.body.continuation.isNil
doAssert lifted_tuple.body.kind == fk_lift
doAssert lifted_tuple.body.destructure != nil
doAssert lifted_tuple.body.construct != nil
doAssert lifted_option.body.kind == fk_lift
doAssert lifted_option.body.destructure != nil
doAssert lifted_option.body.construct != nil
doAssert lifted_nested.body.kind == fk_lift
doAssert lifted_nested.body.destructure != nil
doAssert lifted_nested.body.construct != nil
doAssert lifted_so.body.kind == fk_lift
doAssert lifted_so.body.inner.kind == fk_so
doAssert lifted_so.body.inner.execute != nil
doAssert lifted_chain.body.kind == fk_lift
doAssert lifted_chain.body.inner.continuation.isNil
doAssert lifted_chain.body.continuation.kind == fk_lift
doAssert lifted_chain.body.continuation.inner.kind == fk_ref

vecherinka:
  > pure_value void ~> First:
    pure(First())
  > pure_local void ~> First:
    let value = First()
    pure(value)
  > pure_chain void ~> Second:
    pure(First()) >>> profile[First, Second]("after pure")

doAssert pure_value.kind == fk_top

vecherinka:
  > non_entry_flow First ~> Second:
    profile[First, Second]("non-entry")
  > entry_flow First ~> Third {.entry.}:
    profile[First, Third]("entry")

doAssert non_entry_flow.entry == false
doAssert entry_flow.entry == true
doAssert pure_value.body.kind == fk_raw
doAssert pure_value.body.continuation.isNil
doAssert pure_local.body.kind == fk_raw
doAssert pure_chain.body.kind == fk_raw
doAssert pure_chain.body.continuation.kind == fk_model
doAssert pure_chain.body.continuation.prompt == "after pure"
