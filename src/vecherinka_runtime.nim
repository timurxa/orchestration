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

  PendingAgentStart* = object
    agent_id*: AgentId
    artifact_meta*: ArtifactMeta

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
        input_meta: ArtifactMeta;
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

  WorkID* = uint64

  WorkState* = enum
    ws_waiting,
    ws_running,
    ws_done,
    ws_failed,
    ws_cancelled

  WorkKind* = enum
    wk_model,
    wk_fanout,
    wk_lift,
    wk_so

  ResumeKind* = enum
    rk_continue,
    rk_join,
    rk_finished

  Resume*[A] = ref object
    case kind*: ResumeKind
    of rk_continue:
      flow*: Flow[A]
      next*: Resume[A]
    of rk_join:
      join_id*: WorkID
      slot*: int
    of rk_finished:
      discard

  Activation*[A] = object
    flow*: Flow[A]
    input*: A
    artifact_meta*: ArtifactMeta
    parent*: Option[WorkID]
    resume*: Resume[A]

  WorkNode*[A] = ref object
    id*: WorkID
    kind*: WorkKind
    state*: WorkState
    input*: Option[A]
    input_meta*: Option[ArtifactMeta]
    output*: Option[A]
    output_meta*: Option[ArtifactMeta]
    request_id*: Option[RequestId]
    error_message*: Option[string]

  JoinKind* = enum
    jk_fanout,
    jk_lift

  JoinState*[A] = ref object
    id*: WorkID
    parent*: Option[WorkID]
    remaining*: int
    slots*: seq[Option[A]]
    slot_meta*: seq[Option[ArtifactMeta]]
    original_meta*: ArtifactMeta
    resume*: Resume[A]
    case kind*: JoinKind
    of jk_fanout:
      coalesce*: proc(values: seq[A]): A {.nimcall.}
    of jk_lift:
      original*: A
      construct*: proc(results: seq[A]; input: A): A {.nimcall.}

  PendingModel*[A] = ref object
    node_id*: WorkID
    request_id*: RequestId
    input_meta*: ArtifactMeta
    output_meta*: Option[ArtifactMeta]
    resume*: Resume[A]

  LlmOutput* = object
    ## Structured output passed by fake or real transport. Real Codex parsing
    ## will populate tool_name and arguments later.
    tool_name*: string
    arguments*: JsonNode

  ModelMaterializer*[A] = proc(
    output_kind: int;
    output: LlmOutput
  ): A {.nimcall.}

  LlmCallSpec*[A] = object
    profile*: ProfileSpec
    prompt*: string
    typed_context*: string
    input_meta*: ArtifactMeta
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
    pending_agent_starts*: Table[string, PendingAgentStart]

  ModelSubmitter*[A] = proc(
    context: RuntimeContext[A];
    request_id: RequestId;
    input: A;
    input_meta: ArtifactMeta;
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
    pending_ready*: Table[uint64, Activation[A]]
    next_ready_id*: uint64
    nodes*: Table[WorkID, WorkNode[A]]
    joins*: Table[WorkID, JoinState[A]]
    pending_models*: Table[string, PendingModel[A]]
    next_work_id*: WorkID
    output*: Option[A]
    output_meta*: Option[ArtifactMeta]
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
    has_output_meta: event.has_output_meta,
    output_meta: event.output_meta,
    has_message: event.has_message,
    message: event.message)
  if event.has_output:
    global_event.output_tool_name = event.output.tool_name
    global_event.output_arguments = $event.output.arguments
  send_global_event(context, global_event)

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
    parent: Resume[A]
): Resume[A] =
  if flow.isNil:
    return parent
  Resume[A](kind: rk_continue, flow: flow, next: parent)

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
  result.events_open = false
  result.submitter = submitter
  result.transport = transport
  result.next_request_id = 0
  result.runtime_dir = if $runtime_dir == "": run_dir else: runtime_dir
  result.run_dir = run_dir
  result.next_artifact_id = 0
  result.codex_runtime = nil
  result.pending_agent_starts = initTable[string, PendingAgentStart]()

proc create_run_directory*(source_root: Path): Path =
  ## Keep run state in a unique child of the program working directory.
  if not dirExists($source_root):
    raise newException(ValueError, "source root is not a directory: " &
      $source_root)
  Path(createTempDir("run-", "", $source_root))

proc allocate_artifact_meta*[A](context: RuntimeContext[A]): ArtifactMeta =
  if $context.run_dir == "":
    raise newException(ValueError, "runtime context has no run directory")
  inc context.next_artifact_id
  result = ArtifactMeta(
    id: context.next_artifact_id,
    artifact_dir: context.run_dir /
      Path("artifact-" & $context.next_artifact_id))
  createDir($result.artifact_dir)

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
  result.nodes = initTable[WorkID, WorkNode[A]]()
  result.joins = initTable[WorkID, JoinState[A]]()
  result.pending_models = initTable[string, PendingModel[A]]()
  result.pending_ready = initTable[uint64, Activation[A]]()
  result.next_ready_id = 0
  result.next_work_id = 1
  result.output_meta = none(ArtifactMeta)

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

proc new_work_node[A](
    plan: var WorkPlan[A];
    kind: WorkKind;
    input: Option[A];
    artifact_meta: ArtifactMeta
): WorkID =
  echo "runtime: new work node"
  dump kind
  dump input.isSome
  result = plan.next_work_id
  inc plan.next_work_id
  plan.nodes[result] = WorkNode[A](
    id: result,
    kind: kind,
    state: ws_running,
    input: input,
    input_meta: if input.isSome: some(artifact_meta)
                else: none(ArtifactMeta),
    output: none(A),
    output_meta: none(ArtifactMeta),
    request_id: none(RequestId),
    error_message: none(string)
  )

proc fail_plan[A](plan: var WorkPlan[A]; message: string) =
  echo "runtime: fail plan"
  dump message
  plan.failed = true
  plan.finished = true
  raise newException(ValueError, message)

proc mark_node_failed[A](
    plan: var WorkPlan[A];
    node_id: WorkID;
    message: string
) =
  echo "runtime: mark node failed"
  dump node_id
  dump message
  if plan.nodes.hasKey(node_id):
    let node = plan.nodes[node_id]
    node.state = ws_failed
    node.error_message = some(message)
  plan.failed = true
  plan.finished = true

proc accept_join_result[A](
    plan: var WorkPlan[A];
    join_id: WorkID;
    slot: int;
    value: A;
    artifact_meta: ArtifactMeta
)

proc enqueue_ready[A](
    plan: var WorkPlan[A];
    activation: Activation[A]
) =
  ## Typed activation stays owner-thread state; channel carries only its ID.
  inc plan.next_ready_id
  let ready_id = plan.next_ready_id
  plan.pending_ready[ready_id] = activation
  send_global_event(plan.context, GlobalEvent(
    kind: gek_ready,
    ready_id: ready_id))

proc deliver_resume[A](
    plan: var WorkPlan[A];
    resume: Resume[A];
    value: A;
    artifact_meta: ArtifactMeta
) =
  if resume.isNil:
    fail_plan(plan, "nil resume destination")
    return

  echo "runtime: deliver resume"
  dump resume.kind
  case resume.kind
  of rk_continue:
    enqueue_ready(plan, Activation[A](
      flow: resume.flow,
      input: value,
      artifact_meta: artifact_meta,
      parent: none(WorkID),
      resume: resume.next
    ))
  of rk_join:
    accept_join_result(plan, resume.join_id, resume.slot, value, artifact_meta)
  of rk_finished:
    plan.output = some(value)
    plan.output_meta = some(artifact_meta)
    plan.finished = true
    echo "runtime: plan finished from resume"

proc finish_join[A](
    plan: var WorkPlan[A];
    join_id: WorkID
) =
  echo "runtime: finish join"
  dump join_id
  if not plan.joins.hasKey(join_id):
    fail_plan(plan, "unknown join")
    return

  let join = plan.joins[join_id]
  if join.remaining != 0:
    fail_plan(plan, "join finalized before all results arrived")
    return

  var values = newSeq[A](join.slots.len)
  for index, slot in join.slots:
    if slot.isNone:
      fail_plan(plan, "join has missing result slot")
      return
    values[index] = slot.get

  let artifact_meta = allocate_artifact_meta(plan.context)
  let output = case join.kind
    of jk_fanout: join.coalesce(values)
    of jk_lift: join.construct(values, join.original)

  if plan.nodes.hasKey(join.id):
    let node = plan.nodes[join.id]
    node.output = some(output)
    node.output_meta = some(artifact_meta)
    node.state = ws_done
  plan.joins.del(join_id)
  echo "runtime: join output ready"
  dump join.kind
  dump values.len
  deliver_resume(plan, join.resume, output, artifact_meta)

proc accept_join_result[A](
    plan: var WorkPlan[A];
    join_id: WorkID;
    slot: int;
    value: A;
    artifact_meta: ArtifactMeta
) =
  echo "runtime: accept join result"
  dump join_id
  dump slot
  if not plan.joins.hasKey(join_id):
    fail_plan(plan, "unknown join result")
    return

  let join = plan.joins[join_id]
  if slot < 0 or slot >= join.slots.len:
    fail_plan(plan, "invalid join slot")
    return
  if join.slots[slot].isSome:
    fail_plan(plan, "duplicate join result")
    return

  join.slots[slot] = some(value)
  join.slot_meta[slot] = some(artifact_meta)
  dec join.remaining
  if join.remaining == 0:
    finish_join(plan, join_id)

proc default_model_submit[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    input: A;
    input_meta: ArtifactMeta;
    working_dir: Path
) =
  echo "runtime: default model submit (error path)"
  dump request_id
  discard input
  discard input_meta
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
  dump spec.typed_context
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

proc debug_tool_registry*(input_type, output_type: string): DynamicToolRegistry =
  ## Generated submit adapters provide concrete type names. Keep registry
  ## construction centralized until real tool callbacks are wired.
  result.add(DynamicTool(
    name: "return_" & output_type,
    description: "Return value of type " & output_type &
      " for input " & input_type,
    input_schema: newJObject(),
    data: nil,
    callback: nil
  ))

proc default_debug_value*[A](): A =
  default(A)

proc suspend_model[A](
    plan: var WorkPlan[A];
    flow: Flow[A];
    input: A;
    artifact_meta: ArtifactMeta;
    resume: Resume[A]
) =
  echo "runtime: suspend model"
  let node_id = new_work_node(
    plan, wk_model, some(input), artifact_meta)
  let request_id = allocate_request_id(plan.context)
  let output_meta = allocate_artifact_meta(plan.context)
  let pending = PendingModel[A](
    node_id: node_id,
    request_id: request_id,
    input_meta: artifact_meta,
    output_meta: some(output_meta),
    resume: prepend_continuation(flow.continuation, resume)
  )
  echo "runtime: model pending"
  dump node_id
  dump request_id
  dump plan.pending_models.len
  plan.pending_models[request_id_key(request_id)] = pending

  let node = plan.nodes[node_id]
  node.request_id = some(request_id)
  node.state = ws_waiting

  if not flow.submit.isNil:
    flow.submit(
      plan.context, request_id, input, artifact_meta,
      output_meta.artifact_dir)
  else:
    let submitter = if not plan.context.submitter.isNil:
      plan.context.submitter
    else:
      default_model_submit[A]
    submitter(
      plan.context, request_id, input, artifact_meta,
      output_meta.artifact_dir)

proc begin_fanout[A](
    plan: var WorkPlan[A];
    flow: Flow[A];
    input: A;
    artifact_meta: ArtifactMeta;
    parent: Option[WorkID];
    resume: Resume[A]
) =
  echo "runtime: begin fanout"
  dump flow.branches.len
  dump parent
  let join_id = new_work_node(
    plan, wk_fanout, some(input), artifact_meta)
  let join = JoinState[A](
    id: join_id,
    kind: jk_fanout,
    parent: parent,
    remaining: flow.branches.len,
    slots: newSeq[Option[A]](flow.branches.len),
    slot_meta: newSeq[Option[ArtifactMeta]](flow.branches.len),
    original_meta: artifact_meta,
    resume: prepend_continuation(flow.continuation, resume),
    coalesce: flow.coalesce
  )
  plan.joins[join_id] = join

  for index, branch in flow.branches:
    enqueue_ready(plan, Activation[A](
      flow: branch,
      input: input,
      artifact_meta: artifact_meta,
      parent: some(join_id),
      resume: Resume[A](kind: rk_join, join_id: join_id, slot: index)
    ))

  if flow.branches.len == 0:
    finish_join(plan, join_id)

proc begin_lift[A](
    plan: var WorkPlan[A];
    flow: Flow[A];
    input: A;
    artifact_meta: ArtifactMeta;
    parent: Option[WorkID];
    resume: Resume[A]
) =
  let works = flow.destructure(input)
  echo "runtime: begin lift"
  dump works.len
  dump parent
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

  let join_id = new_work_node(
    plan, wk_lift, some(input), artifact_meta)
  let join = JoinState[A](
    id: join_id,
    kind: jk_lift,
    parent: parent,
    remaining: works.len,
    slots: newSeq[Option[A]](works.len),
    slot_meta: newSeq[Option[ArtifactMeta]](works.len),
    original_meta: artifact_meta,
    resume: prepend_continuation(flow.continuation, resume),
    original: input,
    construct: flow.construct
  )
  plan.joins[join_id] = join

  for work in works:
    enqueue_ready(plan, Activation[A](
      flow: flow.inner,
      input: work.input,
      artifact_meta: artifact_meta,
      parent: some(join_id),
      resume: Resume[A](
        kind: rk_join,
        join_id: join_id,
        slot: work.result_index
      )
    ))

  if works.len == 0:
    finish_join(plan, join_id)

proc handle_activation*[A](
    plan: var WorkPlan[A];
    activation: Activation[A]
) =
  echo "runtime: handle activation"
  dump plan.pending_ready.len
  dump activation.parent
  var current = activation.flow
  var value = activation.input

  while not current.isNil:
    dump current.kind
    case current.kind
    of fk_top:
      echo "runtime: enter top body"
      current = current.body
    of fk_ref:
      echo "runtime: resolve ref"
      dump current.name
      current = resolve_root(plan.roots, current.name)
    of fk_raw:
      echo "runtime: raw value"
      value = current.value
      current = current.continuation
    of fk_it:
      echo "runtime: apply projector"
      value = current.projector(value)
      current = current.continuation
    of fk_model:
      suspend_model(
        plan, current, value, activation.artifact_meta,
        activation.resume)
      return
    of fk_so:
      echo "runtime: execute dynamic flow"
      let child = current.execute(value)
      let child_resume = prepend_continuation(current.continuation,
        activation.resume)
      if child.isNil:
        deliver_resume(plan, child_resume, value, activation.artifact_meta)
      else:
        enqueue_ready(plan, Activation[A](
          flow: child,
          input: value,
          artifact_meta: activation.artifact_meta,
          parent: activation.parent,
          resume: child_resume
        ))
      return
    of fk_fanout:
      echo "runtime: suspend fanout"
      begin_fanout(
        plan, current, value, activation.artifact_meta,
        activation.parent, activation.resume)
      return
    of fk_lift:
      echo "runtime: suspend lift"
      begin_lift(
        plan, current, value, activation.artifact_meta,
        activation.parent, activation.resume)
      return

  deliver_resume(plan, activation.resume, value, activation.artifact_meta)

proc handle_runtime_event[A](
    plan: var WorkPlan[A];
    event: GlobalEvent
) =
  echo "runtime: handle event"
  dump event.runtime_kind
  dump event.request_id
  case event.runtime_kind
  of rev_model_artifact:
    let key = request_id_key(event.request_id)
    if not plan.pending_models.hasKey(key):
      fail_plan(plan, "unknown model completion")
      return
    let pending = plan.pending_models[key]
    dump pending.node_id
    plan.pending_models.del(key)
    if not plan.nodes.hasKey(pending.node_id):
      fail_plan(plan, "model completion has unknown work node")
      return
    let node = plan.nodes[pending.node_id]
    if not event.has_output:
      fail_plan(plan, "model completion has no output")
      return
    if event.output_materializer.isNil:
      fail_plan(plan, "model completion has no materializer")
      return
    if event.output_arguments.len == 0:
      fail_plan(plan, "model completion has no encoded output")
      return
    let materialize = cast[ModelMaterializer[A]](event.output_materializer)
    let artifact = materialize(event.output_kind, LlmOutput(
      tool_name: event.output_tool_name,
      arguments: parseJson(event.output_arguments)))
    if not pending.output_meta.isSome:
      fail_plan(plan, "model completion has no output metadata")
      return
    let output_meta = pending.output_meta.get
    if event.has_output_meta and
        (event.output_meta.id != output_meta.id or
         $event.output_meta.artifact_dir != $output_meta.artifact_dir):
      fail_plan(plan, "model completion output metadata mismatch")
      return
    node.output = some(artifact)
    node.output_meta = some(output_meta)
    node.state = ws_done
    echo "runtime: model artifact accepted"
    deliver_resume(plan, pending.resume, artifact, output_meta)
  of rev_model_error:
    let key = request_id_key(event.request_id)
    if not plan.pending_models.hasKey(key):
      fail_plan(plan, "unknown model error")
      return
    let pending = plan.pending_models[key]
    plan.pending_models.del(key)
    if not event.has_message:
      mark_node_failed(plan, pending.node_id, "model error has no message")
    else:
      mark_node_failed(plan, pending.node_id, event.message)
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
    handle_runtime_event(plan, event)
  of gek_ready:
    if not plan.pending_ready.hasKey(event.ready_id):
      fail_plan(plan, "unknown ready activation")
      return
    let activation = plan.pending_ready[event.ready_id]
    plan.pending_ready.del(event.ready_id)
    handle_activation(plan, activation)
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
    echo "runtime: enqueue entry activation"
    dump result.entry.kind
    enqueue_ready(result, Activation[A](
      flow: result.entry,
      input: input,
      artifact_meta: ArtifactMeta(id: 0, artifact_dir: source_root),
      parent: none(WorkID),
      resume: Resume[A](kind: rk_finished)
    ))
    echo "runtime: run work plan"
    run_work_plan(result, active_runtime)
    echo "runtime: execution complete"
    dump result.finished
    dump result.failed
    dump result.nodes.len
  finally:
    if readers_started:
      stop_codex_readers(readers)
    close_global_events(context)
    if owned_runtime:
      deinit_codex_runtime(active_runtime)
      context.codex_runtime = nil

proc execute_flows*[A](top_level_flows: seq[Flow[A]]) =
  ## Compatibility entry point used by the current generated solve wrapper.
  ## Full execution requires a real input and uses the overload above.
  discard init_work_plan(top_level_flows)
