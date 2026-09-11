import std/macros

type
  Codebase = object

template soData(pattern, body: untyped) {.pragma.}

macro so[B](pattern, body: untyped): untyped =
  let helper = genSym(nskProc, "soHelper")

  let p = newProc(
    helper,
    body = newStmtList(
      newTree(nnkDiscardStmt, newEmptyNode())
    ))

  p.addPragma(newTree(
    nnkCall, ident("soData"), pattern, body))

  result = newTree(
    nnkStmtList,
    p,
    newTree(nnkCall, helper))

macro step(body: typed): untyped =
  # Shape: outer StmtList, inner StmtList, ProcDef.
  echo body.repr
  # let impl = getImpl(body[0][0][0])
  # let data = impl[4][0] # soData(pattern, body)
  #
  # echo "pattern: ", data[1].treeRepr
  # echo "body: ", data[2].treeRepr

  result = newTree(nnkDiscardStmt, newEmptyNode())

step:
  so[Codebase](((req, code), audit)):
      if audit.ok: pure(code)
      else: (req, (code, audit.issues)) >>> lift[(_, here)](fix) >>> audit_fix_loop
