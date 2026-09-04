import std/[macros, strutils]

type
  Location* = distinct string

proc publicIdent(name: string): NimNode =
  newTree(nnkPostfix, ident("*"), ident(name))

proc requirePublicFields(node: NimNode) =
  if node.kind == nnkIdentDefs:
    for i in 0 ..< node.len - 2:
      if node[i].kind != nnkPostfix or node[i].len != 2 or node[i][0].strVal != "*":
        error("all type fields must be public", node[i])
  else:
    for child in node:
      requirePublicFields(child)

macro orchestrate*(body: untyped): untyped =
  var typeSection: NimNode
  var artifactTypes: seq[NimNode] = @[]
  var rest = newStmtList()

  for statement in body:
    if statement.kind == nnkTypeSection:
      if not typeSection.isNil:
        error("orchestrate accepts one type section", statement)
      typeSection = statement
    elif statement.kind == nnkCall and statement.len == 2 and
        statement[0].kind == nnkIdent and statement[0].strVal == "artifact_types":
      if artifactTypes.len != 0:
        error("orchestrate accepts one artifact_types section", statement)
      for artifactType in statement[1]:
        if artifactType.kind != nnkIdent:
          error("artifact_types entries must be type identifiers", artifactType)
        artifactTypes.add(artifactType)
    else:
      rest.add(statement)

  if typeSection.isNil:
    error("orchestrate requires a type section", body)
  if artifactTypes.len == 0:
    error("orchestrate requires a non-empty artifact_types section", body)

  for declaration in typeSection:
    if declaration.kind != nnkTypeDef or declaration.len < 3 or
        declaration[2].kind != nnkObjectTy or declaration[0].kind != nnkPostfix:
      error("orchestrate type declarations must be public objects", declaration)
    requirePublicFields(declaration[2])

  let kindName = ident("ArtifactKind")
  let kindType = newTree(nnkEnumTy, newEmptyNode())
  let variant = newTree(nnkRecCase,
    newTree(nnkIdentDefs, publicIdent("kind"), kindName, newEmptyNode()))

  for artifactType in artifactTypes:
    let tag = ident("artifact" & artifactType.strVal)
    kindType.add(tag)
    variant.add(newTree(nnkOfBranch, tag,
      newTree(nnkRecList, newTree(nnkIdentDefs,
        publicIdent(artifactType.strVal.toLowerAscii()), artifactType, newEmptyNode()))))

  typeSection.add(newTree(nnkTypeDef, publicIdent("ArtifactKind"),
    newEmptyNode(), kindType))
  typeSection.add(newTree(nnkTypeDef, publicIdent("Artifact"), newEmptyNode(),
    newTree(nnkObjectTy, newEmptyNode(), newEmptyNode(),
      newTree(nnkRecList, variant))))

  result = newStmtList(typeSection)
  result.add(newTree(nnkIncludeStmt, ident("bezkonza_impl")))
  for statement in rest:
    result.add(statement)
