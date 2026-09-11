{.experimental: "callOperator".}

import zvetok

type
  Leaf = object
    name: string
    backup: string
    `field-name`: string
  Record = object
    leaf: Leaf
    backup: Leaf
  Pair = tuple[first: Record, second: Record]
  Triple = tuple[first: Record, second: Record, third: Record]
  LeafPair = tuple[first: Leaf, second: Leaf]
  StringPair = tuple[first: string, second: string]

  Nested = tuple[pair: Pair, fallback: Leaf]
  MessageKind = enum
    textMessage
    codeMessage
  Message = object
    case kind: MessageKind
    of textMessage:
      text: string
    of codeMessage:
      code: int

zvetok:
  # Typed projection marker: first brackets declare endpoints; later brackets
  # are parsed selector groups.
  proc pair_first: Pair ~> Record = it[Pair, Record][0]
  proc leaf_name: Leaf ~> string = it[Leaf, string][name]
  proc pair_leaf: Pair ~> Leaf = it[Pair, Leaf][0][leaf]
  proc pair_leaf_composed: Pair ~> Leaf =
    it[Pair, Record][0] >>> it[Record, Leaf][leaf]
  proc pair_leaf_name: Pair ~> string = it[Pair, string][0][leaf][name]
  proc pair_leaf_name_composed: Pair ~> string =
    it[Pair, Record][0] >>> it[Record, Leaf][leaf] >>> it[Leaf, string][name]
  proc pair_leafs: Pair ~> LeafPair = it[Pair, LeafPair][0, 1][leaf]
  proc record_fields: Record ~> LeafPair = it[Record, LeafPair][leaf, backup]
  proc quoted_field: Leaf ~> string = it[Leaf, string][`field-name`]
  proc pair_quoted: Pair ~> StringPair =
    it[Pair, StringPair][0, 1][leaf][`field-name`]
  proc range_pair: Triple ~> Pair = it[Triple, Pair][1 .. 2]
  proc range_first: Triple ~> Record = range_pair() >>> pair_first
  proc range_quoted: Triple ~> StringPair =
    it[Triple, StringPair][1 .. 2][leaf][`field-name`]
  proc nested_name: Triple ~> StringPair =
    it[Triple, StringPair][1 .. 2][leaf][name]

  # Plain lift marker: parser validates pattern; typed body supplies endpoints.
  proc two_here: Pair ~> Pair = cheap[Pair, Pair]("two")
  proc named_tuple: Nested ~> Nested = cheap[Nested, Nested]("named")
  proc nested: Nested ~> Nested = cheap[Nested, Nested]("nested")
  proc object_fields: Leaf ~> Leaf = cheap[Leaf, Leaf]("fields")
  proc object_variant: Message ~> Message = cheap[Message, Message]("variant")

  proc lifted_two: Pair ~> Pair =
    lift[(here, here)](two_here)
  proc lifted_named: Nested ~> Nested =
    lift[(pair: (here, _), fallback: here)](named_tuple)
  proc lifted_nested: Nested ~> Nested =
    lift[seq[Option[(here, _)]]](nested)
  proc lifted_object: Leaf ~> Leaf =
    lift[Leaf(name: here, backup: _, `field-name`: here)](object_fields)
  proc lifted_variant: Message ~> Message =
    lift[Message(kind: textMessage, text: here)](object_variant)

  # Pair lift composes as typed value-level operation inside `so`.
  proc leaf_step: Leaf ~> string = cheap[Leaf, string]("leaf")
  proc lifted_pair: (string, Leaf) ~> (string, string) =
    so[(string, Leaf), (string, string)](input) do:
      input >>> lift[(_, here)](leaf_step)
