import std/[sugar, atomics, json, strutils, sequtils, posix, random, paths, dirs, files, macros, options]
import db_connector/db_sqlite
import results
import schematic
import codex_json
import codex_runtime

randomize()

# API
type
  ArtifactID* = uint64
  ArtifactData* = object
    id*: ArtifactID
    artifact_dir*: Path
    data*: Artifact
  Error = object
    message: string
  Outcome*[T] = Result[ArtifactData, Error]
  Consumer*[T] = (Outcome[T] {.closure.} -> void)

type
  Model* = enum
    luna, terra, sol
  Profile = object
    model: Model
    effort: ReasoningEffort
  Prompt = string
  AgentCreationTrigger* = object
    agent_id*: string
    then*: proc () {.gcsafe.}
  AppEventKind* = enum
    runtime_work
    on_agent_creation
    codex_output
    codex_error
    codex_stopped
    terminate
  AppEvent* = object
    case kind*: AppEventKind
    of runtime_work:
      work*: proc () {.gcsafe.}
    of on_agent_creation:
      trigger*: AgentCreationTrigger
    of codex_output, codex_error:
      message*: string
    of codex_stopped, terminate: discard
  ReaderState* = object
    output_fd*, error_fd*, stop_fd*: cint
  ArtifactStorage* = object
    values: seq[ArtifactData]
  Context* = object
    work_dir*: Path
    artifacts*: ArtifactStorage
    agent_id: Atomic[int]
    runtime*: ptr CodexRuntime
    global*: ptr Channel[AppEvent]
    reader_state*: ReaderState
    stop_pipe*: array[0..1, cint]
    pending_on_agent_creation_triggers*: seq[AgentCreationTrigger]
    db*: DbConn
  Contextual*[A, B] =
    ((ptr Context, ArtifactData, Consumer[B]) {.closure.} -> void)

const short_id_alphabet = "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"
var artifact_id_counter: Atomic[uint64]

proc next_artifact_id(): ArtifactID =
  artifact_id_counter.fetchAdd(1) + 1

proc random_short_id(): string =
  result = newString(4)
  for i in 0 ..< result.len:
    result[i] = short_id_alphabet[randState.rand(short_id_alphabet.high)]

proc create_unique_dir(parent: Path; prefix: string): Path =
  while true:
    let candidate = parent / Path(prefix & random_short_id())
    try:
      if not existsOrCreateDir(candidate):
        return candidate
    except IOError:
      discard

proc artifact_location(work_dir: Path; artifact_id: ArtifactID): Path =
  work_dir / Path("artifact-" & $artifact_id)

proc location_path(artifact_dir: Path; location: Location): Path =
  artifact_dir / Path(string(location))

proc `=copy`(dest: var Context; source: Context) {.error.}

template `~>`*(A, B: typedesc): untyped =
  Contextual[A, B]

proc model_name*(model: Model): string =
  case model:
  of luna: "gpt-5.6-luna"
  of terra: "gpt-5.6-terra"
  of sol: "gpt-5.6-sol"

macro to_artifact*(data: typed; artifact: typed): untyped =
  let data_type = data.getTypeInst
  let artifact_impl = artifact.getTypeInst.getTypeImpl
  let variant = artifact_impl[2][0]

  for branch in variant:
    if branch.kind != nnkOfBranch:
      continue

    let field = branch[1][0]
    let field_type = field[^2]
    if sameType(data_type, field_type):
      let field_name =
        if field[0].kind == nnkPostfix: field[0][1]
        else: field[0]
      let converted = newTree(
        nnkObjConstr,
        ident("Artifact"),
        newTree(nnkExprColonExpr, ident("kind"), branch[0]),
        newTree(nnkExprColonExpr, field_name, data)
      )
      return newTree(nnkAsgn, artifact, converted)

  error("type " & data_type.repr & " is not an Artifact variant", data)

proc add_as_artifact[T](
  storage: var ArtifactStorage;
  data: T;
  artifact_dir: Path
): ArtifactData =
  result = ArtifactData(
    id: next_artifact_id(),
    artifact_dir: artifact_dir
  )
  to_artifact(data, result.data)
  storage.values.add(result)

type
  materialize_node_kind = enum
    materialize_inline
    materialize_location
    materialize_object
    materialize_variant
    materialize_seq
    materialize_option
  materialize_field = object
    name: string
    field_name: NimNode
    node: materialize_node
  materialize_branch = object
    tag: NimNode
    is_else: bool
    fields: seq[materialize_field]
  materialize_node = ref object
    kind: materialize_node_kind
    type_name: string
    tag_name: NimNode
    fields: seq[materialize_field]
    branches: seq[materialize_branch]
    element: materialize_node

proc new_materialize_node(kind: materialize_node_kind): materialize_node =
  new(result)
  result.kind = kind

proc is_inline_type(type_node: NimNode): bool =
  case type_node.repr
  of "bool", "char", "string", "cstring",
     "int", "int8", "int16", "int32", "int64",
     "uint", "uint8", "uint16", "uint32", "uint64",
     "float32", "float64":
    true
  else:
    type_node.getTypeImpl.kind == nnkEnumTy

proc resolved_type(type_node: NimNode): NimNode =
  let type_inst = type_node.getTypeInst
  if type_inst.kind == nnkBracketExpr and type_inst[0].strVal == "typeDesc":
    return type_inst[1]
  type_inst

proc field_name(field: NimNode; index: int): NimNode =
  if field[index].kind == nnkPostfix: field[index][1]
  else: field[index]

proc is_location_type(type_node: NimNode): bool =
  let type_inst = resolved_type(type_node)
  type_inst.kind in {nnkIdent, nnkSym} and type_inst.strVal == "Location"

proc materialize_tree(type_node: NimNode): materialize_node

proc materialize_fields(fields: NimNode): seq[materialize_field] =
  for field in fields:
    if field.kind != nnkIdentDefs:
      error("materialize only supports plain object fields", field)

    for index in 0 ..< field.len - 2:
      let name_node = field_name(field, index)
      let name = name_node.strVal
      result.add(materialize_field(
        name: name,
        field_name: copyNimTree(name_node),
        node: materialize_tree(field[^2])
      ))

proc materialize_variant_tree(type_node: NimNode): materialize_node =
  let fields = type_node.getTypeImpl[2]
  var variant: NimNode
  var common_fields = newStmtList()
  for field in fields:
    if field.kind == nnkRecCase:
      variant = field
    else:
      common_fields.add(field)

  if variant.isNil or variant.len < 2 or variant[0].kind != nnkIdentDefs:
    error("materialize cannot inspect object variant", type_node)

  result = new_materialize_node(materialize_variant)
  result.tag_name = copyNimTree(field_name(variant[0], 0))
  result.fields = materialize_fields(common_fields)

  for branch in variant[1 .. ^1]:
    case branch.kind
    of nnkOfBranch:
      let branch_fields = materialize_fields(branch[^1])
      for tag_index in 0 ..< branch.len - 1:
        result.branches.add(materialize_branch(
          tag: copyNimTree(branch[tag_index]),
          is_else: false,
          fields: branch_fields
        ))
    of nnkElse:
      result.branches.add(materialize_branch(
        tag: newEmptyNode(),
        is_else: true,
        fields: materialize_fields(branch[0])
      ))
    else:
      error("materialize cannot inspect object variant branch", branch)

proc materialize_tree(type_node: NimNode): materialize_node =
  let type_inst = type_node.getTypeInst

  if is_location_type(type_inst):
    result = new_materialize_node(materialize_location)
    return
  if is_inline_type(type_inst):
    result = new_materialize_node(materialize_inline)
    result.type_name = type_inst.repr
    return

  case type_inst.kind
  of nnkBracketExpr:
    if type_inst[0].strVal == "seq":
      if type_inst.len != 2:
        error("materialize seq needs one element type", type_node)
      result = new_materialize_node(materialize_seq)
      result.element = materialize_tree(type_inst[1])
      return
    if type_inst[0].strVal == "Option":
      if type_inst.len != 2:
        error("materialize Option needs one element type", type_node)
      result = new_materialize_node(materialize_option)
      result.element = materialize_tree(type_inst[1])
      return
  else:
    discard

  let type_impl = type_inst.getTypeImpl
  case type_impl.kind
  of nnkObjectTy:
    for field in type_impl[2]:
      if field.kind == nnkRecCase:
        return materialize_variant_tree(type_inst)
    result = new_materialize_node(materialize_object)
    result.fields = materialize_fields(type_impl[2])
    return
  else:
    discard

  error("cannot materialize type " & type_inst.repr, type_node)

proc field_value(value, field_name: NimNode): NimNode =
  newTree(nnkDotExpr, copyNimTree(value), copyNimTree(field_name))

proc option_value(value: NimNode): NimNode =
  let value_copy = copyNimTree(value)
  quote do: get(`value_copy`)

proc append_field_path(path: NimNode; name: string): NimNode
proc sequence_path(path, root_name, index: NimNode): NimNode
proc materialize_output_path(path, root_name: NimNode): NimNode

proc append_verification_error(
  errors: NimNode;
  path: NimNode;
  artifact_path: NimNode
): NimNode =
  let errors_copy = copyNimTree(errors)
  let path_copy = copyNimTree(path)
  let artifact_path_copy = copyNimTree(artifact_path)
  quote do:
    `errors_copy`.add(
      `path_copy` & ": location does not exist: " & $(`artifact_path_copy`) & "\n"
    )

proc emit_verify_locations(
  node: materialize_node;
  value: NimNode;
  path: NimNode;
  root_name: NimNode;
  artifact_dir: NimNode;
  errors: NimNode
): NimNode

proc emit_verify_location_fields(
  fields: seq[materialize_field];
  value: NimNode;
  path: NimNode;
  root_name: NimNode;
  artifact_dir: NimNode;
  errors: NimNode
): NimNode =
  result = newStmtList()
  for field in fields:
    result.add(emit_verify_locations(
      field.node,
      field_value(value, field.field_name),
      append_field_path(path, field.name),
      root_name,
      artifact_dir,
      errors
    ))

proc emit_verify_locations(
  node: materialize_node;
  value: NimNode;
  path: NimNode;
  root_name: NimNode;
  artifact_dir: NimNode;
  errors: NimNode
): NimNode =
  case node.kind
  of materialize_inline:
    result = newStmtList()
  of materialize_location:
    let value_copy = copyNimTree(value)
    let artifact_dir_copy = copyNimTree(artifact_dir)
    let artifact_path = quote do:
      location_path(`artifact_dir_copy`, `value_copy`)
    let error_statement = append_verification_error(errors, path, artifact_path)
    result = quote do:
      if not fileExists(`artifact_path`) and not dirExists(`artifact_path`):
        `error_statement`
  of materialize_object:
    result = emit_verify_location_fields(
      node.fields, value, path, root_name, artifact_dir, errors)
  of materialize_variant:
    result = emit_verify_location_fields(
      node.fields, value, path, root_name, artifact_dir, errors)
    let case_statement = newTree(
      nnkCaseStmt,
      field_value(value, node.tag_name)
    )
    for branch in node.branches:
      let branch_statements = emit_verify_location_fields(
        branch.fields, value, path, root_name, artifact_dir, errors)
      if branch.is_else:
        case_statement.add(newTree(nnkElse, branch_statements))
      else:
        case_statement.add(newTree(
          nnkOfBranch,
          copyNimTree(branch.tag),
          branch_statements
        ))
    result.add(case_statement)
  of materialize_seq:
    let index = genSym(nskForVar, "location_index")
    let item = genSym(nskForVar, "location_item")
    let indexed_path = sequence_path(path, root_name, index)
    result = newTree(
      nnkForStmt,
      index,
      item,
      newTree(nnkCall, ident("pairs"), copyNimTree(value)),
      emit_verify_locations(
        node.element,
        item,
        indexed_path,
        root_name,
        artifact_dir,
        errors
      )
    )
  of materialize_option:
    let value_copy = copyNimTree(value)
    let body = emit_verify_locations(
      node.element,
      option_value(value),
      path,
      root_name,
      artifact_dir,
      errors
    )
    result = quote do:
      if isSome(`value_copy`):
        `body`

macro verify_locations(value: typed; artifact_dir: typed): untyped =
  let tree = materialize_tree(value.getTypeInst)
  let errors = genSym(nskVar, "location_errors")
  let body = emit_verify_locations(
    tree,
    value,
    newLit(""),
    newLit(value.repr),
    artifact_dir,
    errors
  )
  quote do:
    block:
      var `errors` = ""
      `body`
      `errors`

proc append_field_path(path: NimNode; name: string): NimNode =
  if path.kind == nnkStrLit:
    if path.strVal.len == 0:
      return newLit(name)
    return newLit(path.strVal & "." & name)
  let suffix = newLit("." & name)
  let path_copy = copyNimTree(path)
  quote do: `path_copy` & `suffix`

proc materialize_sequence_path(
  path: string;
  root_name: string;
  zero_based_index: int
): string =
  let prefix = if path.len == 0: root_name else: path
  prefix & "[" & $(zero_based_index + 1) & "]"

proc sequence_path(path, root_name, index: NimNode): NimNode =
  let path_copy = copyNimTree(path)
  let root_name_copy = copyNimTree(root_name)
  let index_copy = copyNimTree(index)
  quote do:
    materialize_sequence_path(`path_copy`, `root_name_copy`, `index_copy`)

proc materialize_output_path(path, root_name: NimNode): NimNode =
  if path.kind == nnkStrLit and path.strVal.len == 0:
    return copyNimTree(root_name)
  copyNimTree(path)

proc append_instruction(
  instructions: NimNode;
  path: NimNode;
  text: NimNode
): NimNode =
  let instructions_copy = copyNimTree(instructions)
  let path_copy = copyNimTree(path)
  let text_copy = copyNimTree(text)
  quote do:
    `instructions_copy`.add(`path_copy` & `text_copy`)

proc append_instruction(
  instructions: NimNode;
  path: NimNode;
  label: string;
  value: NimNode
): NimNode =
  append_instruction(
    instructions,
    path,
    newTree(
      nnkInfix,
      ident("&"),
      newLit(": " & label & " = "),
      newTree(nnkInfix, ident("&"), copyNimTree(value), newLit("\n"))
    )
  )

proc emit_location_leaf(
  source_artifact_dir: NimNode;
  artifact_dir: NimNode;
  value: NimNode;
  instructions: NimNode;
  output_path: NimNode
): NimNode =
  let source_dir = copyNimTree(source_artifact_dir)
  let source_path = quote do:
    location_path(`source_dir`, `value`)
  let artifact_dir_copy = copyNimTree(artifact_dir)
  let artifact_path = quote do:
    location_path(`artifact_dir_copy`, `value`)
  let instructions_copy = copyNimTree(instructions)
  let output_path_copy = copyNimTree(output_path)
  let artifact_path_copy = copyNimTree(artifact_path)
  let source_path_copy = copyNimTree(source_path)
  let location_value = quote do: string(`value`)
  let location_value_copy = copyNimTree(location_value)
  quote do:
    if fileExists(`source_path_copy`):
      createDir(`artifact_path_copy`.parentDir)
      copyFile(`source_path_copy`, `artifact_path_copy`)
    elif dirExists(`source_path_copy`):
      createDir(`artifact_path_copy`.parentDir)
      copyDir(`source_path_copy`, `artifact_path_copy`)
    else:
      raise newException(
        IOError,
        "materialize Location source does not exist: " & $(`source_path_copy`)
      )
    `instructions_copy`.add(
      `output_path_copy` & ": location = " & `location_value_copy` & "\n"
    )

proc emit_leaf(
  node: materialize_node;
  value: NimNode;
  path: NimNode;
  root_name: NimNode;
  instructions: NimNode;
  artifact_dir: NimNode;
  source_artifact_dir: NimNode
): NimNode =
  let output_path = materialize_output_path(path, root_name)
  result = newStmtList()
  case node.kind
  of materialize_inline:
    let value_text = quote do: $(`value`)
    result.add(append_instruction(
      instructions,
      output_path,
      node.type_name,
      value_text
    ))
  of materialize_location:
    result = emit_location_leaf(
      source_artifact_dir,
      artifact_dir,
      value,
      instructions,
      output_path
    )
  else:
    error("materialize leaf emitter received structural type", value)

proc emit_materialize(
  node: materialize_node;
  value: NimNode;
  path: NimNode;
  root_name: NimNode;
  instructions: NimNode;
  artifact_dir: NimNode;
  source_artifact_dir: NimNode
): NimNode

proc emit_fields(
  fields: seq[materialize_field];
  value: NimNode;
  path: NimNode;
  root_name: NimNode;
  instructions: NimNode;
  artifact_dir: NimNode;
  source_artifact_dir: NimNode
): NimNode =
  result = newStmtList()
  for field in fields:
    let field_expr = field_value(value, field.field_name)
    let field_path = append_field_path(path, field.name)
    result.add(emit_materialize(
      field.node,
      field_expr,
      field_path,
      root_name,
      instructions,
      artifact_dir,
      source_artifact_dir
    ))

proc emit_materialize(
  node: materialize_node;
  value: NimNode;
  path: NimNode;
  root_name: NimNode;
  instructions: NimNode;
  artifact_dir: NimNode;
  source_artifact_dir: NimNode
): NimNode =
  case node.kind
  of materialize_inline, materialize_location:
    result = emit_leaf(
      node,
      value,
      path,
      root_name,
      instructions,
      artifact_dir,
      source_artifact_dir
    )
  of materialize_object:
    result = emit_fields(
      node.fields,
      value,
      path,
      root_name,
      instructions,
      artifact_dir,
      source_artifact_dir
    )
  of materialize_variant:
    result = emit_fields(
      node.fields,
      value,
      path,
      root_name,
      instructions,
      artifact_dir,
      source_artifact_dir
    )
    let case_statement = newTree(
      nnkCaseStmt,
      newTree(
        nnkDotExpr,
        copyNimTree(value),
        copyNimTree(node.tag_name)
      )
    )
    for branch in node.branches:
      let branch_statements = emit_fields(
        branch.fields,
        value,
        path,
        root_name,
        instructions,
        artifact_dir,
        source_artifact_dir
      )
      if branch.is_else:
        case_statement.add(newTree(nnkElse, branch_statements))
      else:
        case_statement.add(newTree(
          nnkOfBranch,
          copyNimTree(branch.tag),
          branch_statements
        ))
    result.add(case_statement)
  of materialize_seq:
    let sequence_index = genSym(nskForVar, "sequence_index")
    let sequence_item = genSym(nskForVar, "sequence_item")
    let indexed_path = sequence_path(path, root_name, sequence_index)
    let body = emit_materialize(
      node.element,
      sequence_item,
      indexed_path,
      root_name,
      instructions,
      artifact_dir,
      source_artifact_dir
    )
    result = newTree(
      nnkForStmt,
      sequence_index,
      sequence_item,
      newTree(nnkCall, ident("pairs"), copyNimTree(value)),
      body
    )
  of materialize_option:
    let output_path = materialize_output_path(path, root_name)
    let some_value = option_value(value)
    let some_branch = emit_materialize(
      node.element,
      some_value,
      path,
      root_name,
      instructions,
      artifact_dir,
      source_artifact_dir
    )
    let none_branch = append_instruction(
      instructions,
      output_path,
      newLit(": Option:none\n")
    )
    let value_copy = copyNimTree(value)
    let some_branch_copy = copyNimTree(some_branch)
    let none_branch_copy = copyNimTree(none_branch)
    result = quote do:
      if isSome(`value_copy`):
        `some_branch_copy`
      else:
        `none_branch_copy`

proc object_field_type(type_node: NimNode; wanted: string): NimNode =
  let type_impl = type_node.getTypeImpl
  if type_impl.kind != nnkObjectTy:
    error("materialize expects ArtifactData, got " & type_node.repr, type_node)
  for field in type_impl[2]:
    if field.kind != nnkIdentDefs:
      continue
    for index in 0 ..< field.len - 2:
      if field_name(field, index).strVal == wanted:
        return copyNimTree(field[^2])
  error("materialize cannot find ArtifactData." & wanted, type_node)

proc append_location_condition(condition, addition: string): string =
  if condition.len == 0: addition
  else: condition & "; " & addition

proc append_location_description(
  result: var seq[string];
  path: string;
  condition: string
) =
  var line = "- " & path
  if condition.len != 0:
    line &= " (" & condition & ")"
  result.add(line)

proc collect_location_paths(
  node: materialize_node;
  path: string;
  condition: string;
  result: var seq[string]
) =
  case node.kind
  of materialize_inline:
    discard
  of materialize_location:
    append_location_description(result, path, condition)
  of materialize_object:
    for field in node.fields:
      collect_location_paths(
        field.node,
        if path.len == 0: field.name else: path & "." & field.name,
        condition,
        result
      )
  of materialize_variant:
    for field in node.fields:
      collect_location_paths(
        field.node,
        if path.len == 0: field.name else: path & "." & field.name,
        condition,
        result
      )
    for branch in node.branches:
      let branch_condition =
        if branch.is_else:
          node.tag_name.strVal & " is another value"
        else:
          node.tag_name.strVal & " = " & branch.tag.repr
      for field in branch.fields:
        collect_location_paths(
          field.node,
          if path.len == 0: field.name else: path & "." & field.name,
          append_location_condition(condition, branch_condition),
          result
        )
  of materialize_seq:
    collect_location_paths(node.element, path & "[*]", condition, result)
  of materialize_option:
    collect_location_paths(
      node.element,
      path,
      append_location_condition(condition, "when present"),
      result
    )

proc location_contract_text(tree: materialize_node): string =
  var paths: seq[string]
  collect_location_paths(tree, "", "", paths)
  if paths.len != 0:
    result = "Location fields:\n" & paths.join("\n")

macro location_contract(T: typedesc): untyped =
  newLit(location_contract_text(materialize_tree(resolved_type(T))))

template output_discriminated_schema(
  T: typedesc;
  discriminator: untyped
): untyped =
  discriminated(T, discriminator)

macro output_schema(T: typedesc): untyped =
  let type_inst = resolved_type(T)
  let tree = materialize_tree(type_inst)
  if tree.kind == materialize_variant:
    return newCall(
      ident"output_discriminated_schema",
      copyNimTree(T),
      ident(tree.tag_name.strVal)
    )
  newCall(bindSym"schemaOf", copyNimTree(T))

macro materialize(
  data: typed;
  instructions: untyped;
  artifact_dir: typed
): untyped =
  let tree = materialize_tree(object_field_type(data.getTypeInst, "data"))
  let payload = field_value(data, ident("data"))
  let source_artifact_dir = field_value(data, ident("artifact_dir"))
  let root_name = newLit(data.repr & ".data")
  let generated_instructions = genSym(nskVar, "generated_instructions")
  let body = emit_materialize(
    tree,
    payload,
    newLit(""),
    root_name,
    generated_instructions,
    artifact_dir,
    source_artifact_dir
  )
  let instructions_copy = copyNimTree(instructions)
  let body_copy = copyNimTree(body)
  result = quote do:
    block:
      let `instructions_copy` = block:
        var `generated_instructions` = ""
        `body_copy`
        `generated_instructions`
      `instructions_copy`

proc submit[B](
  context: ptr Context;
  profile: Profile;
  prompt: Prompt;
  data: ArtifactData;
  callback: Consumer[B]
) =
  let artifact_id = next_artifact_id()
  let artifact_dir = artifact_location(context[].work_dir, artifact_id)
  createDir(artifact_dir)
  let instructions = block:
    try:
      materialize(data, instructions, artifact_dir)
    except CatchableError as e:
      echo "[materialize] failed: ", e.msg
      callback(Outcome[B].err(Error(
        message: "materialize failed: " & e.msg
      )))
      return

  let output_contract = output_schema(B)
  let output_schema = toJsonSchema(output_contract)
  let location_contract = location_contract(B)
  var tools: DynamicToolRegistry = @[]
  tools.register_dynamic_tool(
    "finish_work",
    "Submit final structured result. Call exactly once when task is complete.",
    output_schema,
    nil,
    proc(tool_data: pointer; tool_context: ToolCallContext) =
      context.global[].send(AppEvent(
        kind: runtime_work,
        work: proc () {.gcsafe.} =
          {.cast(gcsafe).}:
            let parsed = output_contract.tryParse(tool_context.params.arguments)
            if not parsed.ok:
              let message = "invalid finish_work result:\n" &
                parsed.issues.mapIt($it).join("\n")
              echo "[finish_work] invalid result: ",
                parsed.issues.mapIt($it).join("; ")
              context.runtime.accept_tool_response(
                tool_context,
                false,
                @[dynamic_tool_text(message)]
              )
              return

            let res = parsed.value
            let verification_error = verify_locations(res, artifact_dir)
            if verification_error.len != 0:
              echo "[finish_work] location check failed: ",
                verification_error.replace("\n", "; ")
              context.runtime.accept_tool_response(
                tool_context,
                false,
                @[dynamic_tool_text(verification_error)]
              )
              return

            context.runtime.accept_tool_response(
              tool_context,
              true,
              @[dynamic_tool_text($tool_context.params.arguments)]
            )
            var artifact_data = ArtifactData(
              id: artifact_id,
              artifact_dir: artifact_dir
            )
            to_artifact(res, artifact_data.data)
            callback(Outcome[B].ok(artifact_data))
      ))
  )

  let agent_id = $context.agent_id.fetchAdd(1)
  discard context.runtime.create_agent(
    agent_id = agent_id,
    model = model_name(profile.model),
    tools = tools,
    developer_instructions = "Complete task. Submit final result with `finish_work`. None of your responses outside of tool call response is observable. Do not narrate your actions ever.",
    default_effort = profile.effort
  )

  context.global[].send(AppEvent(
    kind: on_agent_creation,
    trigger: AgentCreationTrigger(
      agent_id: agent_id,
      then: proc () {.gcsafe.} =
        {.cast(gcsafe).}:
          discard context.runtime.set_agent_goal(agent_id, "Complete task. Call `finish_work` exactly once with final result.")
          let message = """
            You may only modify files in $artifact_dir. This is your working directory.
            
            = Prompt
            $prompt

            = Input
            This is explicit input given to you. Fields marked of type `location` are paths relative to $artifact_dir.
            $input

            = Location contract
            Location values are strings containing paths relative to $artifact_dir. Each path must reference an existing file or directory. Output will be rejected if the value you submit to `finish_work` tool for these fields is not a path to a file or directory RELATIVE TO $artifact_dir. If a field is a string but it is not explicitly one of the locations listed below, it is a string literal that you must fill in in the `finish_work` tool call.
            $location_contract

            = Output
            finish_work input schema:
            $output_schema
          """.dedent() % [
            "prompt", prompt,
            "input", instructions,
            "location_contract", location_contract,
            "artifact_dir", $artifact_dir,
            "output_schema", $output_schema
          ]
          discard context.runtime.send_agent_message(
            agent_id,
            message
          )
    )))

proc `>>>`*[A, B, C](
  left: Contextual[A, B];
  right: Contextual[B, C]
): Contextual[A, C] =
  (ctx: ptr Context, value: ArtifactData, consumer: Consumer[C]) =>
    left(ctx, value, (outcome: Outcome[B]) => (
      if outcome.isErr: consumer(Outcome[C].err(outcome.error))
      else: right(ctx, outcome.get, consumer)))

proc `[]`*[A, B](profile: Profile; _: typedesc[A]; _: typedesc[B]): (Prompt -> Contextual[A, B]) =
  result = (prompt: Prompt,) =>
    ((ctx: ptr Context, value: ArtifactData, consumer: Consumer[B]) {.closure.} =>
      submit(ctx, profile, prompt.dedent(), value, consumer))

proc minimal*(model: Model): Profile = Profile(model: model, effort: re_minimal)
proc low*(model: Model): Profile = Profile(model: model, effort: re_low)
proc medium*(model: Model): Profile = Profile(model: model, effort: re_medium)
proc high*(model: Model): Profile = Profile(model: model, effort: re_high)
proc xhigh*(model: Model): Profile = Profile(model: model, effort: re_xhigh)

type RuntimeArgs[P, R] = object
  problem: ptr P
  solver: ptr Contextual[P, R]
  outcome: ptr Outcome[R]

const relative_logs_db_path = Path("logs.db")

proc read_codex(
  context: ptr Context;
  fd: cint;
  event_kind: static AppEventKind
) {.gcsafe.} =
  static: doAssert event_kind == codex_output or event_kind == codex_error
  
  var watched = [
    TPollfd(fd: fd, events: POLLIN, revents: 0),
    TPollfd(fd: context.reader_state.stop_fd, events: POLLIN, revents: 0)
  ]
  var pending = ""
  var reached_eof = false

  while true:
    if poll(addr watched[0], Tnfds(2), -1) < 0:
      break

    if watched[1].revents != 0:
      break

    if watched[0].revents != 0:
      var buffer: array[4096, char]
      let count = read(fd, addr buffer[0], buffer.len)
      if count <= 0:
        reached_eof = true
        break
      let s = newString(count)
      copyMem(addr s[0], addr buffer[0], count)
      pending.add(s)
      while true:
        let newline = pending.find('\n')
        if newline < 0:
          break
        let message = pending[0 ..< newline]
        pending.delete(0 .. newline)
        context.global[].send(AppEvent(
          kind: event_kind,
          message: message
        ))

  if reached_eof:
    context.global[].send(AppEvent(kind: codex_stopped))

proc read_codex_output(context: ptr Context) {.thread, gcsafe.} =
  read_codex(context, context.reader_state.output_fd, codex_output)

proc read_codex_error(context: ptr Context) {.thread, gcsafe.} =
  read_codex(context, context.reader_state.error_fd, codex_error)

proc runtime[P, R](
  args: ptr RuntimeArgs[P, R]
) {.thread.} =
  let outcome = args.outcome

  var context = Context()

  let problem_artifact = context.artifacts.add_as_artifact(
    args.problem[],
    getCurrentDir()
  )

  context.work_dir = create_unique_dir(getCurrentDir(), "run-")

  context.db = open($(context.work_dir / relative_logs_db_path), "", "", "")
  defer: context.db.close()

  context.db.exec(sql"""
    DROP TABLE IF EXISTS messages
  """)
  context.db.exec(sql"""
    CREATE TABLE IF NOT EXISTS messages (
      id      INTEGER PRIMARY KEY,
      type    TEXT NOT NULL CHECK (type in ('AGENT_MESSAGE', 'USER_MESSAGE', 'TOOL_CALL')),
      message TEXT NOT NULL
    )
  """)

  context.runtime = init_codex_runtime($context.work_dir)
  defer: context.runtime.deinit_codex_runtime()

  doAssert pipe(context.stop_pipe) == 0
  defer: discard close(context.stop_pipe[0])
  defer: discard close(context.stop_pipe[1])

  var global: Channel[AppEvent]

  global.open()
  defer: context.global[].close()

  context.reader_state = ReaderState(
    output_fd: context.runtime.output_handle(),
    error_fd: context.runtime.error_handle(),
    stop_fd: context.stop_pipe[0]
  )
  context.global = addr global

  var reader_thread: Thread[ptr Context]
  reader_thread.createThread(read_codex_output, addr context)
  defer: reader_thread.joinThread()

  var error_thread: Thread[ptr Context]
  error_thread.createThread(read_codex_error, addr context)
  defer: error_thread.joinThread()

  context.global[].send(AppEvent(
    kind: runtime_work,
    work: proc () {.gcsafe.} =
      {.cast(gcsafe).}:
        args.solver[](addr context, problem_artifact, proc (local_outcome: Outcome[R]) =
          outcome[] = local_outcome
          context.global[].send(AppEvent(kind: terminate)))))

  while true:
    let msg = context.global[].recv()
    case msg.kind:
    of runtime_work: msg.work()
    of on_agent_creation: context.pending_on_agent_creation_triggers.add(msg.trigger)
    of codex_output:
      let message = context.runtime.accept_json(parseJson(msg.message))
      if context.runtime.initialization_error.isSome:
        args.outcome[] = Outcome[R].err(Error(
          message: "codex initialization failed: " &
            context.runtime.initialization_error.get
        ))
        context.global[].send(AppEvent(kind: terminate))
      elif message.kind == mk_notification:
        let notification = message.notification
        if notification.method_name == "item/completed":
          let notif_type = notification.params.extra_fields["item"]["type"].getStr()
          if notif_type == "agentMessage":
            context.db.exec(
              sql"INSERT INTO messages (type, message) VALUES (?, ?)",
              "AGENT_MESSAGE", notification.params.extra_fields["item"]["text"].getStr()
            )
          elif notif_type == "userMessage":
            context.db.exec(
              sql"INSERT INTO messages (type, message) VALUES (?, ?)",
              "USER_MESSAGE", notification.params.extra_fields["item"]["content"]
                .getElems()
                .filter((e: JsonNode) => e["type"].getStr() == "text")
                .foldl(a & "\n" & b["text"].getStr(), "")
            )
      for i in countdown(context.pending_on_agent_creation_triggers.len - 1, 0):
        let agent_id = context.pending_on_agent_creation_triggers[i].agent_id
        if context.runtime.agents[agent_id].thread_id.has_value:
          context.pending_on_agent_creation_triggers[i].then()
          context.pending_on_agent_creation_triggers.del(i)
    of codex_error:
      echo msg.message
      if not context.runtime.initialized and msg.message.strip.startsWith("Error:"):
        args.outcome[] = Outcome[R].err(Error(
          message: "codex app-server startup failed: " & msg.message.strip
        ))
        context.global[].send(AppEvent(kind: terminate))
    of codex_stopped:
      if not context.runtime.initialized:
        args.outcome[] = Outcome[R].err(Error(
          message: "codex app-server exited before initialization"
        ))
        context.global[].send(AppEvent(kind: terminate))
    of terminate:
      var signal = 'x'
      discard write(context.stop_pipe[1], addr signal, 1)

      break

  for row in context.db.rows(sql"SELECT type, message FROM messages"): echo row[0], ": ", row[1]

proc start*[P, R](
  problem: P;
  solver: P ~> R;
  consumer: Consumer[R]
) =
  var outcome: Outcome[R]
  var runtime_args = RuntimeArgs[P, R](
    problem: addr problem,
    solver: addr solver,
    outcome: addr outcome
  )
  var runtime_thread: Thread[ptr RuntimeArgs[P, R]]

  runtime_thread.createThread(runtime, addr runtime_args)
  runtime_thread.joinThread()

  consumer(outcome)
