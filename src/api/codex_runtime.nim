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

  CodexRuntimeLiveness* = ref object
    alive*: bool

  Agent* = object
    id*: AgentId
    thread_id*: Nullable[string]
    turn_id*: Option[string]
    ## JSON-RPC request key owning the agent's active turn, if any.
    active_turn_request*: Option[string]
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
    ## Event turn IDs are not guaranteed to equal the ID in turn/start's
    ## response. Keep explicit aliases to the owning request.
    turn_request_keys*: Table[string, string]
    ## Terminal aliases remain recognizable without remaining active owners.
    turn_tombstones*: Table[string, string]
    server_requests*: Table[string, ServerRequest]
    server_request_tombstones*: Table[string, bool]
    quarantined_event_count*: int
    last_quarantined_event*: Option[string]

  CodexRuntime* {.requiresInit.} = object
    process: Process
    liveness*: CodexRuntimeLiveness
    handles_closed: bool
    pending: seq[Message]
    next_request_id: int64
    next_agent_id: int64
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
  result.turn_request_keys = initTable[string, string]()
  result.turn_tombstones = initTable[string, string]()
  result.server_requests = initTable[string, ServerRequest]()
  result.server_request_tombstones = initTable[string, bool]()
  result.last_quarantined_event = none(string)

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

proc quarantine(state: var RuntimeState; event: string) =
  ## Unknown protocol input must not corrupt active state or crash the
  ## coordinator. Keep a counter and latest reason for diagnostics.
  inc state.quarantined_event_count
  state.last_quarantined_event = some(event)

proc bind_turn_request(
    state: var RuntimeState;
    request_key, turn_id: string
) : bool =
  ## Every observed turn ID becomes an alias for one accepted request. This
  ## preserves correlation when turn/start and turn/started expose different
  ## identifiers while rejecting cross-request collisions.
  if turn_id.len == 0:
    state.quarantine("empty turn ID for " & request_key)
    return false
  if state.turn_tombstones.hasKey(turn_id):
    state.quarantine("late turn alias: " & turn_id)
    return false
  if state.turn_request_keys.hasKey(turn_id) and
      state.turn_request_keys[turn_id] != request_key:
    state.quarantine("turn alias collision: " & turn_id)
    return false
  var aliases = 0
  for owner in state.turn_request_keys.values:
    if owner == request_key:
      inc aliases
  if aliases >= 4:
    state.quarantine("too many turn aliases: " & request_key)
    return false
  state.turn_request_keys[turn_id] = request_key
  if state.requests.hasKey(request_key):
    var outgoing = state.requests[request_key]
    outgoing.turn_id = some(turn_id)
    state.requests[request_key] = outgoing
  true

proc unbind_turn_request(state: var RuntimeState; request_key: string) =
  var removed: seq[string] = @[]
  for turn_id, owner in state.turn_request_keys.pairs:
    if owner == request_key:
      removed.add(turn_id)
  for turn_id in removed:
    state.turn_request_keys.del(turn_id)
    state.turn_tombstones[turn_id] = request_key

proc request_for_turn(state: var RuntimeState; turn_id: string): Option[string] =
  if not state.turn_request_keys.hasKey(turn_id):
    return none(string)
  let request_key = state.turn_request_keys[turn_id]
  if not state.requests.hasKey(request_key):
    return none(string)
  some(request_key)

proc active_turn_request_for_agent(
    state: var RuntimeState;
    agent_id: AgentId
): Option[string] =
  if not state.agents.hasKey(agent_id):
    return none(string)
  let request_key = state.agents[agent_id].active_turn_request
  if request_key.isSome and state.requests.hasKey(request_key.get):
    let request = state.requests[request_key.get]
    if request.request.kind == mk_turn_start and
        request.state in {rs_pending, rs_accepted}:
      return request_key
  none(string)

proc terminalize_turn(
    state: var RuntimeState;
    request_key: string;
    status: RequestState;
    error: Option[string]
): bool =
  if not state.requests.hasKey(request_key):
    return false
  var request = state.requests[request_key]
  if request.request.kind != mk_turn_start or
      request.state notin {rs_pending, rs_accepted}:
    return false
  request.state = status
  request.error = error
  state.requests[request_key] = request
  unbind_turn_request(state, request_key)
  if request.agent_id.isSome and state.agents.hasKey(request.agent_id.get):
    var agent = state.agents[request.agent_id.get]
    if agent.active_turn_request.isSome and
        agent.active_turn_request.get == request_key:
      agent.active_turn_request = none(string)
      agent.turn_id = none(string)
    if status == rs_failed:
      set_agent_error(agent, if error.isSome: error.get else: "turn failed")
    elif status == rs_interrupted:
      set_agent_error(agent, if error.isSome: error.get else: "turn interrupted")
    else:
      agent.state = as_idle
      clear_agent_error(agent)
    state.agents[request.agent_id.get] = agent
  true

proc turn_completion_state(params: NotificationParams): tuple[state: RequestState,
    error: Option[string]] =
  if params.turn_status.isSome and params.turn_status.get == ts_failed:
    return (rs_failed, if params.error_message.isSome:
      params.error_message else: some("turn failed"))
  if params.turn_status.isSome and params.turn_status.get == ts_interrupted:
    return (rs_interrupted, params.error_message)
  (rs_completed, none(string))

proc apply_success*(state: var RuntimeState; success: Success) =
  let key = request_id_key(success.id)
  if not state.requests.hasKey(key):
    return

  var outgoing = state.requests[key]
  if outgoing.state in {rs_completed, rs_failed, rs_interrupted}:
    state.quarantine("late success: " & key)
    return
  outgoing.result = some(success.raw_result)
  outgoing.state = rs_completed

  case outgoing.request.kind:
  of mk_initialize:
    discard
  of mk_thread_start:
    if outgoing.agent_id.isSome:
      let agent_id = outgoing.agent_id.get
      if state.agents.hasKey(agent_id):
        let existing = find_agent_for_thread(state, success.result.thread_id)
        if existing.isSome and existing.get != agent_id:
          state.quarantine("thread ID collision: " & success.result.thread_id)
          outgoing.state = rs_failed
          outgoing.error = some("thread ID already belongs to another agent")
          state.requests[key] = outgoing
          var agent = state.agents[agent_id]
          set_agent_error(agent, outgoing.error.get)
          state.agents[agent_id] = agent
          return
        var agent = state.agents[agent_id]
        agent.thread_id = nullable_string(success.result.thread_id)
        agent.state = as_idle
        clear_agent_error(agent)
        state.agents[agent_id] = agent
  of mk_turn_start:
    outgoing.state = rs_accepted
    state.requests[key] = outgoing
    if not bind_turn_request(state, key, success.result.turn_id):
      discard terminalize_turn(
        state,
        key,
        rs_failed,
        some("turn ID could not be bound"))
      return
    outgoing = state.requests[key]
    if outgoing.agent_id.isSome:
      let agent_id = outgoing.agent_id.get
      if state.agents.hasKey(agent_id):
        var agent = state.agents[agent_id]
        agent.turn_id = some(success.result.turn_id)
        agent.active_turn_request = some(key)
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
  if outgoing.state in {rs_completed, rs_failed, rs_interrupted}:
    state.quarantine("late error: " & key)
    return
  state.requests[key] = outgoing
  if outgoing.request.kind == mk_turn_start:
    discard terminalize_turn(state, key, rs_failed, some(error.message))
  else:
    outgoing.state = rs_failed
    outgoing.error = some(error.message)
    state.requests[key] = outgoing
    if outgoing.agent_id.isSome and state.agents.hasKey(outgoing.agent_id.get):
      var agent = state.agents[outgoing.agent_id.get]
      set_agent_error(agent, error.message)
      state.agents[outgoing.agent_id.get] = agent

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

proc has_pending_server_request_for_agent*(state: var RuntimeState;
    agent_id: AgentId): bool =
  if not state.agents.hasKey(agent_id) or
      not state.agents[agent_id].thread_id.has_value:
    return false
  let thread_id = state.agents[agent_id].thread_id.value
  for request in state.server_requests.values:
    let request_thread = server_request_thread_id(request)
    if request_thread.isSome and request_thread.get == thread_id:
      return true
  false

proc apply_server_request*(state: var RuntimeState; request: ServerRequest): bool =
  let key = request_id_key(request.id)
  if state.server_requests.hasKey(key) or
      state.server_request_tombstones.hasKey(key):
    state.quarantine("duplicate server request: " & key)
    return false
  state.server_requests[key] = request

  let thread_id = server_request_thread_id(request)
  if thread_id.isNone:
    return true
  let agent_id = find_agent_for_thread(state, thread_id.get)
  if agent_id.isNone:
    return true
  var agent = state.agents[agent_id.get]
  if agent.state != as_closed and agent.state != as_error:
    agent.state = as_waiting
    state.agents[agent_id.get] = agent
  true

proc remove_server_request*(state: var RuntimeState; id: RequestId): Option[ServerRequest] =
  let key = request_id_key(id)
  if not state.server_requests.hasKey(key):
    return none(ServerRequest)
  let request = state.server_requests[key]
  state.server_requests.del(key)
  state.server_request_tombstones[key] = true

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
    if notification.kind in {nk_turn_started, nk_turn_completed, nk_unknown}:
      state.quarantine("turn event without thread ID: " & notification.method_name)
    return
  let thread_id = params.thread_id.value
  let agent_id = find_agent_for_thread(state, thread_id)
  if agent_id.isNone:
    state.quarantine("event for unknown thread: " & thread_id)
    return
  let id = agent_id.get

  case notification.kind:
  of nk_thread_started:
    var agent = state.agents[id]
    if agent.state == as_starting:
      agent.state = as_idle
    state.agents[id] = agent
  of nk_turn_started:
    if params.turn_id.isNone:
      state.quarantine("turn started without ID: " & thread_id)
      return
    let request_key = active_turn_request_for_agent(state, id)
    if request_key.isNone:
      if state.turn_tombstones.hasKey(params.turn_id.get):
        state.quarantine("late turn started: " & params.turn_id.get)
      else:
        state.quarantine("turn started without active request: " & params.turn_id.get)
      return
    if bind_turn_request(state, request_key.get, params.turn_id.get):
      var agent = state.agents[id]
      agent.turn_id = params.turn_id
      agent.state = as_working
      state.agents[id] = agent
  of nk_turn_completed:
    var request_key = none(string)
    if params.turn_id.isSome:
      request_key = request_for_turn(state, params.turn_id.get)
      if request_key.isNone:
        if state.turn_tombstones.hasKey(params.turn_id.get):
          state.quarantine("duplicate or late turn completion: " & params.turn_id.get)
          return
        request_key = active_turn_request_for_agent(state, id)
        if request_key.isSome:
          discard bind_turn_request(state, request_key.get, params.turn_id.get)
    else:
      request_key = active_turn_request_for_agent(state, id)
    if request_key.isNone:
      state.quarantine("turn completion without owner: " &
        (if params.turn_id.isSome: params.turn_id.get else: thread_id))
      return
    let request = state.requests[request_key.get]
    if request.agent_id.isNone or request.agent_id.get != id:
      state.quarantine("turn completion crossed agent boundary: " &
        (if params.turn_id.isSome: params.turn_id.get else: request_key.get))
      return
    let completion = turn_completion_state(params)
    discard terminalize_turn(state, request_key.get, completion.state, completion.error)
  of nk_agent_message_delta:
    discard
  of nk_thread_status_changed:
    var agent = state.agents[id]
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
        let request_key = active_turn_request_for_agent(state, id)
        if request_key.isSome:
          discard terminalize_turn(state, request_key.get, rs_failed,
            some("system error"))
        agent = state.agents[id]
        set_agent_error(agent, "system error")
      of tsk_not_loaded:
        let request_key = active_turn_request_for_agent(state, id)
        if request_key.isSome:
          discard terminalize_turn(state, request_key.get, rs_interrupted,
            some("thread not loaded"))
        agent = state.agents[id]
        agent.state = as_closed
        agent.active_turn_request = none(string)
        agent.turn_id = none(string)
      of tsk_unknown:
        discard
    state.agents[id] = agent
  of nk_thread_closed:
    let request_key = active_turn_request_for_agent(state, id)
    if request_key.isSome:
      discard terminalize_turn(state, request_key.get, rs_interrupted,
        some("thread closed"))
    var agent = state.agents[id]
    agent.state = as_closed
    agent.turn_id = none(string)
    agent.active_turn_request = none(string)
    state.agents[id] = agent
  of nk_error:
    let request_key = active_turn_request_for_agent(state, id)
    if request_key.isSome:
      discard terminalize_turn(state, request_key.get, rs_failed,
        if params.error_message.isSome: params.error_message
        else: some("Codex runtime error"))
    var agent = state.agents[id]
    if params.error_message.isSome:
      set_agent_error(agent, params.error_message.get)
    else:
      set_agent_error(agent, "Codex runtime error")
    state.agents[id] = agent
  of nk_initialized, nk_server_request_resolved, nk_unknown:
    discard

proc send(stream: Stream; message: JsonNode) =
  stream.writeLine($message)
  stream.flush()

proc send_server_response(runtime: ptr CodexRuntime; response: ServerResponse) =
  if runtime.process.isNil:
    return
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

proc accept_tool_response*(runtime: ptr CodexRuntime; request_id: RequestId;
    success: bool; content_items: seq[DynamicToolContentItem])

proc handle_message*(runtime: ptr CodexRuntime; message: Message) =
  case message.kind:
  of mk_request:
    discard
  of mk_server_request:
    if not apply_server_request(runtime.state, message.server_request):
      return
    case message.server_request.kind:
    of sr_tool_call:
      try:
        apply_dynamic_tool_call(runtime.state, message.server_request)
      except CatchableError as error:
        ## External tool requests must receive a response even when the model
        ## names a tool that this agent does not expose.
        if runtime.process.isNil:
          discard remove_server_request(
            runtime.state,
            message.server_request.id)
        else:
          try:
            accept_tool_response(
              runtime,
              message.server_request.id,
              false,
              @[dynamic_tool_text(error.msg)])
          except CatchableError:
            discard remove_server_request(
              runtime.state,
              message.server_request.id)
            raise
        let agent_id = find_agent_for_thread(
          runtime.state,
          message.server_request.params.tool_call.thread_id)
        if agent_id.isSome:
          let turn_request = active_turn_request_for_agent(
            runtime.state,
            agent_id.get)
          if turn_request.isSome:
            discard terminalize_turn(
              runtime.state,
              turn_request.get,
              rs_failed,
              some(error.msg))
          var agent = runtime.state.agents[agent_id.get]
          set_agent_error(agent, error.msg)
          runtime.state.agents[agent_id.get] = agent
        raise
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
      if not runtime.process.isNil:
        send_server_response(runtime, ServerResponse(
          id: message.server_request.id,
          result: none(JsonNode),
          error: some(Error(
            id: message.server_request.id,
            code: -32601,
            message: "unsupported server request: " &
              message.server_request.method_name
          ))
        ))
      discard remove_server_request(runtime.state, message.server_request.id)
  of mk_server_response:
    let key = request_id_key(message.server_response.id)
    if not runtime.state.server_requests.hasKey(key):
      runtime.state.quarantine("unknown or duplicate server response: " & key)
      return
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
  if not codex.liveness.isNil:
    codex.liveness.alive = false
  stop_codex_threads(codex)
  stop_codex_runtime(codex)
  codex.process.close()
  codex.pending.setLen(0)
  codex.state.agents.clear()
  codex.state.requests.clear()
  codex.state.turn_request_keys.clear()
  codex.state.turn_tombstones.clear()
  codex.state.server_requests.clear()
  codex.state.server_request_tombstones.clear()
  reset(codex.process)
  reset(codex.pending)
  reset(codex.cwd)
  reset(codex.initialization_error)
  reset(codex.state.agents)
  reset(codex.state.requests)
  reset(codex.state.turn_request_keys)
  reset(codex.state.turn_tombstones)
  reset(codex.state.server_requests)
  reset(codex.state.server_request_tombstones)
  deallocShared(codex)

proc init_codex_runtime*(cwd: string): ptr CodexRuntime =
  if not dirExists(cwd):
    raise newException(ValueError, "cwd is not a directory: " & cwd)
  let canonical_cwd = expandFilename(cwd)

  result = cast[ptr CodexRuntime](allocShared0(sizeof(CodexRuntime)))
  new(result.liveness)
  result.liveness.alive = true
  result.state = new_runtime_state()
  result.handles_closed = false
  result.pending = @[]
  result.next_request_id = 0
  result.next_agent_id = 0
  result.cwd = canonical_cwd
  result.initialized = false
  result.initialization_error = none(string)

  try:
    result.process = startProcess(
      command = "codex",
      workingDir = result.cwd,
      args = ["app-server"],
      options = {poUsePath}
    )
  except CatchableError:
    result.liveness.alive = false
    result.state.agents.clear()
    result.state.requests.clear()
    result.state.turn_request_keys.clear()
    result.state.turn_tombstones.clear()
    result.state.server_requests.clear()
    result.state.server_request_tombstones.clear()
    deallocShared(result)
    result = nil
    raise

  try:
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
  except CatchableError:
    result.liveness.alive = false
    stop_codex_runtime(result)
    result.process.close()
    result.state.agents.clear()
    result.state.requests.clear()
    result.state.turn_request_keys.clear()
    result.state.turn_tombstones.clear()
    result.state.server_requests.clear()
    result.state.server_request_tombstones.clear()
    deallocShared(result)
    result = nil
    raise

proc output_handle*(runtime: ptr CodexRuntime): cint = runtime.process.outputHandle()
proc error_handle*(runtime: ptr CodexRuntime): cint = runtime.process.errorHandle()

proc allocate_agent_id*(runtime: ptr CodexRuntime): AgentId =
  while true:
    result = "vecherinka-agent-" & $runtime.next_agent_id
    inc runtime.next_agent_id
    if not runtime.state.agents.hasKey(result):
      return

proc create_agent*(runtime: ptr CodexRuntime; agent_id: AgentId;
    model: string; tools: DynamicToolRegistry = @[];
    developer_instructions: string = "";
    default_effort: ReasoningEffort = re_low;
    working_dir: string = ""): RequestId =
  if runtime.state.agents.hasKey(agent_id):
    raise newException(ValueError, "agent already exists: " & agent_id)
  let agent_cwd = if working_dir.len == 0:
    runtime.cwd
  else:
    if not dirExists(working_dir):
      raise newException(ValueError, "agent working directory is not a directory: " & working_dir)
    expandFilename(working_dir)

  var copied_tools = newSeq[DynamicTool](tools.len)
  for index, tool in tools:
    copied_tools[index] = tool

  runtime.state.agents[agent_id] = Agent(
    id: agent_id,
    thread_id: Nullable[string](has_value: false),
    turn_id: none(string),
    active_turn_request: none(string),
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
    cwd: NullableOption[string](state: nos_value, value: agent_cwd),
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
  if agent.active_turn_request.isSome:
    raise newException(ValueError, "agent already has an active turn: " & agent_id)

  var current = agent
  current.state = as_working
  runtime.state.agents[agent_id] = current

  let params = TurnStartParams(
    thread_id: agent.thread_id.value,
    text: text,
    effort: NullableOption[ReasoningEffort](state: nos_value, value: effort)
  )
  let request_id = queue_request(
    runtime,
    mk_turn_start,
    Params(kind: mk_turn_start, turn_start: params),
    some(agent_id)
  )
  current.active_turn_request = some(request_id_key(request_id))
  runtime.state.agents[agent_id] = current
  request_id

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
