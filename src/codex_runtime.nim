import std/[osproc, streams, json, options, tables, os]
import ./codex_json

type
  AgentId* = string

  AgentState* = enum
    as_starting,
    as_idle,
    as_working,
    as_waiting,
    as_closed,
    as_error

  RequestState* = enum
    rs_pending,
    rs_accepted,
    rs_completed,
    rs_failed,
    rs_interrupted

  Agent* = object
    id*: AgentId
    thread_id*: Nullable[string]
    turn_id*: Option[string]
    default_effort*: ReasoningEffort
    state*: AgentState
    last_error*: NullableOption[string]
    tools*: DynamicToolRegistry

  OutgoingRequest* = object
    id*: RequestId
    agent_id*: Option[AgentId]
    request*: Request
    state*: RequestState
    turn_id*: Option[string]
    result*: Option[JsonNode]
    error*: Option[string]

  RuntimeState* = object
    agents*: Table[AgentId, Agent]
    requests*: Table[string, OutgoingRequest]
    server_requests*: Table[string, ServerRequest]

  CodexRuntime* {.requiresInit.} = object
    process: Process
    handles_closed: bool
    pending: seq[Message]
    next_request_id: int64
    cwd*: string
    initialized*: bool
    initialization_error*: Option[string]
    state*: RuntimeState

template agents*(runtime: ptr CodexRuntime): untyped = runtime.state.agents
template requests*(runtime: ptr CodexRuntime): untyped = runtime.state.requests
template server_requests*(runtime: ptr CodexRuntime): untyped = runtime.state.server_requests

proc new_runtime_state*(): RuntimeState =
  result.agents = initTable[AgentId, Agent]()
  result.requests = initTable[string, OutgoingRequest]()
  result.server_requests = initTable[string, ServerRequest]()

proc find_agent_for_thread(state: var RuntimeState; thread_id: string): Option[AgentId] =
  for agent_id, agent in state.agents.pairs:
    if agent.thread_id.has_value and agent.thread_id.value == thread_id:
      return some(agent_id)
  none(AgentId)

proc find_dynamic_tool(agent: Agent; name: string): Option[DynamicTool] =
  for tool in agent.tools:
    if tool.name == name:
      return some(tool)
  none(DynamicTool)

proc nullable_string(value: string): Nullable[string] =
  Nullable[string](has_value: true, value: value)

proc set_agent_error(agent: var Agent; message: string) =
  agent.state = as_error
  agent.last_error = NullableOption[string](state: nos_value, value: message)

proc clear_agent_error(agent: var Agent) =
  agent.last_error = NullableOption[string](state: nos_null)

proc apply_success*(state: var RuntimeState; success: Success) =
  let key = request_id_key(success.id)
  if not state.requests.hasKey(key):
    return

  var outgoing = state.requests[key]
  outgoing.result = some(success.raw_result)
  outgoing.state = rs_completed

  case outgoing.request.kind:
  of mk_initialize:
    discard
  of mk_thread_start:
    if outgoing.agent_id.isSome:
      let agent_id = outgoing.agent_id.get
      if state.agents.hasKey(agent_id):
        var agent = state.agents[agent_id]
        agent.thread_id = nullable_string(success.result.thread_id)
        agent.state = as_idle
        clear_agent_error(agent)
        state.agents[agent_id] = agent
  of mk_turn_start:
    outgoing.state = rs_accepted
    outgoing.turn_id = some(success.result.turn_id)
    if outgoing.agent_id.isSome:
      let agent_id = outgoing.agent_id.get
      if state.agents.hasKey(agent_id):
        var agent = state.agents[agent_id]
        agent.turn_id = some(success.result.turn_id)
        agent.state = as_working
        clear_agent_error(agent)
        state.agents[agent_id] = agent
  of mk_thread_goal_set:
    discard
  of mk_thread_stop:
    discard

  state.requests[key] = outgoing

proc apply_error*(state: var RuntimeState; error: Error) =
  let key = request_id_key(error.id)
  if not state.requests.hasKey(key):
    return

  var outgoing = state.requests[key]
  outgoing.state = rs_failed
  outgoing.error = some(error.message)
  if outgoing.agent_id.isSome:
    let agent_id = outgoing.agent_id.get
    if state.agents.hasKey(agent_id):
      var agent = state.agents[agent_id]
      set_agent_error(agent, error.message)
      state.agents[agent_id] = agent
  state.requests[key] = outgoing

proc request_for_turn(state: var RuntimeState; turn_id: string): Option[string] =
  for request_key, outgoing in state.requests.pairs:
    if outgoing.turn_id.isSome and outgoing.turn_id.get == turn_id:
      return some(request_key)
  none(string)

proc server_request_thread_id(request: ServerRequest): Option[string] =
  case request.params.kind:
  of sr_command_execution_approval:
    some(request.params.command_execution_approval.thread_id)
  of sr_file_change_approval:
    some(request.params.file_change_approval.thread_id)
  of sr_tool_user_input:
    some(request.params.tool_user_input.thread_id)
  of sr_tool_call:
    some(request.params.tool_call.thread_id)
  of sr_auth_tokens_refresh:
    none(string)
  of sr_apply_patch_approval:
    some(request.params.apply_patch_approval.conversation_id)
  of sr_exec_command_approval:
    some(request.params.exec_command_approval.conversation_id)
  of sr_mcp_server_elicitation, sr_permission_request:
    if request.params.raw.kind != JObject:
      return none(string)
    if request.params.raw.contains("threadId"):
      return some(request.params.raw["threadId"].getStr)
    none(string)
  of sr_unknown:
    if request.params.unknown.kind != JObject:
      return none(string)
    if request.params.unknown.contains("threadId"):
      return some(request.params.unknown["threadId"].getStr)
    if request.params.unknown.contains("conversationId"):
      return some(request.params.unknown["conversationId"].getStr)
    none(string)

proc apply_server_request*(state: var RuntimeState; request: ServerRequest) =
  let key = request_id_key(request.id)
  state.server_requests[key] = request

  let thread_id = server_request_thread_id(request)
  if thread_id.isNone:
    return
  let agent_id = find_agent_for_thread(state, thread_id.get)
  if agent_id.isNone:
    return
  var agent = state.agents[agent_id.get]
  if agent.state != as_closed and agent.state != as_error:
    agent.state = as_waiting
    state.agents[agent_id.get] = agent

proc remove_server_request*(state: var RuntimeState; id: RequestId): Option[ServerRequest] =
  let key = request_id_key(id)
  if not state.server_requests.hasKey(key):
    return none(ServerRequest)
  let request = state.server_requests[key]
  state.server_requests.del(key)

  let thread_id = server_request_thread_id(request)
  if thread_id.isSome:
    let agent_id = find_agent_for_thread(state, thread_id.get)
    if agent_id.isSome:
      var still_waiting = false
      for pending in state.server_requests.values:
        let pending_thread_id = server_request_thread_id(pending)
        if pending_thread_id.isSome and pending_thread_id.get == thread_id.get:
          still_waiting = true
          break
      if not still_waiting:
        var agent = state.agents[agent_id.get]
        if agent.state == as_waiting:
          agent.state = as_working
          state.agents[agent_id.get] = agent
  some(request)

proc apply_notification*(state: var RuntimeState; notification: Notification) =
  let params = notification.params
  if notification.kind == nk_server_request_resolved:
    if params.request_id.isSome:
      discard remove_server_request(state, params.request_id.get)
    return
  if not params.thread_id.has_value:
    return
  let thread_id = params.thread_id.value
  let agent_id = find_agent_for_thread(state, thread_id)
  if agent_id.isNone:
    return
  let id = agent_id.get
  var agent = state.agents[id]

  case notification.kind:
  of nk_thread_started:
    if agent.state == as_starting:
      agent.state = as_idle
  of nk_turn_started:
    if params.turn_id.isSome:
      agent.turn_id = params.turn_id
    agent.state = as_working
  of nk_turn_completed:
    if params.turn_id.isSome:
      agent.turn_id = none(string)
      let request_key = request_for_turn(state, params.turn_id.get)
      if request_key.isSome:
        var outgoing = state.requests[request_key.get]
        if params.turn_status.isSome and params.turn_status.get == ts_failed:
          outgoing.state = rs_failed
          if params.error_message.isSome:
            outgoing.error = params.error_message
        elif params.turn_status.isSome and params.turn_status.get == ts_interrupted:
          outgoing.state = rs_interrupted
        else:
          outgoing.state = rs_completed
        state.requests[request_key.get] = outgoing
    if params.turn_status.isSome and params.turn_status.get == ts_failed:
      if params.error_message.isSome:
        set_agent_error(agent, params.error_message.get)
      else:
        set_agent_error(agent, "turn failed")
    else:
      agent.state = as_idle
  of nk_agent_message_delta:
    discard
  of nk_thread_status_changed:
    if params.thread_status.isSome:
      case params.thread_status.get:
      of tsk_idle:
        agent.state = as_idle
      of tsk_active:
        if af_waiting_on_approval in params.active_flags or
            af_waiting_on_user_input in params.active_flags:
          agent.state = as_waiting
        else:
          agent.state = as_working
      of tsk_system_error:
        set_agent_error(agent, "system error")
      of tsk_not_loaded:
        agent.state = as_closed
      of tsk_unknown:
        discard
  of nk_thread_closed:
    agent.state = as_closed
    agent.turn_id = none(string)
  of nk_error:
    if params.error_message.isSome:
      set_agent_error(agent, params.error_message.get)
  of nk_initialized, nk_server_request_resolved, nk_unknown:
    discard

  state.agents[id] = agent

proc send(stream: Stream; message: JsonNode) =
  stream.writeLine($message)
  stream.flush()

proc send_server_response(runtime: ptr CodexRuntime; response: ServerResponse) =
  send(runtime.process.inputStream, serialize_message(Message(
    kind: mk_server_response,
    server_response: response
  )))

proc send_initialized(runtime: ptr CodexRuntime) =
  send(runtime.process.inputStream, serialize_message(Message(
    kind: mk_notification,
    notification: Notification(
      kind: nk_initialized,
      params: NotificationParams(
        thread_id: Nullable[string](has_value: false),
        turn_id: none(string),
        turn_status: none(TurnStatus),
        thread_status: none(ThreadStatusKind),
        active_flags: {},
        error_message: none(string)
      )
    )
  )))

proc send_pending_requests(runtime: ptr CodexRuntime) =
  for message in runtime.pending:
    send(runtime.process.inputStream, serialize_message(message))

proc queue_request(runtime: ptr CodexRuntime; request_kind: RequestKind;
    params: Params; agent_id: Option[AgentId]): RequestId =
  let id = RequestId(kind: rid_integer, integer_value: runtime.next_request_id)
  inc runtime.next_request_id
  let request = Request(kind: request_kind, id: id, params: params)
  runtime.pending.add(Message(kind: mk_request, request: request))
  runtime.state.requests[request_id_key(id)] = OutgoingRequest(
    id: id,
    agent_id: agent_id,
    request: request,
    state: rs_pending,
    turn_id: none(string),
    result: none(JsonNode),
    error: none(string)
  )
  if request_kind == mk_initialize or runtime.initialized:
    send(runtime.process.inputStream, serialize_message(Message(
      kind: mk_request,
      request: request
    )))
  id

proc apply_dynamic_tool_call*(state: var RuntimeState; request: ServerRequest) =
  let params = request.params.tool_call
  let agent_id = find_agent_for_thread(state, params.thread_id)
  if agent_id.isNone:
    raise newException(ValueError, "no agent for dynamic tool thread: " & params.thread_id)

  let agent = state.agents[agent_id.get]
  let tool = agent.find_dynamic_tool(params.tool)
  if tool.isNone:
    raise newException(ValueError, "unknown dynamic tool: " & params.tool)
  if tool.get.callback.isNil:
    raise newException(ValueError, "dynamic tool has no callback: " & params.tool)

  tool.get.callback(tool.get.data, ToolCallContext(
    request_id: request.id,
    params: params
  ))

proc handle_message*(runtime: ptr CodexRuntime; message: Message) =
  case message.kind:
  of mk_request:
    discard
  of mk_server_request:
    apply_server_request(runtime.state, message.server_request)
    case message.server_request.kind:
    of sr_tool_call:
      apply_dynamic_tool_call(runtime.state, message.server_request)
    of sr_unknown:
      send_server_response(runtime, ServerResponse(
        id: message.server_request.id,
        result: none(JsonNode),
        error: some(Error(
          id: message.server_request.id,
          code: -32601,
          message: "method not found"
        ))
      ))
      discard remove_server_request(runtime.state, message.server_request.id)
    else:
      discard
  of mk_server_response:
    let key = request_id_key(message.server_response.id)
    if not runtime.state.server_requests.hasKey(key):
      raise newException(ValueError, "unknown server request: " & key)
    send_server_response(runtime, message.server_response)
    discard remove_server_request(runtime.state, message.server_response.id)
  of mk_success:
    apply_success(runtime.state, message.success)
    if message.success.result.kind == mk_initialize:
      runtime.initialized = true
      runtime.initialization_error = none(string)
      send_initialized(runtime)
      send_pending_requests(runtime)
  of mk_error:
    apply_error(runtime.state, message.error)
    if runtime.state.requests.hasKey(request_id_key(message.error.id)):
      let request = runtime.state.requests[request_id_key(message.error.id)]
      if request.request.kind == mk_initialize:
        runtime.initialization_error = some(message.error.message)
  of mk_notification:
    apply_notification(runtime.state, message.notification)

proc accept_json*(runtime: ptr CodexRuntime; node: JsonNode): Message =
  result = parse_message(node, runtime.pending)
  handle_message(runtime, result)

proc accept_tool_response*(runtime: ptr CodexRuntime; request_id: RequestId;
    success: bool; content_items: seq[DynamicToolContentItem])

proc accept_tool_response*(runtime: ptr CodexRuntime; context: ToolCallContext;
    success: bool; content_items: seq[DynamicToolContentItem]) =
  accept_tool_response(runtime, context.request_id, success, content_items)

proc accept_tool_response*(runtime: ptr CodexRuntime; request_id: RequestId;
    success: bool; content_items: seq[DynamicToolContentItem]) =
  handle_message(runtime, Message(
    kind: mk_server_response,
    server_response: ServerResponse(
      id: request_id,
      result: some(serialize_dynamic_tool_call_response(DynamicToolCallResponse(
        success: success,
        content_items: content_items
      ))),
      error: none(Error)
    )
  ))

proc reply_server_request*(runtime: ptr CodexRuntime; id: RequestId;
    result: JsonNode) =
  handle_message(runtime, Message(
    kind: mk_server_response,
    server_response: ServerResponse(
      id: id,
      result: some(result),
      error: none(Error)
    )
  ))

proc fail_server_request*(runtime: ptr CodexRuntime; id: RequestId;
    code: int64; message: string) =
  handle_message(runtime, Message(
    kind: mk_server_response,
    server_response: ServerResponse(
      id: id,
      result: none(JsonNode),
      error: some(Error(id: id, code: code, message: message))
    )
  ))

proc is_running*(runtime: ptr CodexRuntime): bool =
  runtime.process.running

proc server_stdout_stream*(runtime: ptr CodexRuntime): Stream =
  runtime.process.output_stream

proc server_stderr_stream*(runtime: ptr CodexRuntime): Stream =
  runtime.process.error_stream

proc stop_codex_threads(codex: ptr CodexRuntime) =
  if not codex.process.running:
    return
  for agent in codex.state.agents.values:
    if agent.state == as_closed or not agent.thread_id.has_value:
      continue
    discard queue_request(
      codex,
      mk_thread_stop,
      Params(
        kind: mk_thread_stop,
        thread_stop: ThreadStopParams(thread_id: agent.thread_id.value)
      ),
      some(agent.id)
    )

proc stop_codex_runtime*(codex: ptr CodexRuntime) =
  if codex.process.running:
    codex.process.kill()
  discard codex.process.waitForExit(3_000)

proc deinit_codex_runtime*(codex: ptr CodexRuntime) =
  stop_codex_threads(codex)
  stop_codex_runtime(codex)
  codex.process.close()
  codex.pending.setLen(0)
  codex.state.agents.clear()
  codex.state.requests.clear()
  codex.state.server_requests.clear()
  reset(codex.process)
  reset(codex.pending)
  reset(codex.cwd)
  reset(codex.initialization_error)
  reset(codex.state.agents)
  reset(codex.state.requests)
  reset(codex.state.server_requests)
  deallocShared(codex)

proc init_codex_runtime*(cwd: string): ptr CodexRuntime =
  if not dirExists(cwd):
    raise newException(ValueError, "cwd is not a directory: " & cwd)
  let canonical_cwd = expandFilename(cwd)

  result = cast[ptr CodexRuntime](allocShared0(sizeof(CodexRuntime)))
  result.state = new_runtime_state()
  result.handles_closed = false
  result.pending = @[]
  result.next_request_id = 0
  result.cwd = canonical_cwd
  result.initialized = false
  result.initialization_error = none(string)

  result.process = startProcess(
    command = "codex",
    workingDir = result.cwd,
    args = ["app-server"],
    options = {poUsePath}
  )

  discard queue_request(
    result,
    mk_initialize,
    Params(
      kind: mk_initialize,
      initialize: InitializeParams(
        capabilities: NullableOption[InitializeCapabilities](
          state: nos_value,
          value: InitializeCapabilities(
            experimental_api: NullableOption[bool](state: nos_value, value: true),
            opt_out_notification_methods: NullableOption[seq[string]](state: nos_none)
          )
        ),
        client_info: ClientInfo(
          name: "graph-orchestration",
          title: NullableOption[string](state: nos_value, value: "Graph Orchestration"),
          version: "0.1.0"
        )
      )
    ),
    none(AgentId)
  )

proc output_handle*(runtime: ptr CodexRuntime): cint = runtime.process.outputHandle()
proc error_handle*(runtime: ptr CodexRuntime): cint = runtime.process.errorHandle()

proc create_agent*(runtime: ptr CodexRuntime; agent_id: AgentId;
    model: string; tools: DynamicToolRegistry = @[];
    developer_instructions: string = "";
    default_effort: ReasoningEffort = re_low): RequestId =
  if runtime.state.agents.hasKey(agent_id):
    raise newException(ValueError, "agent already exists: " & agent_id)

  var copied_tools = newSeq[DynamicTool](tools.len)
  for index, tool in tools:
    copied_tools[index] = tool

  runtime.state.agents[agent_id] = Agent(
    id: agent_id,
    thread_id: Nullable[string](has_value: false),
    turn_id: none(string),
    default_effort: default_effort,
    state: as_starting,
    last_error: NullableOption[string](state: nos_none),
    tools: copied_tools
  )

  var thread_params = ThreadStartParams(
    approval_policy: NullableOption[AskForApproval](
      state: nos_value,
      value: apa_never
    ),
    base_instructions: NullableOption[string](state: nos_none),
    config: NullableOption[Config](state: nos_none),
    cwd: NullableOption[string](state: nos_value, value: runtime.cwd),
    developer_instructions: NullableOption[string](state: nos_none),
    sandbox: NullableOption[SandboxMode](
      state: nos_value,
      value: sm_danger_full_access
    ),
    ephemeral: NullableOption[bool](state: nos_none),
    model_provider: NullableOption[string](state: nos_none),
    personality: NullableOption[Personality](state: nos_none),
    model: NullableOption[string](state: nos_none),
    dynamic_tools: NullableOption[seq[DynamicToolSpec]](state: nos_none)
  )
  if model.len > 0:
    thread_params.model = NullableOption[string](state: nos_value, value: model)
  if developer_instructions.len > 0:
    thread_params.developer_instructions = NullableOption[string](
      state: nos_value,
      value: developer_instructions
    )
  if copied_tools.len > 0:
    var specs = newSeq[DynamicToolSpec](copied_tools.len)
    for index, tool in copied_tools:
      specs[index] = DynamicToolSpec(
        name: tool.name,
        description: tool.description,
        input_schema: tool.input_schema
      )
    thread_params.dynamic_tools = NullableOption[seq[DynamicToolSpec]](
      state: nos_value,
      value: specs
    )

  queue_request(
    runtime,
    mk_thread_start,
    Params(kind: mk_thread_start, thread_start: thread_params),
    some(agent_id)
  )

proc send_agent_message*(runtime: ptr CodexRuntime; agent_id: AgentId;
    text: string; effort: ReasoningEffort): RequestId =
  if not runtime.state.agents.hasKey(agent_id):
    raise newException(ValueError, "unknown agent: " & agent_id)
  let agent = runtime.state.agents[agent_id]
  if not agent.thread_id.has_value:
    raise newException(ValueError, "agent has not started: " & agent_id)
  if agent.state == as_closed:
    raise newException(ValueError, "agent is closed: " & agent_id)

  var current = agent
  current.state = as_working
  runtime.state.agents[agent_id] = current

  let params = TurnStartParams(
    thread_id: agent.thread_id.value,
    text: text,
    effort: NullableOption[ReasoningEffort](state: nos_value, value: effort)
  )
  queue_request(
    runtime,
    mk_turn_start,
    Params(kind: mk_turn_start, turn_start: params),
    some(agent_id)
  )

proc send_agent_message*(runtime: ptr CodexRuntime; agent_id: AgentId;
    text: string): RequestId =
  if not runtime.state.agents.hasKey(agent_id):
    raise newException(ValueError, "unknown agent: " & agent_id)

  send_agent_message(
    runtime,
    agent_id,
    text,
    runtime.state.agents[agent_id].default_effort
  )

proc set_agent_goal*(runtime: ptr CodexRuntime; agent_id: AgentId;
    objective: string): RequestId =
  if not runtime.state.agents.hasKey(agent_id):
    raise newException(ValueError, "unknown agent: " & agent_id)
  let agent = runtime.state.agents[agent_id]
  if not agent.thread_id.has_value:
    raise newException(ValueError, "agent has not started: " & agent_id)
  if agent.state == as_closed:
    raise newException(ValueError, "agent is closed: " & agent_id)

  let params = ThreadGoalSetParams(
    thread_id: agent.thread_id.value,
    objective: objective
  )
  queue_request(
    runtime,
    mk_thread_goal_set,
    Params(kind: mk_thread_goal_set, thread_goal_set: params),
    some(agent_id)
  )
