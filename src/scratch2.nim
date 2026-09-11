import std/[macros, sugar]

macro t(i: int; a: typed): untyped =
  let l = i
  result = quote do:
    b[3]

  dump result.astGenRepr

  result = newEmptyNode()

var e = [1, 2, 3]

t(1, e)
