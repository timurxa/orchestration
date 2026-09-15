import std/[json, options, tables]

type
  JsonObject* = Table[string, JsonNode]

  RequestKind* = enum
    mk_initialize,
    mk_thread_start,
    mk_turn_start,
    mk_thread_goal_set,
    mk_thread_stop

  ServerRequestKind* = enum
    sr_command_execution_approval,
    sr_file_change_approval,
    sr_tool_user_input,
    sr_tool_call,
    sr_auth_tokens_refresh,
    sr_apply_patch_approval,
    sr_exec_command_approval,
    sr_mcp_server_elicitation,
    sr_permission_request,
    sr_unknown

  RequestIdKind* = enum
    rid_string,
    rid_integer

  RequestId* = object
    case kind*: RequestIdKind
    of rid_string:
      string_value*: string
    of rid_integer:
      integer_value*: int64

  AskForApproval* = enum
    apa_untrusted,
    apa_on_failure,
    apa_on_request,
    apa_never

  SandboxMode* = enum
    sm_read_only,
    sm_workspace_write,
    sm_danger_full_access

  Personality* = enum
    p_none,
    p_friendly,
    p_pragmatic

  ReasoningEffort* = enum
    re_none,
    re_low,
    re_medium,
    re_high,
    re_xhigh,
    re_max

  TurnStatus* = enum
    ts_in_progress,
    ts_completed,
    ts_interrupted,
    ts_failed,
    ts_unknown

  ThreadStatusKind* = enum
    tsk_idle,
    tsk_active,
    tsk_system_error,
    tsk_not_loaded,
    tsk_unknown

  ActiveFlag* = enum
    af_waiting_on_approval,
    af_waiting_on_user_input

  Nullable*[T] = object
    case has_value*: bool
    of false:
      discard
    of true:
      value*: T

  NullableOptionState* = enum
    nos_none,
    nos_null,
    nos_value

  NullableOption*[T] = object
    case state*: NullableOptionState
    of nos_none, nos_null:
      discard
    of nos_value:
      value*: T

  InitializeCapabilities* = object
    experimental_api*: NullableOption[bool]
    opt_out_notification_methods*: NullableOption[seq[string]]
    extra_fields*: JsonObject

  ClientInfo* = object
    name*: string
    title*: NullableOption[string]
    version*: string
    extra_fields*: JsonObject

  InitializeParams* = object
    capabilities*: NullableOption[InitializeCapabilities]
    client_info*: ClientInfo
    extra_fields*: JsonObject

  Config* = JsonObject

  ThreadStartParams* = object
    approval_policy*: NullableOption[AskForApproval]
    base_instructions*: NullableOption[string]
    config*: NullableOption[Config]
    cwd*: NullableOption[string]
    developer_instructions*: NullableOption[string]
    sandbox*: NullableOption[SandboxMode]
    ephemeral*: NullableOption[bool]
    model_provider*: NullableOption[string]
    personality*: NullableOption[Personality]
    model*: NullableOption[string]
    dynamic_tools*: NullableOption[seq[DynamicToolSpec]]
    extra_fields*: JsonObject

  TextInput* = object
    text*: string
    extra_fields*: JsonObject

  TurnStartParams* = object
    thread_id*: string
    text*: string
    effort*: NullableOption[ReasoningEffort]
    extra_fields*: JsonObject

  ThreadGoalSetParams* = object
    thread_id*: string
    objective*: string
    extra_fields*: JsonObject

  ThreadStopParams* = object
    thread_id*: string
    extra_fields*: JsonObject

  Params* = object
    case kind*: RequestKind
    of mk_initialize:
      initialize*: InitializeParams
    of mk_thread_start:
      thread_start*: ThreadStartParams
    of mk_turn_start:
      turn_start*: TurnStartParams
    of mk_thread_goal_set:
      thread_goal_set*: ThreadGoalSetParams
    of mk_thread_stop:
      thread_stop*: ThreadStopParams

  Request* = object
    kind*: RequestKind
    id*: RequestId
    params*: Params
    extra_fields*: JsonObject

  CommandActionKind* = enum
    cak_read,
    cak_list_files,
    cak_search,
    cak_unknown

  CommandAction* = object
    kind*: CommandActionKind
    command*: string
    name*: NullableOption[string]
    path*: NullableOption[string]
    query*: NullableOption[string]
    extra_fields*: JsonObject

  ParsedCommandKind* = enum
    pck_read,
    pck_list_files,
    pck_search,
    pck_unknown

  ParsedCommand* = object
    kind*: ParsedCommandKind
    cmd*: string
    name*: NullableOption[string]
    path*: NullableOption[string]
    query*: NullableOption[string]
    extra_fields*: JsonObject

  CommandExecutionRequestApprovalParams* = object
    approval_id*: NullableOption[string]
    command*: NullableOption[string]
    command_actions*: NullableOption[seq[CommandAction]]
    cwd*: NullableOption[string]
    item_id*: string
    proposed_execpolicy_amendment*: NullableOption[seq[string]]
    reason*: NullableOption[string]
    thread_id*: string
    turn_id*: string
    extra_fields*: JsonObject

  FileChangeKind* = enum
    fck_add,
    fck_delete,
    fck_update,
    fck_unknown

  FileChange* = object
    kind*: FileChangeKind
    content*: NullableOption[string]
    move_path*: NullableOption[string]
    unified_diff*: NullableOption[string]
    extra_fields*: JsonObject

  FileChangeRequestApprovalParams* = object
    grant_root*: NullableOption[string]
    item_id*: string
    reason*: NullableOption[string]
    thread_id*: string
    turn_id*: string
    extra_fields*: JsonObject

  ToolRequestUserInputOption* = object
    description*: string
    label*: string
    extra_fields*: JsonObject

  ToolRequestUserInputQuestion* = object
    header*: string
    id*: string
    is_other*: NullableOption[bool]
    is_secret*: NullableOption[bool]
    options*: NullableOption[seq[ToolRequestUserInputOption]]
    question*: string
    extra_fields*: JsonObject

  ToolRequestUserInputParams* = object
    item_id*: string
    questions*: seq[ToolRequestUserInputQuestion]
    thread_id*: string
    turn_id*: string
    extra_fields*: JsonObject

  DynamicToolCallParams* = object
    arguments*: JsonNode
    call_id*: string
    thread_id*: string
    tool*: string
    turn_id*: string
    extra_fields*: JsonObject

  ToolCallContext* = object
    request_id*: RequestId
    params*: DynamicToolCallParams

  DynamicToolCallback* = proc(data: pointer; context: ToolCallContext) {.nimcall, gcsafe.}

  DynamicTool* = object
    name*: string
    description*: string
    input_schema*: JsonNode
    data*: pointer
    callback*: DynamicToolCallback

  DynamicToolRegistry* = seq[DynamicTool]

  DynamicToolSpec* = object
    name*: string
    description*: string
    input_schema*: JsonNode
    extra_fields*: JsonObject

  DynamicToolContentKind* = enum
    dtc_input_text,
    dtc_input_image,
    dtc_input_audio

  DynamicToolContentItem* = object
    case kind*: DynamicToolContentKind
    of dtc_input_text:
      text*: string
    of dtc_input_image:
      image_url*: string
    of dtc_input_audio:
      audio_url*: string

  DynamicToolCallResponse* = object
    success*: bool
    content_items*: seq[DynamicToolContentItem]

  AuthTokensRefreshReason* = enum
    atrr_unauthorized,
    atrr_unknown

  ChatgptAuthTokensRefreshParams* = object
    previous_account_id*: NullableOption[string]
    reason*: AuthTokensRefreshReason
    extra_fields*: JsonObject

  ApplyPatchApprovalParams* = object
    call_id*: string
    conversation_id*: string
    file_changes*: Table[string, FileChange]
    grant_root*: NullableOption[string]
    reason*: NullableOption[string]
    extra_fields*: JsonObject

  ExecCommandApprovalParams* = object
    approval_id*: NullableOption[string]
    call_id*: string
    command*: seq[string]
    conversation_id*: string
    cwd*: string
    parsed_cmd*: seq[ParsedCommand]
    reason*: NullableOption[string]
    extra_fields*: JsonObject

  ServerRequestParams* = object
    case kind*: ServerRequestKind
    of sr_command_execution_approval:
      command_execution_approval*: CommandExecutionRequestApprovalParams
    of sr_file_change_approval:
      file_change_approval*: FileChangeRequestApprovalParams
    of sr_tool_user_input:
      tool_user_input*: ToolRequestUserInputParams
    of sr_tool_call:
      tool_call*: DynamicToolCallParams
    of sr_auth_tokens_refresh:
      auth_tokens_refresh*: ChatgptAuthTokensRefreshParams
    of sr_apply_patch_approval:
      apply_patch_approval*: ApplyPatchApprovalParams
    of sr_exec_command_approval:
      exec_command_approval*: ExecCommandApprovalParams
    of sr_mcp_server_elicitation, sr_permission_request:
      raw*: JsonNode
    of sr_unknown:
      unknown*: JsonNode

  Error* = object
    id*: RequestId
    code*: int64
    message*: string
    extra_fields*: JsonObject

  ServerRequest* = object
    id*: RequestId
    kind*: ServerRequestKind
    method_name*: string
    params*: ServerRequestParams
    extra_fields*: JsonObject

  ServerResponse* = object
    id*: RequestId
    result*: Option[JsonNode]
    error*: Option[Error]
    extra_fields*: JsonObject

  NotificationKind* = enum
    nk_initialized,
    nk_thread_started,
    nk_turn_started,
    nk_turn_completed,
    nk_agent_message_delta,
    nk_thread_status_changed,
    nk_thread_closed,
    nk_server_request_resolved,
    nk_error,
    nk_unknown

  NotificationParams* = object
    thread_id*: Nullable[string]
    request_id*: Option[RequestId]
    turn_id*: Option[string]
    turn_status*: Option[TurnStatus]
    delta*: Option[string]
    thread_status*: Option[ThreadStatusKind]
    active_flags*: set[ActiveFlag]
    error_message*: Option[string]
    thread_extra_fields*: JsonObject
    turn_extra_fields*: JsonObject
    extra_fields*: JsonObject

  Notification* = object
    kind*: NotificationKind
    method_name*: string
    params*: NotificationParams
    extra_fields*: JsonObject

  ResponseResult* = object
    case kind*: RequestKind
    of mk_initialize:
      discard
    of mk_thread_start:
      thread_id*: string
      thread_extra_fields*: JsonObject
    of mk_turn_start:
      turn_id*: string
      turn_status*: TurnStatus
      turn_extra_fields*: JsonObject
    of mk_thread_goal_set:
      discard
    of mk_thread_stop:
      discard

  Success* = object
    id*: RequestId
    result*: ResponseResult
    raw_result*: JsonNode
    extra_fields*: JsonObject

  MessageKind* = enum
    mk_request,
    mk_server_request,
    mk_server_response,
    mk_success,
    mk_error,
    mk_notification

  Message* = object
    case kind*: MessageKind
    of mk_request:
      request*: Request
    of mk_server_request:
      server_request*: ServerRequest
    of mk_server_response:
      server_response*: ServerResponse
    of mk_success:
      success*: Success
    of mk_error:
      error*: Error
    of mk_notification:
      notification*: Notification

proc register_dynamic_tool*(registry: var DynamicToolRegistry;
    name, description: string; input_schema: JsonNode; data: pointer;
    callback: DynamicToolCallback) =
  registry.add(DynamicTool(
    name: name,
    description: description,
    input_schema: input_schema,
    data: data,
    callback: callback
  ))

proc dynamic_tool_text*(text: string): DynamicToolContentItem =
  DynamicToolContentItem(kind: dtc_input_text, text: text)

proc dynamic_tool_image*(image_url: string): DynamicToolContentItem =
  DynamicToolContentItem(kind: dtc_input_image, image_url: image_url)

proc dynamic_tool_audio*(audio_url: string): DynamicToolContentItem =
  DynamicToolContentItem(kind: dtc_input_audio, audio_url: audio_url)

proc json_object*(node: JsonNode): JsonObject =
  if node.kind != JObject:
    raise newException(ValueError, "expected a JSON object")
  result = initTable[string, JsonNode]()
  for key, value in node.pairs:
    result[key] = value

proc json_object_node(value: JsonObject): JsonNode =
  result = newJObject()
  for key, item in value.pairs:
    result[key] = item

proc extra_fields(node: JsonNode; known: varargs[string]): JsonObject =
  result = initTable[string, JsonNode]()
  if node.kind != JObject:
    return
  for key, value in node.pairs:
    var is_known = false
    for known_key in known:
      if key == known_key:
        is_known = true
        break
    if not is_known:
      result[key] = value

proc add_extra_fields(node: JsonNode; fields: JsonObject) =
  for key, value in fields.pairs:
    node[key] = value

proc put_nullable_option[T](node: JsonNode; key: string;
    value: NullableOption[T]; serialize: proc(value: T): JsonNode {.gcsafe.}) =
  case value.state:
  of nos_none:
    discard
  of nos_null:
    node[key] = newJNull()
  of nos_value:
    node[key] = serialize(value.value)

proc nullable_parsed[T](node: JsonNode; key: string;
    parse: proc(value: JsonNode): T {.gcsafe.}): NullableOption[T] =
  if not node.contains(key):
    return NullableOption[T](state: nos_none)
  if node[key].kind == JNull:
    return NullableOption[T](state: nos_null)
  NullableOption[T](state: nos_value, value: parse(node[key]))

proc nullable_string(node: JsonNode; key: string): NullableOption[string] =
  if not node.contains(key):
    return NullableOption[string](state: nos_none)
  if node[key].kind == JNull:
    return NullableOption[string](state: nos_null)
  NullableOption[string](state: nos_value, value: node[key].getStr)

proc nullable_bool(node: JsonNode; key: string): NullableOption[bool] =
  if not node.contains(key):
    return NullableOption[bool](state: nos_none)
  if node[key].kind == JNull:
    return NullableOption[bool](state: nos_null)
  NullableOption[bool](state: nos_value, value: node[key].getBool)

proc parse_strings(node: JsonNode): seq[string] =
  for item in node:
    result.add(item.getStr)

proc json_node(value: string): JsonNode = %value
proc json_node(value: bool): JsonNode = %value
proc json_node(value: int64): JsonNode = %value
proc json_node(value: AskForApproval): JsonNode =
  case value:
  of apa_untrusted: %"unlessTrusted"
  of apa_on_failure: %"onFailure"
  of apa_on_request: %"onRequest"
  of apa_never: %"never"

proc json_node(value: SandboxMode): JsonNode =
  case value:
  of sm_read_only: %"read-only"
  of sm_workspace_write: %"workspace-write"
  of sm_danger_full_access: %"danger-full-access"

proc json_node(value: Personality): JsonNode =
  case value:
  of p_none: %"none"
  of p_friendly: %"friendly"
  of p_pragmatic: %"pragmatic"

proc json_node(value: ReasoningEffort): JsonNode =
  case value:
  of re_none: %"none"
  of re_low: %"low"
  of re_medium: %"medium"
  of re_high: %"high"
  of re_xhigh: %"xhigh"
  of re_max: %"max"

proc json_node(value: RequestId): JsonNode =
  case value.kind:
  of rid_string: %value.string_value
  of rid_integer: %value.integer_value

proc request_id_key*(value: RequestId): string =
  case value.kind:
  of rid_string: "s:" & value.string_value
  of rid_integer: "i:" & $value.integer_value

proc `==`(left, right: RequestId): bool =
  if left.kind != right.kind:
    return false
  case left.kind:
  of rid_string:
    left.string_value == right.string_value
  of rid_integer:
    left.integer_value == right.integer_value

proc json_node(value: seq[string]): JsonNode =
  result = newJArray()
  for item in value:
    result.add(%item)

proc serialize_dynamic_tool_spec(value: DynamicToolSpec): JsonNode =
  result = newJObject()
  add_extra_fields(result, value.extra_fields)
  result["type"] = %"function"
  result["name"] = %value.name
  result["description"] = %value.description
  result["inputSchema"] = value.input_schema

proc serialize_dynamic_tool_specs(value: seq[DynamicToolSpec]): JsonNode =
  result = newJArray()
  for item in value:
    result.add(serialize_dynamic_tool_spec(item))

proc serialize_dynamic_tool_content_item(value: DynamicToolContentItem): JsonNode =
  result = newJObject()
  case value.kind:
  of dtc_input_text:
    result["type"] = %"inputText"
    result["text"] = %value.text
  of dtc_input_image:
    result["type"] = %"inputImage"
    result["imageUrl"] = %value.image_url
  of dtc_input_audio:
    result["type"] = %"inputAudio"
    result["audioUrl"] = %value.audio_url

proc serialize_dynamic_tool_call_response*(value: DynamicToolCallResponse): JsonNode =
  result = newJObject()
  result["success"] = %value.success
  result["contentItems"] = newJArray()
  for item in value.content_items:
    result["contentItems"].add(serialize_dynamic_tool_content_item(item))

proc parse_ask_for_approval(node: JsonNode): AskForApproval =
  case node.getStr:
  of "unlessTrusted": apa_untrusted
  of "onFailure": apa_on_failure
  of "onRequest": apa_on_request
  of "never": apa_never
  else: raise newException(ValueError, "unknown approval policy")

proc parse_sandbox_mode(node: JsonNode): SandboxMode =
  case node.getStr:
  of "read-only": sm_read_only
  of "workspace-write": sm_workspace_write
  of "danger-full-access": sm_danger_full_access
  else: raise newException(ValueError, "unknown sandbox mode")

proc parse_personality(node: JsonNode): Personality =
  case node.getStr:
  of "none": p_none
  of "friendly": p_friendly
  of "pragmatic": p_pragmatic
  else: raise newException(ValueError, "unknown personality")

proc parse_reasoning_effort(node: JsonNode): ReasoningEffort =
  case node.getStr:
  of "none": re_none
  of "low": re_low
  of "medium": re_medium
  of "high": re_high
  of "xhigh": re_xhigh
  of "max": re_max
  else: raise newException(ValueError, "unknown reasoning effort")

proc parse_turn_status(node: JsonNode): TurnStatus =
  case node.getStr:
  of "inProgress": ts_in_progress
  of "completed": ts_completed
  of "interrupted": ts_interrupted
  of "failed": ts_failed
  else: ts_unknown

proc serialize_initialize_capabilities(value: InitializeCapabilities): JsonNode =
  result = newJObject()
  add_extra_fields(result, value.extra_fields)
  put_nullable_option(result, "experimentalApi", value.experimental_api, json_node)
  put_nullable_option(result, "optOutNotificationMethods", value.opt_out_notification_methods, json_node)

proc parse_initialize_capabilities(node: JsonNode): InitializeCapabilities =
  InitializeCapabilities(
    experimental_api: nullable_bool(node, "experimentalApi"),
    opt_out_notification_methods: nullable_parsed(node, "optOutNotificationMethods", parse_strings),
    extra_fields: extra_fields(node, "experimentalApi", "optOutNotificationMethods")
  )

proc serialize_client_info(info: ClientInfo): JsonNode =
  result = newJObject()
  add_extra_fields(result, info.extra_fields)
  result["name"] = %info.name
  put_nullable_option(result, "title", info.title, json_node)
  result["version"] = %info.version

proc parse_client_info(node: JsonNode): ClientInfo =
  ClientInfo(
    name: node["name"].getStr,
    title: nullable_string(node, "title"),
    version: node["version"].getStr,
    extra_fields: extra_fields(node, "name", "title", "version")
  )

proc serialize_initialize_params(params: InitializeParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)
  put_nullable_option(result, "capabilities", params.capabilities, serialize_initialize_capabilities)
  result["clientInfo"] = serialize_client_info(params.client_info)

proc parse_initialize_params(node: JsonNode): InitializeParams =
  InitializeParams(
    capabilities: nullable_parsed(node, "capabilities", parse_initialize_capabilities),
    client_info: parse_client_info(node["clientInfo"]),
    extra_fields: extra_fields(node, "capabilities", "clientInfo")
  )

proc serialize_thread_start_params(params: ThreadStartParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)
  put_nullable_option(result, "approvalPolicy", params.approval_policy, json_node)
  put_nullable_option(result, "baseInstructions", params.base_instructions, json_node)
  put_nullable_option(result, "config", params.config, json_object_node)
  put_nullable_option(result, "cwd", params.cwd, json_node)
  put_nullable_option(result, "developerInstructions", params.developer_instructions, json_node)
  put_nullable_option(result, "sandbox", params.sandbox, json_node)
  put_nullable_option(result, "ephemeral", params.ephemeral, json_node)
  put_nullable_option(result, "modelProvider", params.model_provider, json_node)
  put_nullable_option(result, "personality", params.personality, json_node)
  put_nullable_option(result, "model", params.model, json_node)
  put_nullable_option(result, "dynamicTools", params.dynamic_tools, serialize_dynamic_tool_specs)

proc parse_dynamic_tool_spec(node: JsonNode): DynamicToolSpec =
  if node["type"].getStr != "function":
    raise newException(ValueError, "only function dynamic tools are supported")
  DynamicToolSpec(
    name: node["name"].getStr,
    description: node["description"].getStr,
    input_schema: node["inputSchema"],
    extra_fields: extra_fields(node, "type", "name", "description", "inputSchema")
  )

proc parse_dynamic_tool_specs(node: JsonNode): seq[DynamicToolSpec] =
  result = @[]
  for item in node:
    result.add(parse_dynamic_tool_spec(item))

proc parse_thread_start_params(node: JsonNode): ThreadStartParams =
  ThreadStartParams(
    approval_policy: nullable_parsed(node, "approvalPolicy", parse_ask_for_approval),
    base_instructions: nullable_string(node, "baseInstructions"),
    config: nullable_parsed(node, "config", json_object),
    cwd: nullable_string(node, "cwd"),
    developer_instructions: nullable_string(node, "developerInstructions"),
    sandbox: nullable_parsed(node, "sandbox", parse_sandbox_mode),
    ephemeral: nullable_bool(node, "ephemeral"),
    model_provider: nullable_string(node, "modelProvider"),
    personality: nullable_parsed(node, "personality", parse_personality),
    model: nullable_string(node, "model"),
    dynamic_tools: nullable_parsed(node, "dynamicTools", parse_dynamic_tool_specs),
    extra_fields: extra_fields(node, "approvalPolicy", "baseInstructions", "config", "cwd", "developerInstructions", "sandbox", "ephemeral", "modelProvider", "personality", "model", "dynamicTools")
  )

proc serialize_text_input(value: TextInput): JsonNode =
  result = newJObject()
  add_extra_fields(result, value.extra_fields)
  result["type"] = %"text"
  result["text"] = %value.text

proc serialize_turn_start_params(params: TurnStartParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)
  result["threadId"] = %params.thread_id
  result["input"] = newJArray()
  result["input"].add(serialize_text_input(TextInput(text: params.text)))
  put_nullable_option(result, "effort", params.effort, json_node)

proc serialize_thread_goal_set_params(params: ThreadGoalSetParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)
  result["threadId"] = %params.thread_id
  result["objective"] = %params.objective

proc serialize_thread_stop_params(params: ThreadStopParams): JsonNode =
  result = newJObject()
  add_extra_fields(result, params.extra_fields)
  result["threadId"] = %params.thread_id

proc serialize_params(params: Params): JsonNode =
  case params.kind:
  of mk_initialize: serialize_initialize_params(params.initialize)
  of mk_thread_start: serialize_thread_start_params(params.thread_start)
  of mk_turn_start: serialize_turn_start_params(params.turn_start)
  of mk_thread_goal_set: serialize_thread_goal_set_params(params.thread_goal_set)
  of mk_thread_stop: serialize_thread_stop_params(params.thread_stop)

proc serialize_message*(message: Message): JsonNode =
  result = newJObject()
  case message.kind:
  of mk_request:
    add_extra_fields(result, message.request.extra_fields)
    result["id"] = json_node(message.request.id)
    case message.request.kind:
    of mk_initialize: result["method"] = %"initialize"
    of mk_thread_start: result["method"] = %"thread/start"
    of mk_turn_start: result["method"] = %"turn/start"
    of mk_thread_goal_set: result["method"] = %"thread/goal/set"
    of mk_thread_stop: result["method"] = %"thread/stop"
    result["params"] = serialize_params(message.request.params)
  of mk_server_request:
    raise newException(ValueError, "server requests are not client-sendable")
  of mk_server_response:
    add_extra_fields(result, message.server_response.extra_fields)
    result["id"] = json_node(message.server_response.id)
    if message.server_response.result.isSome:
      result["result"] = message.server_response.result.get
    elif message.server_response.error.isSome:
      let error = message.server_response.error.get
      result["error"] = newJObject()
      add_extra_fields(result["error"], error.extra_fields)
      result["error"]["code"] = %error.code
      result["error"]["message"] = %error.message
    else:
      raise newException(ValueError, "server response needs result or error")
  of mk_success:
    add_extra_fields(result, message.success.extra_fields)
    result["id"] = json_node(message.success.id)
    result["result"] = message.success.raw_result
  of mk_error:
    result["id"] = json_node(message.error.id)
    result["error"] = newJObject()
    add_extra_fields(result["error"], message.error.extra_fields)
    result["error"]["code"] = %message.error.code
    result["error"]["message"] = %message.error.message
  of mk_notification:
    add_extra_fields(result, message.notification.extra_fields)
    case message.notification.kind:
    of nk_initialized:
      result["method"] = %"initialized"
      result["params"] = newJObject()
      add_extra_fields(result["params"], message.notification.params.extra_fields)
    else:
      raise newException(ValueError, "only initialized notification is client-sendable")

proc server_request_kind*(method_name: string): ServerRequestKind =
  case method_name:
  of "item/commandExecution/requestApproval": sr_command_execution_approval
  of "item/fileChange/requestApproval": sr_file_change_approval
  of "item/tool/requestUserInput": sr_tool_user_input
  of "item/tool/call": sr_tool_call
  of "account/chatgptAuthTokens/refresh": sr_auth_tokens_refresh
  of "applyPatchApproval": sr_apply_patch_approval
  of "execCommandApproval": sr_exec_command_approval
  of "mcpServer/elicitation/request": sr_mcp_server_elicitation
  of "item/permissions/requestApproval": sr_permission_request
  else: sr_unknown

proc server_request_method*(kind: ServerRequestKind): string =
  case kind:
  of sr_command_execution_approval: "item/commandExecution/requestApproval"
  of sr_file_change_approval: "item/fileChange/requestApproval"
  of sr_tool_user_input: "item/tool/requestUserInput"
  of sr_tool_call: "item/tool/call"
  of sr_auth_tokens_refresh: "account/chatgptAuthTokens/refresh"
  of sr_apply_patch_approval: "applyPatchApproval"
  of sr_exec_command_approval: "execCommandApproval"
  of sr_mcp_server_elicitation: "mcpServer/elicitation/request"
  of sr_permission_request: "item/permissions/requestApproval"
  of sr_unknown: ""

proc parse_request_id(node: JsonNode): RequestId =
  case node.kind:
  of JString: RequestId(kind: rid_string, string_value: node.getStr)
  of JInt: RequestId(kind: rid_integer, integer_value: node.getInt.int64)
  else: raise newException(ValueError, "JSON-RPC id must be string or integer")

proc parse_command_action(node: JsonNode): CommandAction =
  let kind = case node["type"].getStr:
    of "read": cak_read
    of "listFiles": cak_list_files
    of "search": cak_search
    else: cak_unknown
  CommandAction(
    kind: kind,
    command: node["command"].getStr,
    name: nullable_string(node, "name"),
    path: nullable_string(node, "path"),
    query: nullable_string(node, "query"),
    extra_fields: extra_fields(node, "type", "command", "name", "path", "query")
  )

proc parse_parsed_command(node: JsonNode): ParsedCommand =
  let kind = case node["type"].getStr:
    of "read": pck_read
    of "list_files": pck_list_files
    of "search": pck_search
    else: pck_unknown
  ParsedCommand(
    kind: kind,
    cmd: node["cmd"].getStr,
    name: nullable_string(node, "name"),
    path: nullable_string(node, "path"),
    query: nullable_string(node, "query"),
    extra_fields: extra_fields(node, "type", "cmd", "name", "path", "query")
  )

proc parse_command_execution_params(node: JsonNode): CommandExecutionRequestApprovalParams =
  var actions = NullableOption[seq[CommandAction]](state: nos_none)
  if node.contains("commandActions"):
    if node["commandActions"].kind == JNull:
      actions = NullableOption[seq[CommandAction]](state: nos_null)
    else:
      var values: seq[CommandAction] = @[]
      for item in node["commandActions"]:
        values.add(parse_command_action(item))
      actions = NullableOption[seq[CommandAction]](state: nos_value, value: values)
  var amendment = nullable_parsed(node, "proposedExecpolicyAmendment", parse_strings)
  CommandExecutionRequestApprovalParams(
    approval_id: nullable_string(node, "approvalId"),
    command: nullable_string(node, "command"),
    command_actions: actions,
    cwd: nullable_string(node, "cwd"),
    item_id: node["itemId"].getStr,
    proposed_execpolicy_amendment: amendment,
    reason: nullable_string(node, "reason"),
    thread_id: node["threadId"].getStr,
    turn_id: node["turnId"].getStr,
    extra_fields: extra_fields(node, "approvalId", "command", "commandActions", "cwd", "itemId", "proposedExecpolicyAmendment", "reason", "threadId", "turnId")
  )

proc parse_file_change_params(node: JsonNode): FileChangeRequestApprovalParams =
  FileChangeRequestApprovalParams(
    grant_root: nullable_string(node, "grantRoot"),
    item_id: node["itemId"].getStr,
    reason: nullable_string(node, "reason"),
    thread_id: node["threadId"].getStr,
    turn_id: node["turnId"].getStr,
    extra_fields: extra_fields(node, "grantRoot", "itemId", "reason", "threadId", "turnId")
  )

proc parse_tool_question(node: JsonNode): ToolRequestUserInputQuestion =
  var options = NullableOption[seq[ToolRequestUserInputOption]](state: nos_none)
  if node.contains("options"):
    if node["options"].kind == JNull:
      options = NullableOption[seq[ToolRequestUserInputOption]](state: nos_null)
    else:
      var values: seq[ToolRequestUserInputOption] = @[]
      for item in node["options"]:
        values.add(ToolRequestUserInputOption(
          description: item["description"].getStr,
          label: item["label"].getStr,
          extra_fields: extra_fields(item, "description", "label")
        ))
      options = NullableOption[seq[ToolRequestUserInputOption]](state: nos_value, value: values)
  ToolRequestUserInputQuestion(
    header: node["header"].getStr,
    id: node["id"].getStr,
    is_other: nullable_bool(node, "isOther"),
    is_secret: nullable_bool(node, "isSecret"),
    options: options,
    question: node["question"].getStr,
    extra_fields: extra_fields(node, "header", "id", "isOther", "isSecret", "options", "question")
  )

proc parse_tool_user_input_params(node: JsonNode): ToolRequestUserInputParams =
  var questions: seq[ToolRequestUserInputQuestion] = @[]
  for item in node["questions"]:
    questions.add(parse_tool_question(item))
  ToolRequestUserInputParams(
    item_id: node["itemId"].getStr,
    questions: questions,
    thread_id: node["threadId"].getStr,
    turn_id: node["turnId"].getStr,
    extra_fields: extra_fields(node, "itemId", "questions", "threadId", "turnId")
  )

proc parse_dynamic_tool_call_params(node: JsonNode): DynamicToolCallParams =
  DynamicToolCallParams(
    arguments: node["arguments"],
    call_id: node["callId"].getStr,
    thread_id: node["threadId"].getStr,
    tool: node["tool"].getStr,
    turn_id: node["turnId"].getStr,
    extra_fields: extra_fields(node, "arguments", "callId", "threadId", "tool", "turnId")
  )

proc parse_auth_refresh_params(node: JsonNode): ChatgptAuthTokensRefreshParams =
  let reason = case node["reason"].getStr:
    of "unauthorized": atrr_unauthorized
    else: atrr_unknown
  ChatgptAuthTokensRefreshParams(
    previous_account_id: nullable_string(node, "previousAccountId"),
    reason: reason,
    extra_fields: extra_fields(node, "previousAccountId", "reason")
  )

proc parse_file_change(node: JsonNode): FileChange =
  let kind = case node["type"].getStr:
    of "add": fck_add
    of "delete": fck_delete
    of "update": fck_update
    else: fck_unknown
  FileChange(
    kind: kind,
    content: nullable_string(node, "content"),
    move_path: nullable_string(node, "move_path"),
    unified_diff: nullable_string(node, "unified_diff"),
    extra_fields: extra_fields(node, "type", "content", "move_path", "unified_diff")
  )

proc parse_apply_patch_params(node: JsonNode): ApplyPatchApprovalParams =
  var changes = initTable[string, FileChange]()
  for path, value in node["fileChanges"].pairs:
    changes[path] = parse_file_change(value)
  ApplyPatchApprovalParams(
    call_id: node["callId"].getStr,
    conversation_id: node["conversationId"].getStr,
    file_changes: changes,
    grant_root: nullable_string(node, "grantRoot"),
    reason: nullable_string(node, "reason"),
    extra_fields: extra_fields(node, "callId", "conversationId", "fileChanges", "grantRoot", "reason")
  )

proc parse_exec_command_params(node: JsonNode): ExecCommandApprovalParams =
  var command: seq[string] = @[]
  for item in node["command"]:
    command.add(item.getStr)
  var parsed: seq[ParsedCommand] = @[]
  for item in node["parsedCmd"]:
    parsed.add(parse_parsed_command(item))
  ExecCommandApprovalParams(
    approval_id: nullable_string(node, "approvalId"),
    call_id: node["callId"].getStr,
    command: command,
    conversation_id: node["conversationId"].getStr,
    cwd: node["cwd"].getStr,
    parsed_cmd: parsed,
    reason: nullable_string(node, "reason"),
    extra_fields: extra_fields(node, "approvalId", "callId", "command", "conversationId", "cwd", "parsedCmd", "reason")
  )

proc parse_server_request_params(kind: ServerRequestKind; node: JsonNode): ServerRequestParams =
  case kind:
  of sr_command_execution_approval:
    ServerRequestParams(kind: kind, command_execution_approval: parse_command_execution_params(node))
  of sr_file_change_approval:
    ServerRequestParams(kind: kind, file_change_approval: parse_file_change_params(node))
  of sr_tool_user_input:
    ServerRequestParams(kind: kind, tool_user_input: parse_tool_user_input_params(node))
  of sr_tool_call:
    ServerRequestParams(kind: kind, tool_call: parse_dynamic_tool_call_params(node))
  of sr_auth_tokens_refresh:
    ServerRequestParams(kind: kind, auth_tokens_refresh: parse_auth_refresh_params(node))
  of sr_apply_patch_approval:
    ServerRequestParams(kind: kind, apply_patch_approval: parse_apply_patch_params(node))
  of sr_exec_command_approval:
    ServerRequestParams(kind: kind, exec_command_approval: parse_exec_command_params(node))
  of sr_mcp_server_elicitation, sr_permission_request:
    ServerRequestParams(kind: kind, raw: node)
  of sr_unknown:
    ServerRequestParams(kind: kind, unknown: node)

proc parse_thread_status(node: JsonNode; flags: var set[ActiveFlag]): ThreadStatusKind =
  flags = {}
  case node["type"].getStr:
  of "idle": tsk_idle
  of "active":
    if node.contains("activeFlags"):
      for flag in node["activeFlags"]:
        case flag.getStr:
        of "waitingOnApproval": flags.incl(af_waiting_on_approval)
        of "waitingOnUserInput": flags.incl(af_waiting_on_user_input)
        else: discard
    tsk_active
  of "systemError": tsk_system_error
  of "notLoaded": tsk_not_loaded
  else: tsk_unknown

proc parse_notification(node: JsonNode): Notification =
  let method_name = node["method"].getStr
  var params = NotificationParams(
    thread_id: Nullable[string](has_value: false),
    request_id: none(RequestId),
    turn_id: none(string),
    turn_status: none(TurnStatus),
    delta: none(string),
    thread_status: none(ThreadStatusKind),
    active_flags: {},
    error_message: none(string),
    thread_extra_fields: initTable[string, JsonNode](),
    turn_extra_fields: initTable[string, JsonNode](),
    extra_fields: initTable[string, JsonNode]()
  )
  let wire_params = if node.contains("params"): node["params"] else: newJObject()
  case method_name:
  of "initialized":
    result.kind = nk_initialized
  of "thread/started":
    result.kind = nk_thread_started
    params.thread_id = Nullable[string](has_value: true, value: wire_params["thread"]["id"].getStr)
    params.thread_extra_fields = extra_fields(wire_params["thread"], "id")
    params.extra_fields = extra_fields(wire_params, "thread")
  of "turn/started":
    result.kind = nk_turn_started
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turn"]["id"].getStr)
    params.turn_status = some(parse_turn_status(wire_params["turn"]["status"]))
    params.turn_extra_fields = extra_fields(wire_params["turn"], "id", "status")
    params.extra_fields = extra_fields(wire_params, "threadId", "turn")
  of "turn/completed":
    result.kind = nk_turn_completed
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turn"]["id"].getStr)
    params.turn_status = some(parse_turn_status(wire_params["turn"]["status"]))
    if wire_params["turn"].contains("error") and wire_params["turn"]["error"].kind != JNull:
      params.error_message = some(wire_params["turn"]["error"]["message"].getStr)
    params.turn_extra_fields = extra_fields(wire_params["turn"], "id", "status", "error")
    params.extra_fields = extra_fields(wire_params, "threadId", "turn")
  of "item/agentMessage/delta":
    result.kind = nk_agent_message_delta
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.turn_id = some(wire_params["turnId"].getStr)
    params.delta = some(wire_params["delta"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "turnId", "itemId", "delta")
  of "thread/status/changed":
    result.kind = nk_thread_status_changed
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    var flags: set[ActiveFlag]
    params.thread_status = some(parse_thread_status(wire_params["status"], flags))
    params.active_flags = flags
    params.extra_fields = extra_fields(wire_params, "threadId", "status")
  of "thread/closed":
    result.kind = nk_thread_closed
    params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId")
  of "serverRequest/resolved":
    result.kind = nk_server_request_resolved
    if wire_params.contains("threadId"):
      params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    if wire_params.contains("requestId"):
      params.request_id = some(parse_request_id(wire_params["requestId"]))
    params.extra_fields = extra_fields(wire_params, "threadId", "requestId")
  of "error":
    result.kind = nk_error
    if wire_params.contains("threadId"):
      params.thread_id = Nullable[string](has_value: true, value: wire_params["threadId"].getStr)
    if wire_params.contains("error"):
      params.error_message = some(wire_params["error"]["message"].getStr)
    params.extra_fields = extra_fields(wire_params, "threadId", "error")
  else:
    result.kind = nk_unknown
    params.extra_fields = json_object(wire_params)
  result.method_name = method_name
  result.params = params
  result.extra_fields = extra_fields(node, "method", "params")

proc parse_server_request(node: JsonNode): ServerRequest =
  let method_name = node["method"].getStr
  let kind = server_request_kind(method_name)
  let wire_params = if node.contains("params"): node["params"] else: newJObject()
  ServerRequest(
    id: parse_request_id(node["id"]),
    kind: kind,
    method_name: method_name,
    params: parse_server_request_params(kind, wire_params),
    extra_fields: extra_fields(node, "id", "method", "params")
  )

proc parse_message*(node: JsonNode; pending: var seq[Message]): Message =
  if node.contains("id"):
    if node.contains("method"):
      return Message(kind: mk_server_request, server_request: parse_server_request(node))

    if not node.contains("result") and not node.contains("error"):
      raise newException(ValueError, "JSON-RPC message with id has neither method, result, nor error")

    let id = parse_request_id(node["id"])
    var request_kind = mk_initialize
    var found = false
    for i in 0 ..< pending.len:
      if pending[i].kind == mk_request and pending[i].request.id == id:
        request_kind = pending[i].request.kind
        pending.del(i)
        found = true
        break
    if not found:
      ## A late or duplicate response is transport noise, not a reason to
      ## tear down the coordinator. RuntimeState records the quarantine.
      return Message(
        kind: mk_notification,
        notification: Notification(
          kind: nk_unknown,
          method_name: "orphan response " & request_id_key(id),
          params: NotificationParams(
            thread_id: Nullable[string](has_value: false),
            request_id: none(RequestId),
            turn_id: none(string),
            turn_status: none(TurnStatus),
            thread_status: none(ThreadStatusKind),
            active_flags: {},
            error_message: none(string))))

    if node.contains("result"):
      let raw_result = node["result"]
      case request_kind:
      of mk_initialize:
        result = Message(
          kind: mk_success,
          success: Success(
            id: id,
            result: ResponseResult(kind: mk_initialize),
            raw_result: raw_result,
            extra_fields: extra_fields(node, "id", "result")
          )
        )
      of mk_thread_start:
        result = Message(
          kind: mk_success,
          success: Success(
            id: id,
            result: ResponseResult(
              kind: mk_thread_start,
              thread_id: raw_result["thread"]["id"].getStr,
              thread_extra_fields: extra_fields(raw_result["thread"], "id")
            ),
            raw_result: raw_result,
            extra_fields: extra_fields(node, "id", "result")
          )
        )
      of mk_turn_start:
        result = Message(
          kind: mk_success,
          success: Success(
            id: id,
            result: ResponseResult(
              kind: mk_turn_start,
              turn_id: raw_result["turn"]["id"].getStr,
              turn_status: parse_turn_status(raw_result["turn"]["status"]),
              turn_extra_fields: extra_fields(raw_result["turn"], "id", "status")
            ),
            raw_result: raw_result,
            extra_fields: extra_fields(node, "id", "result")
          )
        )
      of mk_thread_goal_set:
        result = Message(
          kind: mk_success,
          success: Success(
            id: id,
            result: ResponseResult(kind: mk_thread_goal_set),
            raw_result: raw_result,
            extra_fields: extra_fields(node, "id", "result")
          )
        )
      of mk_thread_stop:
        result = Message(
          kind: mk_success,
          success: Success(
            id: id,
            result: ResponseResult(kind: mk_thread_stop),
            raw_result: raw_result,
            extra_fields: extra_fields(node, "id", "result")
          )
        )
    else:
      result = Message(
        kind: mk_error,
        error: Error(
          id: id,
          code: node["error"]["code"].getInt.int64,
          message: node["error"]["message"].getStr,
          extra_fields: extra_fields(node["error"], "code", "message")
        )
      )
  elif node.contains("method"):
    result = Message(kind: mk_notification, notification: parse_notification(node))
  else:
    raise newException(ValueError, "JSON-RPC message has neither id nor method")
