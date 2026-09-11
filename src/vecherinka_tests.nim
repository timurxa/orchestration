{.experimental: "callOperator".}

import std/[macros, options]
import vecherinka
import it_projection

type
  First = object
  Second = object
  Third = object

let cheap = Profile()

vecherinka:
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
      let e = fan(first_second, first_third_1)
      echo "hi"
      discard input
      Second()
  
  > lens_identity (First, First) ~> First:
    it((First, First))[0]

# type
#   ProjectionLeaf = object
#     name: string
#     `field-name`: string
#   ProjectionRecord = object
#     leaf, backup: ProjectionLeaf
#   ProjectionPair = tuple[first, second: ProjectionRecord]
#   ProjectionNames = tuple[first, second: string]
#
# let projectionIdentity = it(ProjectionPair)
# doAssert projectionIdentity is Flow[ProjectionPair, ProjectionPair]
# doAssert projectionIdentity.itAction.path.groups.len == 0
#
# const projectionName = it(ProjectionPair)[0][leaf][name]
# doAssert projectionName is Flow[ProjectionPair, string]
# doAssert projectionName.itAction.path.groups.len == 3
# for group in projectionName.itAction.path.groups:
#   doAssert group.selectors.len == 1
# doAssert projectionName.itAction.path.groups[0].selectors[0].kind == itsIndex
# doAssert projectionName.itAction.path.groups[0].selectors[0].index == 0
# doAssert projectionName.itAction.path.groups[1].selectors[0].kind == itsField
# doAssert projectionName.itAction.path.groups[1].selectors[0].field == "leaf"
# doAssert projectionName.itAction.path.groups[2].selectors[0].kind == itsField
# doAssert projectionName.itAction.path.groups[2].selectors[0].field == "name"
#
# let projectionFields = it(ProjectionPair)[0, 1][leaf, backup][name]
# doAssert projectionFields is Flow[ProjectionPair,
#   ((string, string), (string, string))]
#
# let projectionRange = it(ProjectionPair)[0 .. 1][leaf][`field-name`]
# doAssert projectionRange is Flow[ProjectionPair, (string, string)]
# doAssert projectionRange.itAction.path.groups[0].selectors[0].kind == itsRange
# doAssert projectionRange.itAction.path.groups[0].selectors[0].first == 0
# doAssert projectionRange.itAction.path.groups[0].selectors[0].last == 1
# doAssert projectionRange.itAction.path.groups[2].selectors[0].kind == itsField
# doAssert projectionRange.itAction.path.groups[2].selectors[0].field == "field-name"
#
# let projectionSingleton = it(ProjectionPair)[0 .. 0][leaf][name]
# doAssert projectionSingleton is Flow[ProjectionPair, (string,)]
#
# let projectionDuplicates = it(ProjectionPair)[1, 0, 1][leaf][name]
# doAssert projectionDuplicates is Flow[ProjectionPair, (string, string, string)]
#
# let projectionNamed: Flow[ProjectionPair, ProjectionNames] =
#   it(ProjectionPair)[0, 1][leaf][name]
# let projectionLength = so(string, int, value): value.len
# let projectionComposed = projectionName >>> projectionLength
# doAssert projectionComposed is Flow[ProjectionPair, int]
# doAssert projectionComposed.node.kind == fnode_compose
#
# let projectionFan = fan(projectionName, projectionNamed)
# doAssert projectionFan is Flow[ProjectionPair, (string, ProjectionNames)]
# doAssert projectionFan.node.kind == fnode_fanout
# doAssert projectionFan.node.children.len == 2
# doAssert projectionFan.node.children[0].kind == fnode_it
# doAssert projectionFan.node.children[1].kind == fnode_it
#
# vecherinka:
#   > projection_in_flow ProjectionPair ~> string:
#     it(ProjectionPair)[0][leaf][name]
#
# static:
#   doAssert not compiles(it(ProjectionPair)[])
#   doAssert not compiles(it(ProjectionPair)[-1])
#   doAssert not compiles(it(ProjectionPair)[2])
#   doAssert not compiles(it(ProjectionPair)[missing])
#   doAssert not compiles(it(ProjectionPair)[0, leaf])
#   doAssert not compiles(it(ProjectionPair)[0 .. 1, 0])
#   doAssert not compiles(it(ProjectionPair)[1 .. 0])
#   doAssert not compiles(it(ProjectionPair)[-1 .. 0])
#   doAssert not compiles(it(ProjectionPair)[0 .. 2])
#   doAssert not compiles(it(ProjectionPair)[0 .. 9223372036854775807])
#   doAssert not compiles(it(ProjectionRecord)[0 .. 0])
#   doAssert not compiles(projectionIdentity[0])
#
# let stringify = so(int, string, input): $input
# proc genericIdentity[T](): Flow[T, T] = it(T)
# let genericIdentityInt = genericIdentity[int]()
# doAssert genericIdentityInt is Flow[int, int]
# proc genericSequenceLift[A, B](step: Flow[A, B]): Flow[seq[A], seq[B]] =
#   lift[seq[B], seq[here]](step)
# type FlowAlias[A, B] = Flow[A, B]
# let aliasStringify: FlowAlias[int, string] = stringify
# let aliasFan = fan(aliasStringify, stringify)
# doAssert aliasFan is Flow[int, (string, string)]
# let genericSequenceLiftValue = genericSequenceLift(stringify)
# doAssert genericSequenceLiftValue is Flow[seq[int], seq[string]]
# type
#   Box[T] = object
#     value: T
#   Wrapper[T] = seq[Option[T]]
#   LiftRecord = object
#     name: string
#     count: int
#   LiftMessageKind = enum lmText, lmCode
#   LiftMessage = object
#     case kind: LiftMessageKind
#     of lmText: text: string
#     of lmCode: code: int
#   LiftNestedMessage = object
#     case outer: bool
#     of true:
#       case inner: bool
#       of true: text: string
#       of false: code: int
#     of false: fallback: string
#   LiftRangeMessage = object
#     case tag: range[0 .. 1]
#     of 0: text: string
#     of 1: code: int
# let decorate = so(string, string, input): "[" & input & "]"
# let boxLift = lift[Box[string], Box[string](value: here)](decorate)
# doAssert boxLift is Flow[Box[string], Box[string]]
# let wrappedAliasLift = lift[Wrapper[string], seq[Option[here]]](stringify)
# doAssert wrappedAliasLift is Flow[seq[Option[int]], Wrapper[string]]
# let objectLift = lift[LiftRecord, LiftRecord(name: here, count: _)](decorate)
# doAssert objectLift is Flow[LiftRecord, LiftRecord]
# doAssert objectLift.liftAction.pattern == "LiftRecord(name: here, count: _)"
# doAssert objectLift.liftAction.step.kind == fnode_so
# let variantLift = lift[LiftMessage, LiftMessage(kind: lmText, text: here)](decorate)
# doAssert variantLift is Flow[LiftMessage, LiftMessage]
# doAssert variantLift.liftAction.pattern ==
#   "LiftMessage(kind: lmText, text: here)"
# let nestedVariantLift = lift[LiftNestedMessage,
#   LiftNestedMessage(inner: true, outer: true, text: here)](decorate)
# doAssert nestedVariantLift is Flow[LiftNestedMessage, LiftNestedMessage]
# let keepObjectLift = lift[LiftRecord, LiftRecord(count: _)](decorate)
# doAssert keepObjectLift is Flow[LiftRecord, LiftRecord]
# let rangeVariantLift = lift[LiftRangeMessage, LiftRangeMessage(tag: 0, text: here)](decorate)
# doAssert rangeVariantLift is Flow[LiftRangeMessage, LiftRangeMessage]
# static:
#   doAssert not compiles(lift[LiftRecord, LiftRecord(name: here)](stringify))
#   doAssert not compiles(lift[LiftRecord, LiftRecord(missing: here)](decorate))
#   doAssert not compiles(lift[LiftRecord, LiftRecord(count: lmCode)](decorate))
#   doAssert not compiles(lift[LiftMessage, LiftMessage(text: here)](decorate))
#   doAssert not compiles(lift[LiftMessage, LiftMessage(kind: lmCode, text: here)](decorate))
#   doAssert not compiles(lift[LiftMessage, LiftMessage(kind: _, text: here)](decorate))
#   doAssert not compiles(lift[LiftNestedMessage, LiftNestedMessage(inner: true)](decorate))
#
# let pairLift = lift[(bool, string), (_, here)](stringify)
# doAssert pairLift is Flow[(bool, int), (bool, string)]
# doAssert pairLift.liftAction.pattern == "(_, here)"
# doAssert pairLift.liftAction.step.kind == fnode_so
# let aliasLift = lift[seq[string], seq[here]](aliasStringify)
# doAssert aliasLift is Flow[seq[int], seq[string]]
# let referenceLift = lift[seq[Second], seq[here]](first_second)
# doAssert referenceLift is Flow[seq[First], seq[Second]]
# doAssert referenceLift.liftAction.pattern == "seq[here]"
# doAssert referenceLift.liftAction.step.kind == fnode_reference
#
# let nestedLift = lift[((bool, string), char), ((_, here), _)](stringify)
# doAssert nestedLift is Flow[((bool, int), char), ((bool, string), char)]
#
# let sequenceLift = lift[seq[Option[string]], seq[Option[here]]](stringify)
# doAssert sequenceLift is Flow[seq[Option[int]], seq[Option[string]]]
#
# let bothLift = lift[(string, string), (here, here)](stringify)
# doAssert bothLift is Flow[(int, int), (string, string)]
#
# let innerActionLift = lift[seq[string], seq[here]](stringify)
# let outerActionLift = lift[Option[seq[string]], Option[here]](innerActionLift)
# doAssert outerActionLift is Flow[Option[seq[int]], Option[seq[string]]]
# doAssert outerActionLift.liftAction.step.kind == fnode_lift
# doAssert outerActionLift.liftAction.step.children.len == 1
# doAssert outerActionLift.liftAction.step.children[0].kind == fnode_so
#
# static:
#   doAssert not compiles(lift[(int, string), (here, here)](stringify))
#   doAssert not compiles(lift[string, seq[here]](stringify))
#   doAssert not compiles(lift[(string, string), (here,)](stringify))
#   doAssert not compiles(12 >>> stringify)
#
# type
#   AddedNamedOutput = tuple[keep: bool, chosen: string, tail: char]
#   AddedNamedInput = tuple[keep: bool, chosen: int, tail: char]
#   AddedOptionAlias = Option[string]
#   AddedSequenceAlias = seq[AddedOptionAlias]
#   AddedSequenceAliasChain = AddedSequenceAlias
#
# let addedNamedLift = lift[AddedNamedOutput,
#   (keep: _, chosen: here, tail: _)](stringify)
# doAssert addedNamedLift is Flow[AddedNamedInput, AddedNamedOutput]
# doAssert addedNamedLift.liftAction.pattern ==
#   "(keep: _, chosen: here, tail: _)"
#
# let addedAliasLift = lift[AddedSequenceAliasChain,
#   seq[Option[here]]](stringify)
# doAssert addedAliasLift is Flow[seq[Option[int]], AddedSequenceAliasChain]
# doAssert addedAliasLift.liftAction.pattern == "seq[Option[here]]"
#
# let addedOptionLift = lift[Option[string], Option[here]](stringify)
# doAssert addedOptionLift is Flow[Option[int], Option[string]]
#
# let addedComposition = it(AddedNamedInput) >>> addedNamedLift
# doAssert addedComposition is Flow[AddedNamedInput, AddedNamedOutput]
# doAssert addedComposition.node.kind == fnode_compose
# doAssert addedComposition.node.children[0].kind == fnode_it
# doAssert addedComposition.node.children[1].kind == fnode_lift
# doAssert addedNamedLift.liftAction.step.kind == fnode_so
#
# static:
#   doAssert not compiles(lift[string, unknownPattern](stringify))
#   doAssert not compiles(lift[string, 12](stringify))
#   doAssert not compiles(lift[Option[string], seq[here]](stringify))
#   doAssert not compiles(lift[seq[string], Option[here]](stringify))
#   doAssert not compiles(lift[Option[int], Option[here]](stringify))
#   doAssert not compiles(lift[AddedNamedOutput,
#     (chosen: _, keep: here, tail: _)](stringify))
#   doAssert not compiles(lift[AddedNamedOutput,
#     (keep: _, chosen: here, chosen: _)](stringify))
#   doAssert not compiles(lift[string, here](12))
#   doAssert not compiles((true, 12) >>> pairLift)
#   doAssert not compiles(@[1] >>> addedOptionLift)
#   doAssert not compiles(12 >>> it(int))
