{.experimental: "callOperator".}

import konez

type
  Leaf = object
    name: string
    `field-name`: string
  Record = object
    leaf: Leaf
    backup: Leaf
  Pair = tuple[first: Record, second: Record]
  Triple = tuple[first: Record, second: Record, third: Record]
  LeafPair = tuple[first: Leaf, second: Leaf]
  StringPair = tuple[first: string, second: string]

konez:
  > pair_first Pair ~> Record:
    it[0]

  > leaf_name Leaf ~> string:
    it[name]

  > pair_leaf Pair ~> Leaf:
    it[0] >>> it[leaf]

  > pair_leaf_name Pair ~> string:
    it[0][leaf] >>> leaf_name

  > pair_leafs Pair ~> LeafPair:
    it[0, 1][leaf]

  > record_fields Record ~> LeafPair:
    it[leaf, backup]

  > quoted_field Leaf ~> string:
    it[`field-name`]

  > pair_quoted Pair ~> StringPair:
    it[0, 1][leaf] >>> it[0, 1][`field-name`]

  > range_first Triple ~> Record:
    it[1 .. 2] >>> pair_first

  > range_quoted Triple ~> StringPair:
    it[1 .. 2][leaf] >>> it[0, 1][`field-name`]

  > nested_name Triple ~> StringPair:
    it[1 .. 2][leaf][name]
