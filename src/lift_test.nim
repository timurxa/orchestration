{.experimental: "callOperator".}

import konez

type
  Leaf = object
    name: string
    backup: string
    `field-name`: string
  Pair = tuple[first: Leaf, second: Leaf]
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

konez:
  > one_here (Leaf, Leaf) ~> Leaf:
    lift[(_, here)](one_here)

  > two_here Pair ~> Pair:
    lift[(here, here)](two_here)

  > named_tuple Nested ~> Nested:
    lift[(pair: (here, _), fallback: here)](named_tuple)

  > nested (Nested) ~> Nested:
    lift[seq[Option[(here, _)]]](nested)

  > object_fields Leaf ~> Leaf:
    lift[Leaf(name: here, backup: _, `field-name`: here)](object_fields)

  > object_variant Message ~> Message:
    lift[Message(kind: textMessage, text: here)](object_variant)
