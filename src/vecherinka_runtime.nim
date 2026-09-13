## Runtime data model and lazy executor for lowered Vecherinka flows.
##
## Included by `vecherinka.nim`. Keep compile-time AST and macro machinery out
## of this fragment.

import std/[sugar, json, options, tables, posix, strutils, os,
  paths, tempfiles]
import codex_json
import codex_runtime

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
    ## Structured output passed by fake or real transport. Real Codex parsing
    ## will populate tool_name and arguments later.
    tool_name*: string
    arguments*: JsonNode

  ModelMaterialization*[A] = object
    ok*: bool
    value*: A
    error*: string

  ModelMaterializer*[A] = proc(
    output_kind: int;
    output: LlmOutput
  ): ModelMaterialization[A] {.nimcall.}

  LlmToolData* = ref object
    ## Opaque callback state. Runtime context keeps GC ownership.
    context*: pointer
    request_id*: RequestId
    output_kind*: int
    materializer*: pointer

  LlmCallSpec*[A] = object
    profile*: ProfileSpec
    prompt*: string
    materialized_input*: string
    runtime_dir*: Path
    working_dir*: Path
    tools*: DynamicToolRegistry
    output_kind*: int
    materialize*: ModelMaterializer[A]

  RuntimeEventKind* = enum
    rev_model_artifact,
    rev_model_error,
    rev_shutdown

  RuntimeEvent*[A] = object
    request_id*: RequestId
    kind*: RuntimeEventKind
    ## Keep typed artifact construction on the runtime thread. Events carry
    ## only transport output plus the generated materializer.
    has_output*: bool
    output_kind*: int
    output*: LlmOutput
    materialize*: ModelMaterializer[A]
    has_tool_request_id*: bool
    tool_request_id*: RequestId
    has_output_meta*: bool
    output_meta*: ArtifactMeta
    has_message*: bool
    message*: string

  GlobalEventKind* = enum
    gek_runtime,
    gek_ready,
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
    kind*: GlobalEventKind
    message*: string
    request_id*: RequestId
    ready_id*: uint64
    runtime_kind*: RuntimeEventKind
    has_output*: bool
    output_kind*: int
    output_tool_name*: string
    output_arguments*: string
    output_materializer*: pointer
    has_tool_request_id*: bool
    tool_request_id*: RequestId
    has_output_meta*: bool
    output_meta*: ArtifactMeta
    has_message*: bool

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

  RuntimeContext*[A] = ref object
    artifacts*: Table[ArtifactID, ArtifactRecord[A]]
    events*: Channel[GlobalEvent]
    events_open*: bool
    submitter*: ModelSubmitter[A]
    transport*: LlmTransport[A]
    next_request_id*: int64
    ## Common base for runtime-relative Location values. This is the program
    ## working directory, not an individual artifact directory.
    runtime_dir*: Path
    run_dir*: Path
    next_artifact_id*: ArtifactID
    codex_runtime*: ptr CodexRuntime
    llm_tool_data*: seq[LlmToolData]

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
  var global_event = GlobalEvent(
    kind: gek_runtime,
    request_id: event.request_id,
    runtime_kind: event.kind,
    has_output: event.has_output,
    output_kind: event.output_kind,
    output_materializer: cast[pointer](event.materialize),
    has_tool_request_id: event.has_tool_request_id,
    tool_request_id: event.tool_request_id,
    has_output_meta: event.has_output_meta,
    output_meta: event.output_meta,
    has_message: event.has_message,
    message: event.message)
  if event.has_output:
    global_event.output_tool_name = event.output.tool_name
    global_event.output_arguments = $event.output.arguments
  send_global_event(context, global_event)

proc enqueue_llm_output_event*[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    output_kind: int;
    materialize: ModelMaterializer[A];
    tool_context: ToolCallContext
) {.gcsafe.} =
  ## Callback only copies transport data. Typed decoding stays owner-thread.
  {.cast(gcsafe).}:
    var event: RuntimeEvent[A]
    event.kind = rev_model_artifact
    event.request_id = request_id
    event.output_kind = output_kind
    event.output = LlmOutput(
      tool_name: tool_context.params.tool,
      arguments: tool_context.params.arguments)
    event.materialize = materialize
    event.has_output = true
    event.has_tool_request_id = true
    event.tool_request_id = tool_context.request_id
    enqueue_runtime_event(context, event)

proc new_llm_tool_data*(
    context: pointer;
    request_id: RequestId;
    output_kind: int;
    materializer: pointer
): LlmToolData =
  let data = LlmToolData(
    context: context,
    request_id: request_id,
    output_kind: output_kind,
    materializer: materializer)
  data

proc retain_llm_tool_data*[A](context: RuntimeContext[A]; data: LlmToolData) =
  context.llm_tool_data.add(data)

proc release_llm_tool_data*[A](context: RuntimeContext[A]) =
  context.llm_tool_data.setLen(0)

proc recv_global_event*[A](context: RuntimeContext[A]): GlobalEvent =
  context.events.recv()

proc try_recv_global_event*[A](context: RuntimeContext[A]): tuple[data_available: bool, event: GlobalEvent] =
  let received = context.events.tryRecv()
  (data_available: received.dataAvailable, event: received.msg)

proc reader_error_message(operation: string; error_code: cint): string =
  operation & " failed (errno " & $error_code & ")"

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
    send_global_event(events, GlobalEvent(kind: line_kind, message: line))
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
      send_global_event(args.events, GlobalEvent(kind: args.line_kind, message: pending))
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
    process_exited: false)

proc handle_global_event*(
    messenger: var GlobalEventMessenger;
    runtime: ptr CodexRuntime;
    event: GlobalEvent
) =
  ## Main-thread coordinator. Only this path touches CodexRuntime protocol state.
  case event.kind
  of gek_runtime, gek_ready:
    discard
  of gek_stdout_line:
    if runtime.isNil:
      raise newException(ValueError, "stdout event requires CodexRuntime owner")
    discard runtime.accept_json(parseJson(event.message))
  of gek_stderr_line:
    discard
  of gek_stdout_closed:
    messenger.stdout_closed = true
    if messenger.stderr_closed and not runtime.isNil:
      messenger.process_exited = not runtime.is_running()
  of gek_stderr_closed:
    messenger.stderr_closed = true
    if messenger.stdout_closed and not runtime.isNil:
      messenger.process_exited = not runtime.is_running()
  of gek_process_exit:
    messenger.process_exited = true
  of gek_reader_error:
    raise newException(IOError, event.message)
  of gek_shutdown:
    discard

proc minimal*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_minimal)
proc low*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_low)
proc medium*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_medium)
proc high*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_high)
proc xhigh*(model: string): ProfileSpec =
  ProfileSpec(model: model, effort: re_xhigh)

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
    runtime_dir: Path = Path("")
): RuntimeContext[A] =
  echo "runtime: new context"
  dump submitter.isNil
  dump transport.isNil
  new result
  result.artifacts = initTable[ArtifactID, ArtifactRecord[A]]()
  result.events_open = false
  result.submitter = submitter
  result.transport = transport
  result.next_request_id = 0
  result.runtime_dir = if $runtime_dir == "": run_dir else: runtime_dir
  result.run_dir = run_dir
  result.next_artifact_id = 0
  result.codex_runtime = nil
  result.llm_tool_data = @[]

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

proc allocate_request_id[A](context: RuntimeContext[A]): RequestId =
  echo "runtime: allocate request id"
  dump context.next_request_id
  result = RequestId(kind: rid_integer,
    integer_value: context.next_request_id)
  inc context.next_request_id
  dump result

proc init_work_plan*[A](
    top_level_flows: seq[Flow[A]];
    context: RuntimeContext[A]
): WorkPlan[A] =
  echo "runtime: init work plan"
  dump top_level_flows.len
  result.context = context
  result.roots = initTable[string, Flow[A]]()
  result.joins = initTable[JoinID, JoinState]()
  result.join_invocations = initTable[JoinID, Invocation[A]]()
  result.model_requests = initTable[string, Invocation[A]]()
  result.pending_ready = initTable[uint64, Invocation[A]]()
  result.next_ready_id = 0
  result.next_join_id = 1
  result.output = none(ArtifactID)

  for top in top_level_flows:
    if top.isNil or top.kind != fk_top:
      raise newException(ValueError, "top-level flow is not fk_top")
    echo "runtime: register top flow"
    dump top.root
    dump top.entry
    if result.roots.hasKey(top.root):
      raise newException(ValueError, "duplicate root: " & top.root)
    result.roots[top.root] = top.body
    if top.entry:
      if not result.entry.isNil:
        raise newException(ValueError, "multiple entry roots")
      result.entry = top.body

  if result.entry.isNil:
    raise newException(ValueError, "missing entry root")
  echo "runtime: work plan ready"
  dump result.roots.len
  dump result.entry.kind

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
  echo "runtime: fail plan"
  dump message
  plan.failed = true
  plan.finished = true
  raise newException(ValueError, message)

proc new_join_state[A](
    plan: var WorkPlan[A];
    kind: JoinKind;
    slot_count: int
): JoinID =
  if slot_count < 0:
    fail_plan(plan, "join slot count cannot be negative")
    return
  result = plan.next_join_id
  inc plan.next_join_id
  plan.joins[result] = JoinState(
    id: result,
    kind: kind,
    remaining: slot_count,
    slots: newSeq[Option[ArtifactID]](slot_count))

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
  send_global_event(plan.context, GlobalEvent(
    kind: gek_ready,
    ready_id: ready_id))

proc deliver_destination[A](
    plan: var WorkPlan[A];
    destination: Destination[A];
    artifact_id: ArtifactID
) =
  if destination.isNil:
    fail_plan(plan, "nil invocation destination")
    return

  echo "runtime: deliver destination"
  dump destination.kind
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
    echo "runtime: plan finished from destination"

proc finish_join[A](
    plan: var WorkPlan[A];
    join_id: JoinID
) =
  echo "runtime: finish join"
  dump join_id
  if not plan.joins.hasKey(join_id):
    fail_plan(plan, "unknown join")
    return

  if not plan.join_invocations.hasKey(join_id):
    fail_plan(plan, "join has no invocation")
    return

  let state = plan.joins[join_id]
  let invocation = plan.join_invocations[join_id]
  if state.remaining != 0:
    fail_plan(plan, "join finalized before all results arrived")
    return

  var values = newSeq[A](state.slots.len)
  for index, slot in state.slots:
    if slot.isNone:
      fail_plan(plan, "join has missing result slot")
      return
    values[index] = lookup_artifact(plan.context, slot.get).data

  if invocation.flow.isNil:
    fail_plan(plan, "join invocation has no flow")
    return

  var output: A
  case state.kind
  of jk_fanout:
    if invocation.flow.kind != fk_fanout or invocation.flow.coalesce.isNil:
      fail_plan(plan, "fanout join has invalid flow")
      return
    output = invocation.flow.coalesce(values)
  of jk_lift:
    if invocation.flow.kind != fk_lift or invocation.flow.construct.isNil:
      fail_plan(plan, "lift join has invalid flow")
      return
    let original = lookup_artifact(plan.context, invocation.input_id).data
    output = invocation.flow.construct(values, original)

  let destination = invocation.destination
  let output_id = register_generated_artifact(plan.context, output)
  plan.joins.del(join_id)
  plan.join_invocations.del(join_id)
  echo "runtime: join output ready"
  dump state.kind
  dump values.len
  deliver_destination(plan, destination, output_id)

proc accept_join_result[A](
    plan: var WorkPlan[A];
    join_id: JoinID;
    slot: int;
    artifact_id: ArtifactID
) =
  echo "runtime: accept join result"
  dump join_id
  dump slot
  if not plan.joins.hasKey(join_id):
    fail_plan(plan, "unknown join result")
    return

  let state = plan.joins[join_id]
  discard lookup_artifact(plan.context, artifact_id)
  if slot < 0 or slot >= state.slots.len:
    fail_plan(plan, "invalid join slot")
    return
  if state.slots[slot].isSome:
    fail_plan(plan, "duplicate join result")
    return

  state.slots[slot] = some(artifact_id)
  dec state.remaining
  if state.remaining == 0:
    finish_join(plan, join_id)
    return

proc default_model_submit[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    input: A;
    working_dir: Path
) =
  echo "runtime: default model submit (error path)"
  dump request_id
  discard input
  discard working_dir
  var event: RuntimeEvent[A]
  event.kind = rev_model_error
  event.request_id = request_id
  event.message = "no model submitter configured"
  event.has_message = true
  enqueue_runtime_event(context, event)

proc default_llm_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  ## Default transport is deterministic. It exercises generated output
  ## materialization without opening a Codex process.
  echo "runtime: default LLM transport"
  dump request_id
  dump spec.output_kind
  dump spec.tools.len
  if spec.materialize.isNil:
    var event: RuntimeEvent[A]
    event.kind = rev_model_error
    event.request_id = request_id
    event.message = "LLM spec has no output materializer"
    event.has_message = true
    enqueue_runtime_event(context, event)
    return
  let output = LlmOutput(
    tool_name: "debug_return",
    arguments: newJObject()
  )
  var event: RuntimeEvent[A]
  event.kind = rev_model_artifact
  event.request_id = request_id
  event.output_kind = spec.output_kind
  event.output = output
  event.materialize = spec.materialize
  event.has_output = true
  enqueue_runtime_event(context, event)

proc submit_llm*[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  echo "runtime: submit LLM"
  dump request_id
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
  echo "runtime: suspend model"
  let input_record = lookup_artifact(plan.context, input_id)
  let request_id = allocate_request_id(plan.context)
  let output_meta = reserve_artifact_meta(plan.context)
  let invocation = Invocation[A](
    flow: flow,
    input_id: input_id,
    destination: prepend_continuation(flow.continuation, destination),
    output_meta: some(output_meta))
  let key = request_id_key(request_id)
  if plan.model_requests.hasKey(key):
    fail_plan(plan, "duplicate model request ID")
    return
  plan.model_requests[key] = invocation
  echo "runtime: model request in flight"
  dump request_id
  dump plan.model_requests.len

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
  echo "runtime: begin fanout"
  dump flow.branches.len
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
  echo "runtime: begin lift"
  dump works.len
  var seen = newSeq[bool](works.len)
  for work in works:
    if work.result_index < 0 or work.result_index >= works.len:
      fail_plan(plan, "lift result index out of range")
      return
    if seen[work.result_index]:
      fail_plan(plan, "duplicate lift result index")
      return
    seen[work.result_index] = true

  for index in 0 ..< seen.len:
    if not seen[index]:
      fail_plan(plan, "lift result indexes are not contiguous")
      return

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
  echo "runtime: handle invocation"
  dump plan.pending_ready.len
  let initial_record = lookup_artifact(plan.context, invocation.input_id)
  var current = invocation.flow
  var destination = invocation.destination
  var value = initial_record.data
  var value_id = invocation.input_id

  while not current.isNil:
    dump current.kind
    case current.kind
    of fk_top:
      echo "runtime: enter top body"
      current = current.body
    of fk_ref:
      echo "runtime: resolve ref"
      dump current.name
      destination = prepend_continuation(
        current.continuation,
        destination)
      current = resolve_root(plan.roots, current.name)
    of fk_raw:
      echo "runtime: raw value"
      value = current.value
      value_id = register_generated_artifact(plan.context, value)
      current = current.continuation
    of fk_it:
      echo "runtime: apply projector"
      value = current.projector(value)
      value_id = register_generated_artifact(plan.context, value)
      current = current.continuation
    of fk_model:
      suspend_model(
        plan, current, value_id,
        destination)
      return
    of fk_so:
      echo "runtime: execute dynamic flow"
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
      echo "runtime: suspend fanout"
      begin_fanout(
        plan, current, value_id,
        destination)
      return
    of fk_lift:
      echo "runtime: suspend lift"
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
  echo "runtime: handle event"
  dump event.runtime_kind
  dump event.request_id
  case event.runtime_kind
  of rev_model_artifact:
    let key = request_id_key(event.request_id)
    if not plan.model_requests.hasKey(key):
      fail_plan(plan, "unknown model completion")
      return
    let invocation = plan.model_requests[key]
    if invocation.flow.isNil or invocation.flow.kind != fk_model:
      fail_plan(plan, "model completion has invalid invocation")
      return
    if invocation.output_meta.isNone:
      fail_plan(plan, "model invocation has no output metadata")
      return
    if not event.has_output:
      fail_plan(plan, "model completion has no output")
      return
    if event.output_materializer.isNil:
      fail_plan(plan, "model completion has no materializer")
      return
    if event.output_arguments.len == 0:
      fail_plan(plan, "model completion has no encoded output")
      return
    let can_ack_tool = event.has_tool_request_id and not runtime.isNil and
      runtime.server_requests.hasKey(request_id_key(event.tool_request_id))
    if event.has_tool_request_id and event.output_tool_name != "finish_work":
      if can_ack_tool:
        runtime.accept_tool_response(
          event.tool_request_id,
          false,
          @[dynamic_tool_text("unexpected completion tool: " &
            event.output_tool_name)])
        return
      fail_plan(plan, "unexpected completion tool: " & event.output_tool_name)
      return
    let materialize = cast[ModelMaterializer[A]](event.output_materializer)
    var decoded: ModelMaterialization[A]
    try:
      decoded = materialize(event.output_kind, LlmOutput(
        tool_name: event.output_tool_name,
        arguments: parseJson(event.output_arguments)))
    except CatchableError as error:
      decoded.ok = false
      decoded.error = error.msg
    if not decoded.ok:
      if can_ack_tool:
        runtime.accept_tool_response(
          event.tool_request_id,
          false,
          @[dynamic_tool_text("invalid finish_work result: " & decoded.error)])
        return
      fail_plan(plan, "invalid model output: " & decoded.error)
      return
    let artifact = decoded.value
    let output_meta = invocation.output_meta.get
    if event.has_output_meta and
        (event.output_meta.id != output_meta.id or
         $event.output_meta.artifact_dir != $output_meta.artifact_dir):
      fail_plan(plan, "model completion output metadata mismatch")
      return
    if can_ack_tool:
      runtime.accept_tool_response(
        event.tool_request_id,
        true,
        @[dynamic_tool_text(event.output_arguments)])
    plan.model_requests.del(key)
    let output_id = register_artifact(plan.context, artifact, output_meta)
    echo "runtime: model artifact accepted"
    deliver_destination(plan, invocation.destination, output_id)
  of rev_model_error:
    let key = request_id_key(event.request_id)
    if not plan.model_requests.hasKey(key):
      fail_plan(plan, "unknown model error")
      return
    plan.model_requests.del(key)
    plan.failed = true
    plan.finished = true
  of rev_shutdown:
    echo "runtime: shutdown event"
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
    if not plan.pending_ready.hasKey(event.ready_id):
      fail_plan(plan, "unknown ready invocation")
      return
    let invocation = plan.pending_ready[event.ready_id]
    plan.pending_ready.del(event.ready_id)
    handle_invocation(plan, invocation)
  of gek_stdout_line, gek_stderr_line, gek_stdout_closed, gek_stderr_closed,
      gek_process_exit, gek_reader_error:
    messenger.handle_global_event(runtime, event)
  of gek_shutdown:
    plan.finished = true

proc run_work_plan*[A](
    plan: var WorkPlan[A];
    runtime: ptr CodexRuntime = nil
) =
  if not plan.context.events_open:
    raise newException(ValueError, "global event channel is not open")
  var messenger = new_global_event_messenger()
  while not plan.finished:
    let event = recv_global_event(plan.context)
    handle_global_event(plan, messenger, runtime, event)

proc execute_flows*[A](
    top_level_flows: seq[Flow[A]];
    input: A;
    submitter: ModelSubmitter[A] = nil;
    transport: LlmTransport[A] = nil;
    runtime: ptr CodexRuntime = nil
): WorkPlan[A] =
  ## The main thread owns runtime protocol state. A supplied runtime is
  ## borrowed; otherwise this call owns the complete Codex lifecycle.
  echo "runtime: execute flows"
  dump top_level_flows.len
  let source_root = Path(expandFilename(os.getCurrentDir()))
  let run_dir = create_run_directory(source_root)
  let context = new_runtime_context(
    submitter, transport, run_dir, source_root)
  var owned_runtime = false
  var active_runtime = runtime
  var readers: CodexReaders
  var readers_started = false
  try:
    if active_runtime.isNil:
      active_runtime = init_codex_runtime($context.run_dir)
      owned_runtime = true
    context.codex_runtime = active_runtime
    open_global_events(context)
    start_codex_readers(readers, context, active_runtime)
    readers_started = true
    result = init_work_plan(top_level_flows, context)
    let input_meta = ArtifactMeta(id: 0, artifact_dir: source_root)
    let input_id = register_artifact(context, input, input_meta)
    echo "runtime: enqueue entry invocation"
    dump result.entry.kind
    enqueue_ready(result, new_invocation(
      result.entry,
      input_id,
      Destination[A](kind: dk_finished)))
    echo "runtime: run work plan"
    run_work_plan(result, active_runtime)
    echo "runtime: execution complete"
    dump result.finished
    dump result.failed
    dump result.joins.len
  finally:
    if readers_started:
      stop_codex_readers(readers)
    close_global_events(context)
    release_llm_tool_data(context)
    if owned_runtime:
      deinit_codex_runtime(active_runtime)
      context.codex_runtime = nil

proc execute_flows*[A](top_level_flows: seq[Flow[A]]) =
  ## Compatibility entry point used by the current generated solve wrapper.
  ## Full execution requires a real input and uses the overload above.
  discard init_work_plan(top_level_flows)
