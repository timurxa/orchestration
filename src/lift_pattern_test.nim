import std/macros
import lift_pattern

macro checkLeaf(pattern: untyped): untyped =
  let tree = parseLiftPattern(pattern)
  doAssert tree.nodeCount == 1
  doAssert tree.rootId == LiftPatternId(0)
  doAssert tree.patternKind == lpkHere
  doAssert tree.hereCount == 1
  result = newEmptyNode()

macro checkWrapper(pattern: untyped): untyped =
  let tree = parseLiftPattern(pattern)
  doAssert tree.nodeCount == 5
  doAssert tree.patternKind == lpkSeq
  doAssert tree.hereCount == 1

  let sequenceId = tree.rootId
  doAssert sequenceId == LiftPatternId(4)
  let optionId = tree.node(sequenceId).childId
  doAssert optionId == LiftPatternId(3)
  let tupleId = tree.node(optionId).childId
  doAssert tupleId == LiftPatternId(2)

  let tupleNode = tree.node(tupleId)
  doAssert tupleNode.tupleItemCount == 2
  doAssert tupleNode.tupleItem(0).patternId == LiftPatternId(0)
  doAssert tupleNode.tupleItem(1).patternId == LiftPatternId(1)
  doAssert tree.node(tupleNode.tupleItem(0).patternId).patternKind == lpkHere
  doAssert tree.node(tupleNode.tupleItem(1).patternId).patternKind == lpkKeep
  result = newEmptyNode()

macro checkObject(pattern: untyped): untyped =
  let tree = parseLiftPattern(pattern)
  doAssert tree.nodeCount == 4
  doAssert tree.patternKind == lpkObject
  doAssert tree.hereCount == 2

  let objectNode = tree.rootPattern
  doAssert objectNode.objectMemberCount == 2
  let left = objectNode.objectMember(0)
  let right = objectNode.objectMember(1)
  doAssert left.kind == lomPattern
  doAssert right.kind == lomPattern
  doAssert left.patternId == LiftPatternId(0)
  doAssert right.patternId == LiftPatternId(2)
  doAssert tree.objectMemberPattern(left).patternKind == lpkHere
  doAssert tree.objectMemberPattern(right).patternKind == lpkOption
  result = newEmptyNode()

macro checkObjectMembers(pattern: untyped): untyped =
  let tree = parseLiftPattern(pattern)
  doAssert tree.nodeCount == 1
  doAssert tree.patternKind == lpkObject
  doAssert tree.hereCount == 0

  let objectNode = tree.rootPattern
  let tagMember = objectNode.objectMember(0)
  let wildcardMember = objectNode.objectMember(1)
  doAssert tagMember.objectMemberKind == lomTag
  doAssert tagMember.objectMemberName == "tag"
  doAssert tagMember.objectMemberTag.text == "text"
  doAssert tagMember.objectMemberTag.tagExpression.repr == "text"
  doAssert wildcardMember.objectMemberKind == lomWildcard
  result = newEmptyNode()

checkLeaf(here)
checkWrapper(seq[Option[(here, _)]])
checkObject(Node(left: here, right: Option[here]))
checkObjectMembers(Record(tag: text, keep: _))
