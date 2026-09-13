## Runtime data model and lazy executor for lowered Vecherinka flows.
##
## Included by `vecherinka.nim`. Keep compile-time AST and macro machinery out
## of this fragment.

import std/[sugar, deques, json, options, tables]
import codex_json

type
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
      profile*: ProfileSpec
      prompt*: string
      packer*: pointer
      unpacker*: pointer
      prepare*: proc(input: A): ModelCallSpec[A] {.nimcall.}
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
    parent*: Option[WorkID]
    resume*: Resume[A]

  WorkNode*[A] = ref object
    id*: WorkID
    kind*: WorkKind
    state*: WorkState
    parent*: Option[WorkID]
    input*: Option[A]
    output*: Option[A]
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
    resume*: Resume[A]

  LlmOutput* = object
    ## Structured output passed by fake or real transport. Real Codex parsing
    ## will populate tool_name and arguments later.
    tool_name*: string
    arguments*: JsonNode

  ModelCallSpec*[A] = object
    profile*: ProfileSpec
    prompt*: string
    input*: A
    output_kind*: int
    debug_output*: proc(output_kind: int; output: LlmOutput): A {.nimcall.}
    ## Generated full submit adapter. Erased pointer avoids recursive generic
    ## variant constructor issues; runtime casts only at dispatch boundary.
    submit*: pointer

  LlmCallSpec*[A] = object
    profile*: ProfileSpec
    prompt*: string
    typed_context*: string
    tools*: DynamicToolRegistry
    output_kind*: int
    materialize*: proc(output_kind: int; output: LlmOutput): A {.nimcall.}

  RuntimeEventKind* = enum
    rev_model_artifact,
    rev_model_error,
    rev_shutdown

  RuntimeEvent*[A] = object
    request_id*: RequestId
    kind*: RuntimeEventKind
    ## Keep payload storage uniform. Constructors below assign fields after
    ## allocation; Nim's generic variant constructor crashes for generated A.
    has_artifact*: bool
    artifact*: ref A
    has_message*: bool
    message*: string

  RuntimeContext*[A] = ref object
    events*: Deque[RuntimeEvent[A]]
    submitter*: ModelSubmitter[A]
    transport*: LlmTransport[A]
    next_request_id*: int64

  ModelSubmitter*[A] = proc(
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: ModelCallSpec[A]
  ) {.nimcall.}

  LlmTransport*[A] = proc(
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
  ) {.nimcall.}

  ErasedModelSubmit* = proc(
    context: pointer;
    request_id: RequestId;
    spec: pointer
  ) {.nimcall.}

  WorkPlan*[A] = object
    context*: RuntimeContext[A]
    roots*: Table[string, Flow[A]]
    entry*: Flow[A]
    ready*: Deque[Activation[A]]
    nodes*: Table[WorkID, WorkNode[A]]
    joins*: Table[WorkID, JoinState[A]]
    pending_models*: Table[string, PendingModel[A]]
    next_work_id*: WorkID
    output*: Option[A]
    finished*: bool
    failed*: bool

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
    transport: LlmTransport[A] = nil
): RuntimeContext[A] =
  echo "initializing new runtime context with event queue, transport, and req id"
  new result
  result.events = initDeque[RuntimeEvent[A]]()
  result.submitter = submitter
  result.transport = transport
  result.next_request_id = 0

proc allocate_request_id[A](context: RuntimeContext[A]): RequestId =
  result = RequestId(kind: rid_integer,
    integer_value: context.next_request_id)
  inc context.next_request_id

proc init_work_plan*[A](
    top_level_flows: seq[Flow[A]];
    context: RuntimeContext[A]
): WorkPlan[A] =
  echo "initializing work plan"
  result.context = context
  result.roots = initTable[string, Flow[A]]()
  result.nodes = initTable[WorkID, WorkNode[A]]()
  result.joins = initTable[WorkID, JoinState[A]]()
  result.pending_models = initTable[string, PendingModel[A]]()
  result.ready = initDeque[Activation[A]]()
  result.next_work_id = 1

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

proc new_work_node[A](
    plan: var WorkPlan[A];
    kind: WorkKind;
    parent: Option[WorkID];
    input: Option[A]
): WorkID =
  echo "new_work_node"
  dump kind
  result = plan.next_work_id
  inc plan.next_work_id
  plan.nodes[result] = WorkNode[A](
    id: result,
    kind: kind,
    state: ws_running,
    parent: parent,
    input: input,
    output: none(A),
    request_id: none(RequestId),
    error_message: none(string)
  )

proc fail_plan[A](plan: var WorkPlan[A]; message: string) =
  plan.failed = true
  plan.finished = true
  raise newException(ValueError, message)

proc mark_node_failed[A](
    plan: var WorkPlan[A];
    node_id: WorkID;
    message: string
) =
  if plan.nodes.hasKey(node_id):
    let node = plan.nodes[node_id]
    node.state = ws_failed
    node.error_message = some(message)
  plan.failed = true
  plan.finished = true

proc finalize_join[A](
    plan: var WorkPlan[A];
    join_id: WorkID
)

proc accept_join_result[A](
    plan: var WorkPlan[A];
    join_id: WorkID;
    slot: int;
    value: A
)

proc deliver_resume[A](
    plan: var WorkPlan[A];
    resume: Resume[A];
    value: A
) =
  if resume.isNil:
    fail_plan(plan, "nil resume destination")
    return

  case resume.kind
  of rk_continue:
    addLast(plan.ready, Activation[A](
      flow: resume.flow,
      input: value,
      parent: none(WorkID),
      resume: resume.next
    ))
  of rk_join:
    accept_join_result(plan, resume.join_id, resume.slot, value)
  of rk_finished:
    plan.output = some(value)
    plan.finished = true

proc finish_join[A](
    plan: var WorkPlan[A];
    join_id: WorkID
) =
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

  let output = case join.kind
    of jk_fanout: join.coalesce(values)
    of jk_lift: join.construct(values, join.original)

  if plan.nodes.hasKey(join.id):
    let node = plan.nodes[join.id]
    node.output = some(output)
    node.state = ws_done
  plan.joins.del(join_id)
  deliver_resume(plan, join.resume, output)

proc finalize_join[A](
    plan: var WorkPlan[A];
    join_id: WorkID
) =
  finish_join(plan, join_id)

proc accept_join_result[A](
    plan: var WorkPlan[A];
    join_id: WorkID;
    slot: int;
    value: A
) =
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
  dec join.remaining
  if join.remaining == 0:
    finalize_join(plan, join_id)

proc default_model_submit[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: ModelCallSpec[A]
) =
  echo "default_model_submit"
  discard spec
  var event: RuntimeEvent[A]
  event.kind = rev_model_error
  event.request_id = request_id
  event.message = "no model submitter configured"
  event.has_message = true
  addLast(context.events, event)

proc default_llm_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  ## Default transport is deterministic. It exercises generated output
  ## materialization without opening a Codex process.
  if spec.materialize.isNil:
    var event: RuntimeEvent[A]
    event.kind = rev_model_error
    event.request_id = request_id
    event.message = "LLM spec has no output materializer"
    event.has_message = true
    addLast(context.events, event)
    return
  let output = spec.materialize(
    spec.output_kind,
    LlmOutput(
      tool_name: "debug_return",
      arguments: newJObject()
    )
  )
  var event: RuntimeEvent[A]
  event.kind = rev_model_artifact
  event.request_id = request_id
  new(event.artifact)
  event.artifact[] = output
  event.has_artifact = true
  addLast(context.events, event)

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
    parent: Option[WorkID];
    resume: Resume[A]
) =
  echo "suspend_model"
  let node_id = new_work_node(plan, wk_model, parent, some(input))
  var spec = if flow.prepare.isNil:
    ModelCallSpec[A](
      profile: flow.profile,
      prompt: flow.prompt,
      input: input,
      output_kind: -1,
      debug_output: nil
    )
  else:
    flow.prepare(input)
  let request_id = allocate_request_id(plan.context)
  let pending = PendingModel[A](
    node_id: node_id,
    request_id: request_id,
    resume: prepend_continuation(flow.continuation, resume)
  )
  echo "prepended continuation, added to pending model requests"
  plan.pending_models[request_id_key(request_id)] = pending

  let node = plan.nodes[node_id]
  node.request_id = some(request_id)
  node.state = ws_waiting

  if not spec.submit.isNil:
    let submitter = cast[ErasedModelSubmit](spec.submit)
    submitter(cast[pointer](plan.context), request_id, addr spec)
  else:
    let submitter = if not plan.context.submitter.isNil:
      plan.context.submitter
    else:
      default_model_submit[A]
    submitter(plan.context, request_id, spec)

proc begin_fanout[A](
    plan: var WorkPlan[A];
    flow: Flow[A];
    input: A;
    parent: Option[WorkID];
    resume: Resume[A]
) =
  let join_id = new_work_node(plan, wk_fanout, parent, some(input))
  let join = JoinState[A](
    id: join_id,
    kind: jk_fanout,
    parent: parent,
    remaining: flow.branches.len,
    slots: newSeq[Option[A]](flow.branches.len),
    resume: prepend_continuation(flow.continuation, resume),
    coalesce: flow.coalesce
  )
  plan.joins[join_id] = join

  for index, branch in flow.branches:
    addLast(plan.ready, Activation[A](
      flow: branch,
      input: input,
      parent: some(join_id),
      resume: Resume[A](kind: rk_join, join_id: join_id, slot: index)
    ))

  if flow.branches.len == 0:
    finalize_join(plan, join_id)

proc begin_lift[A](
    plan: var WorkPlan[A];
    flow: Flow[A];
    input: A;
    parent: Option[WorkID];
    resume: Resume[A]
) =
  let works = flow.destructure(input)
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

  let join_id = new_work_node(plan, wk_lift, parent, some(input))
  let join = JoinState[A](
    id: join_id,
    kind: jk_lift,
    parent: parent,
    remaining: works.len,
    slots: newSeq[Option[A]](works.len),
    resume: prepend_continuation(flow.continuation, resume),
    original: input,
    construct: flow.construct
  )
  plan.joins[join_id] = join

  for work in works:
    addLast(plan.ready, Activation[A](
      flow: flow.inner,
      input: work.input,
      parent: some(join_id),
      resume: Resume[A](
        kind: rk_join,
        join_id: join_id,
        slot: work.result_index
      )
    ))

  if works.len == 0:
    finalize_join(plan, join_id)

proc handle_activation*[A](
    plan: var WorkPlan[A];
    activation: Activation[A]
) =
  echo "handle_activation"
  var current = activation.flow
  var value = activation.input

  while not current.isNil:
    dump current.kind
    case current.kind
    of fk_top:
      current = current.body
    of fk_ref:
      current = resolve_root(plan.roots, current.name)
    of fk_raw:
      value = current.value
      current = current.continuation
    of fk_it:
      value = current.projector(value)
      current = current.continuation
    of fk_model:
      suspend_model(plan, current, value, activation.parent, activation.resume)
      return
    of fk_so:
      let child = current.execute(value)
      let child_resume = prepend_continuation(current.continuation,
        activation.resume)
      if child.isNil:
        deliver_resume(plan, child_resume, value)
      else:
        addLast(plan.ready, Activation[A](
          flow: child,
          input: value,
          parent: activation.parent,
          resume: child_resume
        ))
      return
    of fk_fanout:
      begin_fanout(plan, current, value, activation.parent,
        activation.resume)
      return
    of fk_lift:
      begin_lift(plan, current, value, activation.parent,
        activation.resume)
      return

  deliver_resume(plan, activation.resume, value)

proc handle_event[A](
    plan: var WorkPlan[A];
    event: RuntimeEvent[A]
) =
  case event.kind
  of rev_model_artifact:
    let key = request_id_key(event.request_id)
    if not plan.pending_models.hasKey(key):
      fail_plan(plan, "unknown model completion")
      return
    let pending = plan.pending_models[key]
    plan.pending_models.del(key)
    if not plan.nodes.hasKey(pending.node_id):
      fail_plan(plan, "model completion has unknown work node")
      return
    let node = plan.nodes[pending.node_id]
    if not event.has_artifact:
      fail_plan(plan, "model completion has no artifact")
      return
    if event.artifact.isNil:
      fail_plan(plan, "model completion has nil artifact")
      return
    let artifact = event.artifact[]
    node.output = some(artifact)
    node.state = ws_done
    deliver_resume(plan, pending.resume, artifact)
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
    plan.finished = true

proc drain_ready_batch*[A](
    plan: var WorkPlan[A];
    limit: int = 64
) =
  echo "drain_ready_batch"
  var handled = 0
  while not plan.finished and plan.ready.len > 0 and handled < limit:
    let activation = popFirst(plan.ready)
    inc handled
    handle_activation(plan, activation)

proc drain_events*[A](plan: var WorkPlan[A]) =
  echo "drain_events"
  while not plan.finished and plan.context.events.len > 0:
    let event = popFirst(plan.context.events)
    handle_event(plan, event)

proc run_work_plan*[A](plan: var WorkPlan[A]) =
  while not plan.finished:
    echo "while not plan.finished"
    drain_ready_batch(plan)
    drain_events(plan)
    if plan.ready.len == 0 and plan.context.events.len == 0 and
        not plan.finished:
      ## Real submitters are added in a later slice. A missing event here is a
      ## scheduler bug, not permission to recurse or busy-spin.
      fail_plan(plan, "work plan stalled with no ready work or event")

proc execute_flows*[A](
    top_level_flows: seq[Flow[A]];
    input: A;
    submitter: ModelSubmitter[A] = nil;
    transport: LlmTransport[A] = nil
): WorkPlan[A] =
  echo "executing flows"
  let context = new_runtime_context(submitter, transport)
  result = init_work_plan(top_level_flows, context)
  echo "adding activation for input"
  addLast(result.ready, Activation[A](
    flow: result.entry,
    input: input,
    parent: none(WorkID),
    resume: Resume[A](kind: rk_finished)
  ))
  echo "running work plan"
  run_work_plan(result)

proc execute_flows*[A](top_level_flows: seq[Flow[A]]) =
  ## Compatibility entry point used by the current generated solve wrapper.
  ## Full execution requires a real input and uses the overload above.
  discard init_work_plan(top_level_flows)
