## Runtime data model and lazy executor for lowered Vecherinka flows.
##
## Included by `vecherinka.nim`. Keep compile-time AST and macro machinery out
## of this fragment.

import std/[json, options, tables, posix, strutils, os,
  paths, tempfiles]
import codex_json
import codex_runtime
import structured_log

type
  ArtifactID* = uint64

  ArtifactMeta* = object
    id*: ArtifactID
    artifact_dir*: Path

  ArtifactRecord*[A] = object
    data*: A
    meta*: ArtifactMeta

  ProfileSpec* = object
    model*: string
    effort*: ReasoningEffort

  FlowKind* = enum
    fk_top,
    fk_model,
    fk_raw,
    fk_ref,
    fk_it,
    fk_fanout,
    fk_so,
    fk_lift

  Flow*[A] = ref object
    continuation*: Flow[A]
    case kind*: FlowKind
    of fk_top:
      root*: string
      entry*: bool
      body*: Flow[A]
    of fk_model:
      submit*: proc(
        context: RuntimeContext[A];
        request_id: RequestId;
        input: A;
        working_dir: Path
      ) {.nimcall.}
    of fk_raw:
      value*: A
    of fk_ref:
      name*: string
    of fk_it:
      projector*: proc(input: A): A {.nimcall.}
    of fk_fanout:
      branches*: seq[Flow[A]]
      coalesce*: proc(values: seq[A]): A {.nimcall.}
    of fk_so:
      execute*: proc(input: A): Flow[A] {.nimcall.}
    of fk_lift:
      inner*: Flow[A]
      destructure*: proc(input: A):
        seq[tuple[result_index: int, input: A]] {.nimcall.}
      construct*: proc(results: seq[A]; input: A): A {.nimcall.}

  JoinID* = uint64

  JoinKind* = enum
    jk_fanout,
    jk_lift

  DestinationKind* = enum
    dk_continue,
    dk_join,
    dk_finished

  Destination*[A] = ref object
    ## Dynamic destination used only when an invocation yields.
    case kind*: DestinationKind
    of dk_continue:
      flow*: Flow[A]
      next*: Destination[A]
    of dk_join:
      join_id*: JoinID
      slot*: int
    of dk_finished:
      discard

  Invocation*[A] = ref object
    ## One dynamic computation. Flow owns executable code; this owns its data
    ## input and explicit destination after it yields.
    flow*: Flow[A]
    input_id*: ArtifactID
    destination*: Destination[A]
    ## Some only for an in-flight model invocation.
    output_meta*: Option[ArtifactMeta]

  JoinState* = ref object
    ## Persistent fork/join data only. Control code lives in join_invocations.
    id*: JoinID
    kind*: JoinKind
    remaining*: int
    slots*: seq[Option[ArtifactID]]

  LlmOutput* = object
    ## Structured output passed by fake or real transport.
    tool_name*: string
    arguments*: JsonNode
    ## Runtime-only root used by generated Location verification. Transports
    ## leave it empty; the owner thread supplies it before materialization.
    working_dir*: Path

  LlmToolBinding* = object
    ## Vecherinka-owned state behind a dynamic tool handle. The handle itself
    ## is an opaque integer encoded as a pointer and is never dereferenced.
    id*: uint64
    context*: pointer
    request_id*: RequestId
    output_kind*: int
    materializer*: pointer

  ModelMaterialization*[A] = object
    case ok*: bool
    of true:
      value*: A
    of false:
      error*: string

  ModelMaterializer*[A] = proc(
    output_kind: int;
    output: LlmOutput
  ): ModelMaterialization[A] {.nimcall.}

  LlmCallSpec*[A] = object
    profile*: ProfileSpec
    prompt*: string
    materialized_input*: string
    runtime_dir*: Path
    working_dir*: Path
    tools*: DynamicToolRegistry
    output_kind*: int
    materialize*: ModelMaterializer[A]

  PendingAgentStart*[A] = object
    model_request_id*: RequestId
    agent_id*: AgentId
    start_request_id*: Option[RequestId]
    turn_request_id*: Option[RequestId]
    spec*: LlmCallSpec[A]

  RuntimeEventKind* = enum
    rev_model_artifact,
    rev_model_error,
    rev_shutdown

  RuntimeEvent*[A] = object
    request_id*: RequestId
    case kind*: RuntimeEventKind
    of rev_model_artifact:
      ## Keep typed artifact construction on the runtime thread. Events carry
      ## only transport output plus the generated materializer.
      output_kind*: int
      output*: LlmOutput
      materialize*: ModelMaterializer[A]
      tool_request_id*: Option[RequestId]
      tool_binding_id*: Option[uint64]
      output_meta*: Option[ArtifactMeta]
    of rev_model_error:
      error_message*: string
    of rev_shutdown:
      discard

  GlobalEventKind* = enum
    gek_runtime,
    gek_ready,
    gek_create_agent,
    gek_stdout_line,
    gek_stderr_line,
    gek_stdout_closed,
    gek_stderr_closed,
    gek_reader_error,
    gek_process_exit,
    gek_shutdown

  GlobalEvent* = object
    ## Events contain copied transport data or a main-thread work ID. Readers
    ## never receive or mutate CodexRuntime, WorkPlan, Flow, or RuntimeContext.
    case kind*: GlobalEventKind
    of gek_runtime:
      request_id*: RequestId
      case runtime_kind*: RuntimeEventKind
      of rev_model_artifact:
        output_kind*: int
        output_tool_name*: string
        output_arguments*: string
        output_materializer*: pointer
        tool_request_id*: Option[RequestId]
        tool_binding_id*: Option[uint64]
        output_meta*: Option[ArtifactMeta]
      of rev_model_error:
        error_message*: string
      of rev_shutdown:
        discard
    of gek_ready:
      ready_id*: uint64
    of gek_create_agent:
      model_request_id*: RequestId
      agent_id*: AgentId
      model*: string
      effort*: ReasoningEffort
      working_dir*: Path
      tools*: DynamicToolRegistry
    of gek_stdout_line, gek_stderr_line, gek_reader_error:
      message*: string
    of gek_stdout_closed, gek_stderr_closed, gek_process_exit,
        gek_shutdown:
      discard

  CodexReaderArgs = object
    fd: cint
    stop_fd: cint
    events: ptr Channel[GlobalEvent]
    line_kind: GlobalEventKind
    closed_kind: GlobalEventKind

  CodexReaders* = object
    stop_pipe*: array[0..1, cint]
    output_fd*: cint
    error_fd*: cint
    output_thread: Thread[CodexReaderArgs]
    error_thread: Thread[CodexReaderArgs]
    output_started*: bool
    error_started*: bool
    active*: bool

  GlobalEventMessenger* = object
    ## Main-thread state for global transport events. CodexRuntime remains
    ## exclusively owned by that same thread.
    stdout_closed*: bool
    stderr_closed*: bool
    process_exited*: bool
    last_stderr*: Option[string]

  RuntimeContext*[A] = ref object
    artifacts*: Table[ArtifactID, ArtifactRecord[A]]
    events*: Channel[GlobalEvent]
    events_open*: bool
    logger*: StructuredLogger
    submitter*: ModelSubmitter[A]
    transport*: LlmTransport[A]
    next_request_id*: int64
    ## Common base for runtime-relative Location values. This is the program
    ## working directory, not an individual artifact directory.
    runtime_dir*: Path
    run_dir*: Path
    next_artifact_id*: ArtifactID
    codex_runtime*: ptr CodexRuntime
    pending_agent_starts*: Table[string, PendingAgentStart[A]]

  ModelSubmitter*[A] = proc(
    context: RuntimeContext[A];
    request_id: RequestId;
    input: A;
    working_dir: Path
  ) {.nimcall.}

  LlmTransport*[A] = proc(
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
  ) {.nimcall.}

  WorkPlan*[A] = object
    context*: RuntimeContext[A]
    roots*: Table[string, Flow[A]]
    entry*: Flow[A]
    pending_ready*: Table[uint64, Invocation[A]]
    next_ready_id*: uint64
    joins*: Table[JoinID, JoinState]
    join_invocations*: Table[JoinID, Invocation[A]]
    next_join_id*: JoinID
    model_requests*: Table[string, Invocation[A]]
    output*: Option[ArtifactID]
    finished*: bool
    failed*: bool
    failure_message*: Option[string]

proc runtime_log*[A](context: RuntimeContext[A]; event, component: string;
    fields: JsonNode = nil) =
  ## Logging stays optional and non-fatal; runtime state never depends on it.
  if context.isNil or context.logger.isNil:
    return
  discard context.logger.emit(event, component, fields)

proc flow_kind_text[A](flow: Flow[A]): string =
  if flow.isNil:
    return "nil"
  $flow.kind

when sizeof(pointer) < sizeof(uint64):
  {.fatal: "Vecherinka dynamic tool handles require 64-bit pointers".}

var llm_tool_bindings = initTable[uint64, LlmToolBinding]()
var next_llm_tool_binding_id: uint64

proc llm_tool_handle(binding_id: uint64): pointer {.inline.} =
  cast[pointer](cast[uint](binding_id))

proc llm_tool_binding_id(handle: pointer): uint64 {.inline.} =
  cast[uint64](cast[uint](handle))

proc register_llm_tool_binding*(context: pointer; request_id: RequestId;
    output_kind: int; materializer: pointer): pointer =
  ## IDs are never reused: a stale DynamicTool handle can only miss lookup.
  if next_llm_tool_binding_id == high(uint64):
    raise newException(OverflowDefect, "LLM tool binding ID space exhausted")
  inc next_llm_tool_binding_id
  let binding_id = next_llm_tool_binding_id
  llm_tool_bindings[binding_id] = LlmToolBinding(
    id: binding_id,
    context: context,
    request_id: request_id,
    output_kind: output_kind,
    materializer: materializer)
  llm_tool_handle(binding_id)

proc lookup_llm_tool_binding*(handle: pointer): Option[LlmToolBinding] =
  ## Callback and registry mutation are serialized by the runtime coordinator.
  let binding_id = llm_tool_binding_id(handle)
  if binding_id == 0 or not llm_tool_bindings.hasKey(binding_id):
    return none(LlmToolBinding)
  some(llm_tool_bindings[binding_id])

proc retire_llm_tool_binding*(binding_id: uint64) =
  llm_tool_bindings.del(binding_id)

proc retire_llm_tool_bindings*(context: pointer) =
  var retired: seq[uint64] = @[]
  for binding_id, binding in llm_tool_bindings.pairs:
    if binding.context == context:
      retired.add(binding_id)
  for binding_id in retired:
    llm_tool_bindings.del(binding_id)

proc open_global_events*[A](context: RuntimeContext[A]) =
  ## Open once before reader threads start; close only after all readers join.
  if context.events_open:
    raise newException(ValueError, "global event channel already open")
  context.events.open()
  context.events_open = true

proc close_global_events*[A](context: RuntimeContext[A]) =
  ## Channel lifetime is a main-thread responsibility.
  if context.events_open:
    context.events.close()
    context.events_open = false

proc send_global_event*(events: ptr Channel[GlobalEvent]; event: GlobalEvent) {.gcsafe.} =
  ## Reader-side send. Caller must keep channel open until readers stop.
  events[].send(event)

proc send_global_event*[A](context: RuntimeContext[A]; event: GlobalEvent) =
  if not context.events_open:
    raise newException(ValueError, "global event channel is not open")
  context.events.send(event)

proc enqueue_runtime_event*[A](
    context: RuntimeContext[A];
    event: RuntimeEvent[A]
) =
  ## Runtime callbacks publish value-only events; main loop handles them later.
  if not context.events_open:
    raise newException(ValueError, "global event channel is not open")
  var global_event: GlobalEvent
  case event.kind
  of rev_model_artifact:
    global_event = GlobalEvent(
      kind: gek_runtime,
      request_id: event.request_id,
      runtime_kind: rev_model_artifact,
      output_kind: event.output_kind,
      output_tool_name: event.output.tool_name,
      output_arguments: $event.output.arguments,
      output_materializer: cast[pointer](event.materialize),
      tool_request_id: event.tool_request_id,
      tool_binding_id: event.tool_binding_id,
      output_meta: event.output_meta)
  of rev_model_error:
    global_event = GlobalEvent(
      kind: gek_runtime,
      request_id: event.request_id,
      runtime_kind: rev_model_error,
      error_message: event.error_message)
  of rev_shutdown:
    global_event = GlobalEvent(
      kind: gek_runtime,
      request_id: event.request_id,
      runtime_kind: rev_shutdown)
  send_global_event(context, global_event)

proc enqueue_llm_output_event*[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    output_kind: int;
    materialize: ModelMaterializer[A];
    binding_id: uint64;
    tool_context: ToolCallContext
) {.gcsafe.} =
  ## Callback only copies transport data. Typed decoding stays owner-thread.
  {.cast(gcsafe).}:
    let event = RuntimeEvent[A](
      request_id: request_id,
      kind: rev_model_artifact,
      output_kind: output_kind,
      output: LlmOutput(
        tool_name: tool_context.params.tool,
        arguments: tool_context.params.arguments),
      materialize: materialize,
      tool_request_id: some(tool_context.request_id),
      tool_binding_id: some(binding_id),
      output_meta: none(ArtifactMeta))
    enqueue_runtime_event(context, event)

proc recv_global_event*[A](context: RuntimeContext[A]): GlobalEvent =
  context.events.recv()

proc try_recv_global_event*[A](context: RuntimeContext[A]): tuple[data_available: bool, event: GlobalEvent] =
  let received = context.events.tryRecv()
  (data_available: received.dataAvailable, event: received.msg)

proc reader_error_message(operation: string; error_code: cint): string =
  operation & " failed (errno " & $error_code & ")"

proc new_line_event(kind: GlobalEventKind; message: string): GlobalEvent =
  case kind
  of gek_stdout_line, gek_stderr_line:
    GlobalEvent(kind: kind, message: message)
  else:
    raise newException(ValueError, "invalid line event kind")

proc emit_pending_lines(
    pending: var string;
    line_kind: GlobalEventKind;
    events: ptr Channel[GlobalEvent]
) {.gcsafe.} =
  ## Each loop removes one complete line; remaining bytes stay local to reader.
  while true:
    let newline = pending.find('\n')
    if newline < 0:
      break
    var line = pending[0 ..< newline]
    if line.len > 0 and line[^1] == '\r':
      line.setLen(line.len - 1)
    send_global_event(events, new_line_event(line_kind, line))
    if newline + 1 >= pending.len:
      pending.setLen(0)
    else:
      pending = pending[newline + 1 .. ^1]

proc read_codex_stream(args: CodexReaderArgs) {.thread, gcsafe.} =
  var watched = [
    TPollfd(fd: args.fd, events: POLLIN, revents: 0),
    TPollfd(fd: args.stop_fd, events: POLLIN, revents: 0)
  ]
  var pending = ""
  var reached_eof = false

  while true:
    var poll_result: cint
    while true:
      poll_result = poll(addr watched[0], Tnfds(2), -1)
      if poll_result >= 0 or errno != EINTR:
        break
    if poll_result < 0:
      send_global_event(args.events, GlobalEvent(
        kind: gek_reader_error,
        message: reader_error_message("poll", errno)))
      break

    if watched[1].revents != 0:
      break

    let stream_events = watched[0].revents
    if (stream_events and POLLNVAL) != 0:
      send_global_event(args.events, GlobalEvent(
        kind: gek_reader_error,
        message: reader_error_message("poll descriptor", EBADF)))
      break
    if (stream_events and POLLERR) != 0 and
        (stream_events and POLLIN) == 0 and
        (stream_events and POLLHUP) == 0:
      send_global_event(args.events, GlobalEvent(
        kind: gek_reader_error,
        message: reader_error_message("stream poll", EIO)))
      break

    if (stream_events and (POLLIN or POLLHUP or POLLERR)) == 0:
      continue

    var buffer: array[4096, byte]
    var count: int
    while true:
      count = read(args.fd, addr buffer[0], buffer.len)
      if count >= 0 or errno != EINTR:
        break
    if count > 0:
      var chunk = newString(count)
      copyMem(addr chunk[0], addr buffer[0], count)
      pending.add(chunk)
      emit_pending_lines(pending, args.line_kind, args.events)
    elif count == 0:
      reached_eof = true
      break
    else:
      send_global_event(args.events, GlobalEvent(
        kind: gek_reader_error,
        message: reader_error_message("read", errno)))
      break

  if reached_eof:
    if pending.len > 0:
      if pending[^1] == '\r':
        pending.setLen(pending.len - 1)
      send_global_event(args.events, new_line_event(args.line_kind, pending))
    send_global_event(args.events, GlobalEvent(kind: args.closed_kind))

proc start_codex_readers_impl(
    readers: var CodexReaders;
    events: ptr Channel[GlobalEvent];
    output_fd, error_fd: cint
) =
  ## Child descriptors are borrowed. CodexRuntime owns their eventual close.
  if readers.active:
    raise newException(ValueError, "Codex readers already active")
  if output_fd < 0 or error_fd < 0:
    raise newException(ValueError, "invalid Codex output descriptor")
  if pipe(readers.stop_pipe) != 0:
    raise newException(IOError, reader_error_message("stop pipe", errno))

  readers.output_fd = output_fd
  readers.error_fd = error_fd
  readers.output_started = false
  readers.error_started = false
  readers.active = true

  try:
    createThread(
      readers.output_thread,
      read_codex_stream,
      CodexReaderArgs(
        fd: output_fd,
        stop_fd: readers.stop_pipe[0],
        events: events,
        line_kind: gek_stdout_line,
        closed_kind: gek_stdout_closed))
    readers.output_started = true
    createThread(
      readers.error_thread,
      read_codex_stream,
      CodexReaderArgs(
        fd: error_fd,
        stop_fd: readers.stop_pipe[0],
        events: events,
        line_kind: gek_stderr_line,
        closed_kind: gek_stderr_closed))
    readers.error_started = true
  except CatchableError:
    var signal = 'x'
    discard write(readers.stop_pipe[1], addr signal, 1)
    if readers.output_started:
      readers.output_thread.joinThread()
    if readers.error_started:
      readers.error_thread.joinThread()
    discard close(readers.stop_pipe[0])
    discard close(readers.stop_pipe[1])
    readers.active = false
    raise

proc start_codex_readers*[A](
    readers: var CodexReaders;
    context: RuntimeContext[A];
    output_fd, error_fd: cint
) =
  if context.isNil or not context.events_open:
    raise newException(ValueError, "global event channel is not open")
  start_codex_readers_impl(
    readers,
    addr context.events,
    output_fd,
    error_fd)

proc start_codex_readers*[A](
    readers: var CodexReaders;
    context: RuntimeContext[A];
    runtime: ptr CodexRuntime
) =
  ## Descriptor lookup happens on the owning main thread before readers start.
  if runtime.isNil:
    raise newException(ValueError, "Codex readers require CodexRuntime owner")
  start_codex_readers(
    readers,
    context,
    runtime.output_handle(),
    runtime.error_handle())

proc stop_codex_readers*(readers: var CodexReaders) =
  ## Wake and join readers before channel or borrowed descriptor cleanup.
  if not readers.active:
    return
  var signal = 'x'
  discard write(readers.stop_pipe[1], addr signal, 1)
  if readers.output_started:
    readers.output_thread.joinThread()
  if readers.error_started:
    readers.error_thread.joinThread()
  discard close(readers.stop_pipe[0])
  discard close(readers.stop_pipe[1])
  readers.output_started = false
  readers.error_started = false
  readers.active = false

proc new_global_event_messenger*(): GlobalEventMessenger =
  GlobalEventMessenger(
    stdout_closed: false,
    stderr_closed: false,
    process_exited: false,
    last_stderr: none(string))

proc streams_closed(messenger: GlobalEventMessenger): bool {.inline.} =
  messenger.stdout_closed and messenger.stderr_closed

proc fail_on_process_exit[A](
    plan: var WorkPlan[A];
    messenger: GlobalEventMessenger
) =
  ## Child exit is terminal only after both pipes drained and process reaped.
  ## This preserves final bytes while preventing a dead coordinator receive.
  if messenger.process_exited and messenger.streams_closed and not plan.finished:
    plan.failed = true
    plan.finished = true
    plan.failure_message = some(
      if messenger.last_stderr.isSome:
        "codex app-server exited: " & messenger.last_stderr.get
      else:
        "codex app-server exited before work completed")

proc fail_runtime[A](plan: var WorkPlan[A]; message: string) =
  if plan.finished:
    return
  plan.failed = true
  plan.finished = true
  plan.failure_message = some(message)

proc codex_process_exit_seen(
    messenger: var GlobalEventMessenger;
    runtime: ptr CodexRuntime
): bool =
  if messenger.process_exited or runtime.isNil:
    return messenger.process_exited
  if not runtime.is_running():
    messenger.process_exited = true
  messenger.process_exited

proc handle_global_event*(
    messenger: var GlobalEventMessenger;
    runtime: ptr CodexRuntime;
    event: GlobalEvent
) =
  ## Main-thread coordinator. Only this path touches CodexRuntime protocol state.
  case event.kind
  of gek_runtime, gek_ready:
    discard
  of gek_create_agent:
    discard
  of gek_stdout_line:
    if runtime.isNil:
      raise newException(ValueError, "stdout event requires CodexRuntime owner")
    discard runtime.accept_json(parseJson(event.message))
  of gek_stderr_line:
    messenger.last_stderr = some(event.message)
  of gek_stdout_closed:
    messenger.stdout_closed = true
    discard messenger.codex_process_exit_seen(runtime)
  of gek_stderr_closed:
    messenger.stderr_closed = true
    discard messenger.codex_process_exit_seen(runtime)
  of gek_process_exit:
    messenger.process_exited = true
  of gek_reader_error:
    raise newException(IOError, event.message)
  of gek_shutdown:
    discard

proc none*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_none)
proc minimal*(model: string): ProfileSpec =
  ## Compatibility alias. Codex renamed this effort to `none`.
  none(model)
proc low*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_low)
proc medium*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_medium)
proc high*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_high)
proc xhigh*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_xhigh)
proc max*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_max)

proc prepend_continuation*[A](
    flow: Flow[A];
    destination: Destination[A]
): Destination[A] =
  if flow.isNil:
    return destination
  Destination[A](kind: dk_continue, flow: flow, next: destination)

proc new_runtime_context*[A](
    submitter: ModelSubmitter[A] = nil;
    transport: LlmTransport[A] = nil;
    run_dir: Path = Path("");
    runtime_dir: Path = Path("");
    logger: StructuredLogger = nil
): RuntimeContext[A] =
  new result
  result.artifacts = initTable[ArtifactID, ArtifactRecord[A]]()
  result.events_open = false
  result.logger = logger
  result.submitter = submitter
  result.transport = transport
  result.next_request_id = 0
  result.runtime_dir = if $runtime_dir == "": run_dir else: runtime_dir
  result.run_dir = run_dir
  result.next_artifact_id = 0
  result.codex_runtime = nil
  result.pending_agent_starts = initTable[string, PendingAgentStart[A]]()

proc create_run_directory*(source_root: Path): Path =
  ## Keep run state in a unique child of the program working directory.
  if not dirExists($source_root):
    raise newException(ValueError, "source root is not a directory: " &
      $source_root)
  Path(createTempDir("run-", "", $source_root))

proc reserve_artifact_meta*[A](context: RuntimeContext[A]): ArtifactMeta =
  if $context.run_dir == "":
    raise newException(ValueError, "runtime context has no run directory")
  inc context.next_artifact_id
  result = ArtifactMeta(
    id: context.next_artifact_id,
    artifact_dir: context.run_dir /
      Path("artifact-" & $context.next_artifact_id))
  createDir($result.artifact_dir)
  context.runtime_log(
    "artifact.reserve",
    "vecherinka",
    log_fields(
      ("artifact_id", %result.id),
      ("artifact_dir", %($lastPathPart(result.artifact_dir)))))

proc allocate_artifact_meta*[A](context: RuntimeContext[A]): ArtifactMeta =
  ## Compatibility name for callers that only reserve identity and root.
  reserve_artifact_meta(context)

proc register_artifact*[A](
    context: RuntimeContext[A];
    data: A;
    meta: ArtifactMeta
): ArtifactID =
  ## Registration establishes the sole persistent owner of this artifact.
  if context.isNil:
    raise newException(ValueError, "cannot register artifact without context")
  if context.artifacts.hasKey(meta.id):
    raise newException(ValueError, "artifact ID already registered: " & $meta.id)
  context.artifacts[meta.id] = ArtifactRecord[A](data: data, meta: meta)
  result = meta.id
  context.runtime_log(
    "artifact.commit",
    "vecherinka",
    log_fields(
      ("artifact_id", %meta.id),
      ("artifact_dir", %($lastPathPart(meta.artifact_dir)))))

proc lookup_artifact*[A](
    context: RuntimeContext[A];
    artifact_id: ArtifactID
): ArtifactRecord[A] =
  if context.isNil or not context.artifacts.hasKey(artifact_id):
    raise newException(ValueError, "unknown artifact ID: " & $artifact_id)
  result = context.artifacts[artifact_id]
  if result.meta.id != artifact_id:
    raise newException(ValueError, "artifact table key and metadata ID mismatch")

proc register_generated_artifact[A](
    context: RuntimeContext[A];
    data: A
): ArtifactID =
  let meta = reserve_artifact_meta(context)
  register_artifact(context, data, meta)

proc materialized_name_used(names: seq[string]; name: string): bool =
  for used_name in names:
    if used_name == name:
      return true
  false

proc copy_location_payload*(
    runtime_dir, artifact_dir: Path;
    location: string;
    materialized_names: var seq[string]
): string =
  ## Destination is flat by design. The containment check also prevents a
  ## Location naming a parent of the destination from recursive self-copy.
  if location.len == 0:
    raise newException(IOError, "materialize Location is empty")

  let source = runtime_dir / Path(location)
  if not source.isRelativeTo(runtime_dir):
    raise newException(IOError,
      "materialize Location is outside runtime directory: " & $source)

  let source_is_file = fileExists($source)
  let source_is_dir = dirExists($source)
  if not source_is_file and not source_is_dir:
    raise newException(IOError,
      "materialize Location source does not exist: " & $source)
  if source_is_dir and artifact_dir.isRelativeTo(source):
    raise newException(IOError,
      "materialize Location source contains destination: " & $source)

  createDir($artifact_dir)
  let parts = splitFile(source)
  let stem = $parts.name
  if stem.len == 0:
    raise newException(IOError,
      "materialize Location has no file name: " & $source)

  var suffix = 0
  while true:
    let candidate = stem & (if suffix == 0: "" else: "-" & $suffix) &
      parts.ext
    let destination = artifact_dir / Path(candidate)
    if not materialized_name_used(materialized_names, candidate) and
        not fileExists($destination) and not dirExists($destination):
      if source_is_file:
        ## Check immediately before the file copy, not only during path setup.
        if not source.isRelativeTo(runtime_dir):
          raise newException(IOError,
            "materialize Location is outside runtime directory: " & $source)
        copyFile($source, $destination)
      else:
        if not source.isRelativeTo(runtime_dir):
          raise newException(IOError,
            "materialize Location is outside runtime directory: " & $source)
        copyDir($source, $destination)
      materialized_names.add(candidate)
      return candidate
    inc suffix

proc verify_location_payload*(working_dir: Path; location: string): string =
  ## A valid output Location names an existing payload inside this model call.
  if location.len == 0:
    return "Location is empty"

  let source = working_dir / Path(location)
  if not source.isRelativeTo(working_dir):
    return "Location is outside working directory: " & $source
  if not fileExists($source) and not dirExists($source):
    return "Location source does not exist: " & $source
  ""

proc allocate_request_id[A](context: RuntimeContext[A]): RequestId =
  result = RequestId(kind: rid_integer,
    integer_value: context.next_request_id)
  inc context.next_request_id

proc init_work_plan*[A](
    top_level_flows: seq[Flow[A]];
    context: RuntimeContext[A]
): WorkPlan[A] =
  result.context = context
  result.roots = initTable[string, Flow[A]]()
  result.joins = initTable[JoinID, JoinState]()
  result.join_invocations = initTable[JoinID, Invocation[A]]()
  result.model_requests = initTable[string, Invocation[A]]()
  result.pending_ready = initTable[uint64, Invocation[A]]()
  result.next_ready_id = 0
  result.next_join_id = 1
  result.output = none(ArtifactID)
  result.failure_message = none(string)

  for top in top_level_flows:
    if top.isNil or top.kind != fk_top:
      raise newException(ValueError, "top-level flow is not fk_top")
    if result.roots.hasKey(top.root):
      raise newException(ValueError, "duplicate root: " & top.root)
    result.roots[top.root] = top.body
    if top.entry:
      if not result.entry.isNil:
        raise newException(ValueError, "multiple entry roots")
      result.entry = top.body

  if result.entry.isNil:
    raise newException(ValueError, "missing entry root")

proc init_work_plan*[A](
    top_level_flows: seq[Flow[A]]
): WorkPlan[A] =
  ## Compatibility validator for the old generated solve wrapper. It does not
  ## execute because there is no valid runtime input in this overload.
  init_work_plan(top_level_flows, new_runtime_context[A]())

proc resolve_root[A](
    roots: Table[string, Flow[A]];
    name: string
): Flow[A] =
  if not roots.hasKey(name):
    raise newException(ValueError, "unknown flow root: " & name)
  roots[name]

proc fail_plan[A](plan: var WorkPlan[A]; message: string) =
  plan.failed = true
  plan.finished = true
  raise newException(ValueError, message)

template plan_assert[A](plan: var WorkPlan[A]; condition: bool;
    message: string) =
  ## Invariant failure is terminal; fail_plan raises, so callers need no return.
  if not condition:
    fail_plan(plan, message)

proc new_join_state[A](
    plan: var WorkPlan[A];
    kind: JoinKind;
    slot_count: int
): JoinID =
  plan_assert(plan, slot_count >= 0, "join slot count cannot be negative")
  result = plan.next_join_id
  inc plan.next_join_id
  plan.joins[result] = JoinState(
    id: result,
    kind: kind,
    remaining: slot_count,
    slots: newSeq[Option[ArtifactID]](slot_count))
  plan.context.runtime_log(
    "join.open",
    "vecherinka",
    log_fields(
      ("join_id", %result),
      ("kind", %($kind)),
      ("slot_count", %slot_count)))

proc accept_join_result[A](
    plan: var WorkPlan[A];
    join_id: JoinID;
    slot: int;
    artifact_id: ArtifactID
)

proc new_invocation[A](
    flow: Flow[A];
    input_id: ArtifactID;
    destination: Destination[A]
): Invocation[A] =
  Invocation[A](
    flow: flow,
    input_id: input_id,
    destination: destination,
    output_meta: none(ArtifactMeta))

proc enqueue_ready[A](
    plan: var WorkPlan[A];
    invocation: Invocation[A]
) =
  ## Typed invocation stays owner-thread state; channel carries only its ID.
  discard lookup_artifact(plan.context, invocation.input_id)
  inc plan.next_ready_id
  let ready_id = plan.next_ready_id
  plan.pending_ready[ready_id] = invocation
  plan.context.runtime_log(
    "ready.enqueue",
    "vecherinka",
    log_fields(
      ("ready_id", %ready_id),
      ("flow_kind", %(flow_kind_text(invocation.flow))),
      ("input_artifact_id", %invocation.input_id)))
  send_global_event(plan.context, GlobalEvent(
    kind: gek_ready,
    ready_id: ready_id))

proc deliver_destination[A](
    plan: var WorkPlan[A];
    destination: Destination[A];
    artifact_id: ArtifactID
) =
  plan_assert(plan, not destination.isNil, "nil invocation destination")

  case destination.kind
  of dk_continue:
    enqueue_ready(plan, new_invocation(
      destination.flow,
      artifact_id,
      destination.next
    ))
  of dk_join:
    accept_join_result(plan, destination.join_id, destination.slot, artifact_id)
  of dk_finished:
    plan.output = some(artifact_id)
    plan.finished = true

proc finish_join[A](
    plan: var WorkPlan[A];
    join_id: JoinID
) =
  plan_assert(plan, plan.joins.hasKey(join_id), "unknown join")
  plan_assert(plan, plan.join_invocations.hasKey(join_id),
    "join has no invocation")

  let state = plan.joins[join_id]
  let invocation = plan.join_invocations[join_id]
  plan_assert(plan, state.remaining == 0,
    "join finalized before all results arrived")

  var values = newSeq[A](state.slots.len)
  for index, slot in state.slots:
    plan_assert(plan, slot.isSome, "join has missing result slot")
    values[index] = lookup_artifact(plan.context, slot.get).data

  plan_assert(plan, not invocation.flow.isNil,
    "join invocation has no flow")

  var output: A
  case state.kind
  of jk_fanout:
    plan_assert(plan,
      invocation.flow.kind == fk_fanout and not invocation.flow.coalesce.isNil,
      "fanout join has invalid flow")
    output = invocation.flow.coalesce(values)
  of jk_lift:
    plan_assert(plan,
      invocation.flow.kind == fk_lift and not invocation.flow.construct.isNil,
      "lift join has invalid flow")
    let original = lookup_artifact(plan.context, invocation.input_id).data
    output = invocation.flow.construct(values, original)

  let destination = invocation.destination
  let output_id = register_generated_artifact(plan.context, output)
  plan.context.runtime_log(
    "join.close",
    "vecherinka",
    log_fields(
      ("join_id", %join_id),
      ("output_artifact_id", %output_id)))
  plan.joins.del(join_id)
  plan.join_invocations.del(join_id)
  deliver_destination(plan, destination, output_id)

proc accept_join_result[A](
    plan: var WorkPlan[A];
    join_id: JoinID;
    slot: int;
    artifact_id: ArtifactID
) =
  plan_assert(plan, plan.joins.hasKey(join_id), "unknown join result")

  let state = plan.joins[join_id]
  discard lookup_artifact(plan.context, artifact_id)
  plan_assert(plan, slot >= 0 and slot < state.slots.len,
    "invalid join slot")
  plan_assert(plan, state.slots[slot].isNone, "duplicate join result")

  state.slots[slot] = some(artifact_id)
  dec state.remaining
  plan.context.runtime_log(
    "join.slot",
    "vecherinka",
    log_fields(
      ("join_id", %join_id),
      ("slot", %slot),
      ("artifact_id", %artifact_id),
      ("remaining", %state.remaining)))
  if state.remaining == 0:
    finish_join(plan, join_id)
    return

proc default_model_submit[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    input: A;
    working_dir: Path
) =
  discard input
  discard working_dir
  let event = RuntimeEvent[A](
    kind: rev_model_error,
    request_id: request_id,
    error_message: "no model submitter configured")
  enqueue_runtime_event(context, event)

proc default_llm_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  ## Queue agent creation. Coordinator sends turn only after thread/start
  ## response installs thread ID in CodexRuntime.
  if context.codex_runtime.isNil:
    enqueue_runtime_event(context, RuntimeEvent[A](
      kind: rev_model_error,
      request_id: request_id,
      error_message: "no Codex runtime configured"))
    return

  let key = request_id_key(request_id)
  if context.pending_agent_starts.hasKey(key):
    enqueue_runtime_event(context, RuntimeEvent[A](
      kind: rev_model_error,
      request_id: request_id,
      error_message: "duplicate pending agent request"))
    return

  let agent_id = "vecherinka-agent-" & key
  context.pending_agent_starts[key] = PendingAgentStart[A](
    model_request_id: request_id,
    agent_id: agent_id,
    start_request_id: none(RequestId),
    turn_request_id: none(RequestId),
    spec: spec)
  send_global_event(context, GlobalEvent(
    kind: gek_create_agent,
    model_request_id: request_id,
    agent_id: agent_id,
    model: spec.profile.model,
    effort: spec.profile.effort,
    working_dir: spec.working_dir,
    tools: spec.tools))

proc llm_turn_prompt[A](spec: LlmCallSpec[A]): string =
  ## Generic wrapper avoids copying LlmCallSpec through erased boundaries.
  result = spec.prompt
  result.add("\n\nComplete task. Call finish_work exactly once when done.")
  result.add("\nYou may modify only: " & $spec.working_dir)
  result.add("\nLocation values are paths relative to: " & $spec.runtime_dir)
  result.add("\nEvery Location must name an existing file or directory inside the working directory.")
  if spec.materialized_input.len != 0:
    result.add("\n\ninput:\n")
    result.add(spec.materialized_input)

proc enqueue_agent_error[A](context: RuntimeContext[A]; request_id: RequestId;
    message: string) =
  enqueue_runtime_event(context, RuntimeEvent[A](
    kind: rev_model_error,
    request_id: request_id,
    error_message: message))

proc begin_agent_creation[A](
    plan: var WorkPlan[A];
    runtime: ptr CodexRuntime;
    event: GlobalEvent
) =
  plan_assert(plan, not runtime.isNil, "agent creation requires CodexRuntime")
  let key = request_id_key(event.model_request_id)
  plan_assert(plan, plan.model_requests.hasKey(key),
    "agent creation has unknown model request")
  plan_assert(plan, plan.context.pending_agent_starts.hasKey(key),
    "agent creation has no pending context")

  var pending = plan.context.pending_agent_starts[key]
  plan_assert(plan, pending.start_request_id.isNone,
    "agent creation already started")
  plan_assert(plan, pending.agent_id == event.agent_id,
    "agent creation ID mismatch")

  try:
    let start_request_id = runtime.create_agent(
      event.agent_id,
      event.model,
      event.tools,
      "Complete task. Call finish_work exactly once when done.",
      event.effort,
      $event.working_dir)
    pending.start_request_id = some(start_request_id)
    plan.context.pending_agent_starts[key] = pending
    plan.context.runtime_log(
      "agent.thread.submit",
      "codex",
      log_fields(
        ("model_request_id", %(request_id_key(event.model_request_id))),
        ("agent_id", %event.agent_id),
        ("request_id", %(request_id_key(start_request_id)))))
  except CatchableError as error:
    plan.context.pending_agent_starts.del(key)
    plan.context.runtime_log(
      "agent.thread.fail",
      "codex",
      log_fields(
        ("model_request_id", %(request_id_key(event.model_request_id))),
        ("agent_id", %event.agent_id),
        ("error", %error.msg)))
    enqueue_agent_error(plan.context, event.model_request_id, error.msg)

proc advance_agent_starts[A](
    plan: var WorkPlan[A];
    runtime: ptr CodexRuntime
) =
  if runtime.isNil:
    return
  var completed: seq[string] = @[]
  for key, pending_value in plan.context.pending_agent_starts.pairs:
    var pending = pending_value
    if pending.turn_request_id.isSome:
      let turn_key = request_id_key(pending.turn_request_id.get)
      if not runtime.requests.hasKey(turn_key):
        continue
      let turn_request = runtime.requests[turn_key]
      if turn_request.state == rs_failed:
        enqueue_agent_error(
          plan.context,
          pending.model_request_id,
          if turn_request.error.isSome:
            turn_request.error.get
          else:
            "agent turn failed")
        completed.add(key)
      elif turn_request.state == rs_completed:
        enqueue_agent_error(
          plan.context,
          pending.model_request_id,
          "agent turn completed without finish_work")
        completed.add(key)
      continue
    if pending.start_request_id.isNone:
      continue
    let start_request_id = pending.start_request_id.get
    let start_key = request_id_key(start_request_id)
    if not runtime.requests.hasKey(start_key):
      continue
    let start_request = runtime.requests[start_key]
    if start_request.state == rs_failed:
      enqueue_agent_error(
        plan.context,
        pending.model_request_id,
        if start_request.error.isSome:
          start_request.error.get
        else:
          "agent creation failed")
      completed.add(key)
      continue
    if not runtime.agents.hasKey(pending.agent_id) or
        not runtime.agents[pending.agent_id].thread_id.has_value:
      continue
    try:
      let turn_request_id = runtime.send_agent_message(
        pending.agent_id,
        llm_turn_prompt(pending.spec),
        pending.spec.profile.effort)
      pending.turn_request_id = some(turn_request_id)
      plan.context.pending_agent_starts[key] = pending
      plan.context.runtime_log(
        "agent.turn.submit",
        "codex",
        log_fields(
          ("model_request_id", %(request_id_key(pending.model_request_id))),
          ("agent_id", %pending.agent_id),
          ("request_id", %(request_id_key(turn_request_id)))))
    except CatchableError as error:
      plan.context.runtime_log(
        "agent.turn.fail",
        "codex",
        log_fields(
          ("model_request_id", %(request_id_key(pending.model_request_id))),
          ("agent_id", %pending.agent_id),
          ("error", %error.msg)))
      enqueue_agent_error(plan.context, pending.model_request_id, error.msg)
      completed.add(key)
  for key in completed:
    plan.context.pending_agent_starts.del(key)

proc submit_llm*[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  let transport = if context.transport.isNil:
    default_llm_transport[A]
  else:
    context.transport
  transport(context, request_id, spec)

proc suspend_model[A](
    plan: var WorkPlan[A];
    flow: Flow[A];
    input_id: ArtifactID;
    destination: Destination[A]
) =
  let input_record = lookup_artifact(plan.context, input_id)
  let request_id = allocate_request_id(plan.context)
  let output_meta = reserve_artifact_meta(plan.context)
  let invocation = Invocation[A](
    flow: flow,
    input_id: input_id,
    destination: prepend_continuation(flow.continuation, destination),
    output_meta: some(output_meta))
  let key = request_id_key(request_id)
  plan_assert(plan, not plan.model_requests.hasKey(key),
    "duplicate model request ID")
  plan.model_requests[key] = invocation
  plan.context.runtime_log(
    "model.submit",
    "vecherinka",
    log_fields(
      ("request_id", %(request_id_key(request_id))),
      ("flow_kind", %(flow_kind_text(flow))),
      ("input_artifact_id", %input_id),
      ("output_artifact_id", %output_meta.id),
      ("submitter", %(if flow.submit.isNil: "default" else: "custom")),
      ("working_dir", %($lastPathPart(output_meta.artifact_dir)))))
  if not flow.submit.isNil:
    flow.submit(
      plan.context, request_id, input_record.data, output_meta.artifact_dir)
  else:
    let submitter = if not plan.context.submitter.isNil:
      plan.context.submitter
    else:
      default_model_submit[A]
    submitter(
      plan.context, request_id, input_record.data, output_meta.artifact_dir)

proc begin_fanout[A](
    plan: var WorkPlan[A];
    flow: Flow[A];
    input_id: ArtifactID;
    destination: Destination[A]
) =
  let join_id = new_join_state(plan, jk_fanout, flow.branches.len)
  plan.join_invocations[join_id] = new_invocation(
    flow,
    input_id,
    prepend_continuation(flow.continuation, destination))

  for index, branch in flow.branches:
    enqueue_ready(plan, new_invocation(
      branch,
      input_id,
      Destination[A](kind: dk_join, join_id: join_id, slot: index)))

  if flow.branches.len == 0:
    finish_join(plan, join_id)

proc begin_lift[A](
    plan: var WorkPlan[A];
    flow: Flow[A];
    input_id: ArtifactID;
    destination: Destination[A]
) =
  let original = lookup_artifact(plan.context, input_id).data
  let works = flow.destructure(original)
  var seen = newSeq[bool](works.len)
  for work in works:
    plan_assert(plan,
      work.result_index >= 0 and work.result_index < works.len,
      "lift result index out of range")
    plan_assert(plan, not seen[work.result_index],
      "duplicate lift result index")
    seen[work.result_index] = true

  for index in 0 ..< seen.len:
    plan_assert(plan, seen[index], "lift result indexes are not contiguous")

  let join_id = new_join_state(plan, jk_lift, works.len)
  plan.join_invocations[join_id] = new_invocation(
    flow,
    input_id,
    prepend_continuation(flow.continuation, destination))

  for work in works:
    let input_artifact_id = register_generated_artifact(plan.context, work.input)
    enqueue_ready(plan, new_invocation(
      flow.inner,
      input_artifact_id,
      Destination[A](
        kind: dk_join,
        join_id: join_id,
        slot: work.result_index)))

  if works.len == 0:
    finish_join(plan, join_id)

proc handle_invocation*[A](
    plan: var WorkPlan[A];
    invocation: Invocation[A]
) =
  let initial_record = lookup_artifact(plan.context, invocation.input_id)
  plan.context.runtime_log(
    "invocation.start",
    "vecherinka",
    log_fields(
      ("flow_kind", %(flow_kind_text(invocation.flow))),
      ("input_artifact_id", %invocation.input_id)))
  var current = invocation.flow
  var destination = invocation.destination
  var value = initial_record.data
  var value_id = invocation.input_id

  while not current.isNil:
    case current.kind
    of fk_top:
      current = current.body
    of fk_ref:
      destination = prepend_continuation(
        current.continuation,
        destination)
      current = resolve_root(plan.roots, current.name)
    of fk_raw:
      value = current.value
      value_id = register_generated_artifact(plan.context, value)
      current = current.continuation
    of fk_it:
      value = current.projector(value)
      value_id = register_generated_artifact(plan.context, value)
      current = current.continuation
    of fk_model:
      suspend_model(
        plan, current, value_id,
        destination)
      return
    of fk_so:
      let child = current.execute(value)
      let child_destination = prepend_continuation(current.continuation,
        destination)
      if child.isNil:
        deliver_destination(plan, child_destination, value_id)
      else:
        enqueue_ready(plan, new_invocation(
          child,
          value_id,
          child_destination))
      return
    of fk_fanout:
      begin_fanout(
        plan, current, value_id,
        destination)
      return
    of fk_lift:
      begin_lift(
        plan, current, value_id,
        destination)
      return

  deliver_destination(plan, destination, value_id)

proc handle_runtime_event[A](
    plan: var WorkPlan[A];
    runtime: ptr CodexRuntime;
    event: GlobalEvent
) =
  plan_assert(plan, event.kind == gek_runtime,
    "non-runtime event passed to runtime handler")
  case event.runtime_kind
  of rev_model_artifact:
    let key = request_id_key(event.request_id)
    plan_assert(plan, plan.model_requests.hasKey(key),
      "unknown model completion")
    let invocation = plan.model_requests[key]
    plan_assert(plan,
      not invocation.flow.isNil and invocation.flow.kind == fk_model,
      "model completion has invalid invocation")
    plan_assert(plan, invocation.output_meta.isSome,
      "model invocation has no output metadata")
    plan_assert(plan, not event.output_materializer.isNil,
      "model completion has no materializer")
    plan_assert(plan, event.output_arguments.len > 0,
      "model completion has no encoded output")
    plan.context.runtime_log(
      "model.output",
      "vecherinka",
      log_fields(
        ("request_id", %(request_id_key(event.request_id))),
        ("tool", %event.output_tool_name),
        ("arguments_bytes", %event.output_arguments.len)))
    let can_ack_tool = event.tool_request_id.isSome and not runtime.isNil and
      runtime.server_requests.hasKey(
        request_id_key(event.tool_request_id.get))
    if event.tool_request_id.isSome and event.output_tool_name != "finish_work":
      if can_ack_tool:
        runtime.accept_tool_response(
          event.tool_request_id.get,
          false,
          @[dynamic_tool_text("unexpected completion tool: " &
            event.output_tool_name)])
        return
      plan_assert(plan, false,
        "unexpected completion tool: " & event.output_tool_name)
      return
    let output_meta = invocation.output_meta.get
    let materialize = cast[ModelMaterializer[A]](event.output_materializer)
    let decoded = try:
      materialize(event.output_kind, LlmOutput(
        tool_name: event.output_tool_name,
        arguments: parseJson(event.output_arguments),
        working_dir: output_meta.artifact_dir))
    except CatchableError as error:
      ModelMaterialization[A](ok: false, error: error.msg)
    if not decoded.ok:
      plan.context.runtime_log(
        "model.reject",
        "vecherinka",
        log_fields(
          ("request_id", %(request_id_key(event.request_id))),
          ("error", %decoded.error)))
      if can_ack_tool:
        runtime.accept_tool_response(
          event.tool_request_id.get,
          false,
          @[dynamic_tool_text("invalid finish_work result: " & decoded.error)])
        return
      plan_assert(plan, false, "invalid model output: " & decoded.error)
      return
    let artifact = decoded.value
    plan_assert(plan,
      event.output_meta.isNone or
        (event.output_meta.get.id == output_meta.id and
         $event.output_meta.get.artifact_dir == $output_meta.artifact_dir),
      "model completion output metadata mismatch")
    if can_ack_tool:
      runtime.accept_tool_response(
        event.tool_request_id.get,
        true,
        @[dynamic_tool_text(event.output_arguments)])
    if event.tool_binding_id.isSome:
      retire_llm_tool_binding(event.tool_binding_id.get)
    plan.model_requests.del(key)
    if plan.context.pending_agent_starts.hasKey(key):
      plan.context.pending_agent_starts.del(key)
    let output_id = register_artifact(plan.context, artifact, output_meta)
    plan.context.runtime_log(
      "model.finish",
      "vecherinka",
      log_fields(
        ("request_id", %(request_id_key(event.request_id))),
        ("output_artifact_id", %output_id)))
    deliver_destination(plan, invocation.destination, output_id)
  of rev_model_error:
    let key = request_id_key(event.request_id)
    plan_assert(plan, plan.model_requests.hasKey(key), "unknown model error")
    plan.model_requests.del(key)
    if plan.context.pending_agent_starts.hasKey(key):
      plan.context.pending_agent_starts.del(key)
    plan.context.runtime_log(
      "model.fail",
      "vecherinka",
      log_fields(
        ("request_id", %(request_id_key(event.request_id))),
        ("error", %event.error_message)))
    plan.failure_message = some(event.error_message)
    plan.failed = true
    plan.finished = true
  of rev_shutdown:
    plan.finished = true

proc handle_global_event[A](
    plan: var WorkPlan[A];
    messenger: var GlobalEventMessenger;
    runtime: ptr CodexRuntime;
    event: GlobalEvent
) =
  ## One main-thread dispatcher handles both transport and Vecherinka events.
  case event.kind
  of gek_runtime:
    handle_runtime_event(plan, runtime, event)
  of gek_ready:
    plan_assert(plan, plan.pending_ready.hasKey(event.ready_id),
      "unknown ready invocation")
    plan.context.runtime_log(
      "ready.consume",
      "vecherinka",
      log_fields(("ready_id", %event.ready_id)))
    let invocation = plan.pending_ready[event.ready_id]
    plan.pending_ready.del(event.ready_id)
    handle_invocation(plan, invocation)
  of gek_create_agent:
    begin_agent_creation(plan, runtime, event)
  of gek_stdout_line, gek_stderr_line, gek_stdout_closed, gek_stderr_closed,
      gek_process_exit, gek_reader_error:
    let event_name = case event.kind
    of gek_stdout_line: "protocol.stdout"
    of gek_stderr_line: "protocol.stderr"
    of gek_stdout_closed: "reader.stdout.close"
    of gek_stderr_closed: "reader.stderr.close"
    of gek_process_exit: "process.exit"
    of gek_reader_error: "reader.error"
    else: "transport.event"
    plan.context.runtime_log(
      event_name,
      "codex",
      if event.kind == gek_stdout_line or event.kind == gek_stderr_line:
        log_fields(("bytes", %event.message.len))
      elif event.kind == gek_reader_error:
        log_fields(("error", %event.message))
      else:
        nil)
    messenger.handle_global_event(runtime, event)
    if event.kind == gek_stdout_line:
      advance_agent_starts(plan, runtime)
    if event.kind == gek_stdout_line and not runtime.isNil and
        runtime.initialization_error.isSome:
      plan.fail_runtime(
        "codex initialization failed: " & runtime.initialization_error.get)
    elif event.kind == gek_stderr_line and not runtime.isNil and
        not runtime.initialized and event.message.strip.startsWith("Error:"):
      plan.fail_runtime("codex app-server startup failed: " & event.message.strip)
    plan.fail_on_process_exit(messenger)
  of gek_shutdown:
    plan.context.runtime_log("run.shutdown", "vecherinka")
    plan.finished = true

proc run_work_plan*[A](
    plan: var WorkPlan[A];
    runtime: ptr CodexRuntime = nil
) =
  if not plan.context.events_open:
    raise newException(ValueError, "global event channel is not open")
  var messenger = new_global_event_messenger()
  while not plan.finished:
    let received = try_recv_global_event(plan.context)
    if received.data_available:
      handle_global_event(plan, messenger, runtime, received.event)
    elif not messenger.process_exited and
        messenger.codex_process_exit_seen(runtime):
      ## Poll process status while channel is idle. Reader EOF events still
      ## arrive separately, so exit is not treated as stream completion.
      handle_global_event(
        plan,
        messenger,
        runtime,
        GlobalEvent(kind: gek_process_exit))
    else:
      sleep(1)

proc execute_flows*[A](
    top_level_flows: seq[Flow[A]];
    input: A;
    submitter: ModelSubmitter[A] = nil;
    transport: LlmTransport[A] = nil;
    runtime: ptr CodexRuntime = nil;
    logger: StructuredLogger = nil
): WorkPlan[A] =
  ## The main thread owns runtime protocol state. A supplied runtime is
  ## borrowed; otherwise this call owns the complete Codex lifecycle.
  let source_root = Path(expandFilename(os.getCurrentDir()))
  let run_dir = create_run_directory(source_root)
  let context = new_runtime_context(
    submitter, transport, run_dir, source_root, logger)
  context.runtime_log(
    "run.start",
    "vecherinka",
    log_fields(
      ("run_dir", %($lastPathPart(run_dir))),
      ("runtime_dir", %($lastPathPart(source_root))),
      ("owns_runtime", %runtime.isNil)))
  var owned_runtime = false
  var active_runtime = runtime
  var readers: CodexReaders
  var readers_started = false
  var plan_initialized = false
  try:
    if active_runtime.isNil:
      active_runtime = init_codex_runtime($context.run_dir)
      owned_runtime = true
    context.codex_runtime = active_runtime
    open_global_events(context)
    start_codex_readers(readers, context, active_runtime)
    readers_started = true
    result = init_work_plan(top_level_flows, context)
    plan_initialized = true
    let input_meta = ArtifactMeta(id: 0, artifact_dir: source_root)
    let input_id = register_artifact(context, input, input_meta)
    enqueue_ready(result, new_invocation(
      result.entry,
      input_id,
      Destination[A](kind: dk_finished)))
    run_work_plan(result, active_runtime)
  finally:
    if plan_initialized:
      context.runtime_log(
        if result.failed: "run.fail" elif result.finished: "run.finish"
        else: "run.abort",
        "vecherinka",
        log_fields(
          ("failed", %result.failed),
          ("finished", %result.finished)))
    else:
      context.runtime_log("run.abort", "vecherinka",
        log_fields(("reason", %"plan initialization failed")))
    if readers_started:
      stop_codex_readers(readers)
    retire_llm_tool_bindings(cast[pointer](context))
    close_global_events(context)
    if owned_runtime:
      deinit_codex_runtime(active_runtime)
      context.codex_runtime = nil

proc execute_flows*[A](top_level_flows: seq[Flow[A]]) =
  ## Compatibility entry point used by the current generated solve wrapper.
  ## Full execution requires a real input and uses the overload above.
  discard init_work_plan(top_level_flows)
