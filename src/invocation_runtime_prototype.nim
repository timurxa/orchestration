## Focused prototype for an Invocation-owned lazy runtime.
##
## Flow owns immutable computational code and its local continuation.
## Invocation owns suspended control. JoinState owns aggregate artifact data.

import std/[options, tables]

type
  ArtifactID = uint64
  RequestID = uint64
  InvocationID = uint64
  JoinID = uint64

  FlowKind = enum
    fk_raw,
    fk_it,
    fk_model,
    fk_so,
    fk_fanout,
    fk_lift

  ModelSubmitter[A] = proc(
    request_id: RequestID;
    input_id: ArtifactID;
    input: A;
    output_id: ArtifactID
  ) {.nimcall.}

  Flow[A] = ref object
    ## Flow is code plus local lexical continuation. Runtime never mutates it.
    continuation: Flow[A]
    case kind: FlowKind
    of fk_raw:
      value: A
    of fk_it:
      projector: proc(input: A): A {.nimcall.}
    of fk_model:
      submit: ModelSubmitter[A]
    of fk_so:
      execute: proc(input: A): Flow[A] {.nimcall.}
    of fk_fanout:
      branches: seq[Flow[A]]
      coalesce: proc(values: seq[A]): A {.nimcall.}
    of fk_lift:
      inner: Flow[A]
      destructure: proc(input: A):
        seq[tuple[result_index: int, input: A]] {.nimcall.}
      construct: proc(results: seq[A]; input: A): A {.nimcall.}

  ReturnTargetKind = enum
    rt_continue,
    rt_join,
    rt_finished

  ReturnTarget[A] = ref object
    ## Nonlocal return address. Only dynamic child calls need rt_continue:
    ## model and join owners retain their current Flow while suspended.
    case kind: ReturnTargetKind
    of rt_continue:
      flow: Flow[A]
      next: ReturnTarget[A]
    of rt_join:
      join_id: JoinID
      slot: int
    of rt_finished:
      discard

  InvocationPhase = enum
    ip_ready,
    ip_model_waiting,
    ip_join_waiting

  Invocation[A] = ref object
    ## Single owner for live execution control.
    id: InvocationID
    flow: Flow[A]
    input_id: ArtifactID
    return_to: ReturnTarget[A]
    case phase: InvocationPhase
    of ip_ready:
      discard
    of ip_model_waiting:
      request_id: RequestID
      reserved_output_id: ArtifactID
    of ip_join_waiting:
      join_id: JoinID

  JoinKind = enum
    jk_fanout,
    jk_lift

  JoinState[A] = ref object
    ## Data only. Flow callbacks and local continuation stay on owner.flow.
    id: JoinID
    owner_invocation_id: InvocationID
    kind: JoinKind
    remaining: int
    slots: seq[Option[ArtifactID]]

  JoinStore[A] = object
    states: Table[JoinID, JoinState[A]]

  InvocationRuntime[A] = ref object
    artifacts: Table[ArtifactID, A]
    invocations: Table[InvocationID, Invocation[A]]
    ready: seq[InvocationID]
    ready_head: int
    request_to_invocation: Table[RequestID, InvocationID]
    joins: JoinStore[A]
    submitter: ModelSubmitter[A]
    next_artifact_id: ArtifactID
    next_invocation_id: InvocationID
    next_request_id: RequestID
    next_join_id: JoinID
    output: Option[ArtifactID]
    finished: bool
    failed: bool

proc raw_flow[A](value: A; continuation: Flow[A] = nil): Flow[A] {.nimcall.} =
  Flow[A](kind: fk_raw, continuation: continuation, value: value)

proc it_flow[A](
    projector: proc(input: A): A {.nimcall.};
    continuation: Flow[A] = nil
): Flow[A] {.nimcall.} =
  Flow[A](kind: fk_it, continuation: continuation, projector: projector)

proc model_flow[A](
    submitter: ModelSubmitter[A] = nil;
    continuation: Flow[A] = nil
): Flow[A] {.nimcall.} =
  Flow[A](kind: fk_model, continuation: continuation, submit: submitter)

proc so_flow[A](
    execute: proc(input: A): Flow[A] {.nimcall.};
    continuation: Flow[A] = nil
): Flow[A] {.nimcall.} =
  Flow[A](kind: fk_so, continuation: continuation, execute: execute)

proc fanout_flow[A](
    branches: seq[Flow[A]];
    coalesce: proc(values: seq[A]): A {.nimcall.};
    continuation: Flow[A] = nil
): Flow[A] {.nimcall.} =
  Flow[A](
    kind: fk_fanout,
    continuation: continuation,
    branches: branches,
    coalesce: coalesce)

proc lift_flow[A](
    inner: Flow[A];
    destructure: proc(input: A):
      seq[tuple[result_index: int, input: A]] {.nimcall.};
    construct: proc(results: seq[A]; input: A): A {.nimcall.};
    continuation: Flow[A] = nil
): Flow[A] {.nimcall.} =
  Flow[A](
    kind: fk_lift,
    continuation: continuation,
    inner: inner,
    destructure: destructure,
    construct: construct)

proc finished_target[A](): ReturnTarget[A] {.nimcall.} =
  ReturnTarget[A](kind: rt_finished)

proc join_target[A](join_id: JoinID; slot: int): ReturnTarget[A] {.nimcall.} =
  ReturnTarget[A](kind: rt_join, join_id: join_id, slot: slot)

proc prepend_local[A](
    flow: Flow[A];
    parent: ReturnTarget[A]
): ReturnTarget[A] {.nimcall.} =
  if flow.isNil:
    return parent
  ReturnTarget[A](kind: rt_continue, flow: flow, next: parent)

proc new_runtime[A](
    submitter: ModelSubmitter[A] = nil
): InvocationRuntime[A] {.nimcall.} =
  new result
  result.artifacts = initTable[ArtifactID, A]()
  result.invocations = initTable[InvocationID, Invocation[A]]()
  result.request_to_invocation = initTable[RequestID, InvocationID]()
  result.joins.states = initTable[JoinID, JoinState[A]]()
  result.submitter = submitter
  result.ready = @[]
  result.ready_head = 0
  result.next_artifact_id = 0
  result.next_invocation_id = 0
  result.next_request_id = 0
  result.next_join_id = 0
  result.output = none(ArtifactID)

proc lookup_artifact[A](
    runtime: InvocationRuntime[A];
    artifact_id: ArtifactID
): A {.nimcall.} =
  if not runtime.artifacts.hasKey(artifact_id):
    raise newException(ValueError, "unknown artifact")
  runtime.artifacts[artifact_id]

proc register_artifact[A](
    runtime: InvocationRuntime[A];
    value: A
): ArtifactID {.nimcall.} =
  inc runtime.next_artifact_id
  result = runtime.next_artifact_id
  runtime.artifacts[result] = value

proc reserve_artifact_id[A](
    runtime: InvocationRuntime[A]
): ArtifactID {.nimcall.} =
  inc runtime.next_artifact_id
  runtime.next_artifact_id

proc register_artifact_at[A](
    runtime: InvocationRuntime[A];
    artifact_id: ArtifactID;
    value: A
) {.nimcall.} =
  if runtime.artifacts.hasKey(artifact_id):
    raise newException(ValueError, "artifact already registered")
  runtime.artifacts[artifact_id] = value

proc new_invocation[A](
    runtime: InvocationRuntime[A];
    flow: Flow[A];
    input_id: ArtifactID;
    return_to: ReturnTarget[A]
): InvocationID {.nimcall.} =
  discard runtime.lookup_artifact(input_id)
  inc runtime.next_invocation_id
  result = runtime.next_invocation_id
  runtime.invocations[result] = Invocation[A](
    id: result,
    flow: flow,
    input_id: input_id,
    return_to: return_to,
    phase: ip_ready)

proc enqueue[A](
    runtime: InvocationRuntime[A];
    invocation_id: InvocationID
) {.nimcall.} =
  if not runtime.invocations.hasKey(invocation_id):
    raise newException(ValueError, "unknown invocation")
  runtime.ready.add(invocation_id)

proc create_join[A](
    runtime: InvocationRuntime[A];
    owner_invocation_id: InvocationID;
    kind: JoinKind;
    slot_count: int
): JoinID {.nimcall.} =
  inc runtime.next_join_id
  result = runtime.next_join_id
  runtime.joins.states[result] = JoinState[A](
    id: result,
    owner_invocation_id: owner_invocation_id,
    kind: kind,
    remaining: slot_count,
    slots: newSeq[Option[ArtifactID]](slot_count))

proc fail_runtime[A](runtime: InvocationRuntime[A]; message: string) {.nimcall.} =
  runtime.failed = true
  runtime.finished = true
  raise newException(ValueError, message)

proc accept_join_result[A](
    runtime: InvocationRuntime[A];
    join_id: JoinID;
    slot: int;
    artifact_id: ArtifactID
) {.nimcall.}

proc finish_join[A](
    runtime: InvocationRuntime[A];
    join_id: JoinID
) {.nimcall.} =
  if not runtime.joins.states.hasKey(join_id):
    runtime.fail_runtime("unknown join")
  let state = runtime.joins.states[join_id]
  if state.remaining != 0:
    runtime.fail_runtime("join not ready")
  if not runtime.invocations.hasKey(state.owner_invocation_id):
    runtime.fail_runtime("join owner missing")

  let owner = runtime.invocations[state.owner_invocation_id]
  if owner.phase != ip_join_waiting or owner.join_id != join_id:
    runtime.fail_runtime("join owner phase mismatch")

  var values = newSeq[A](state.slots.len)
  for index, slot in state.slots:
    if slot.isNone:
      runtime.fail_runtime("join slot missing")
    values[index] = runtime.lookup_artifact(slot.get)

  let input = runtime.lookup_artifact(owner.input_id)
  var output: A
  case owner.flow.kind
  of fk_fanout:
    if state.kind != jk_fanout:
      runtime.fail_runtime("fanout has wrong join kind")
    output = owner.flow.coalesce(values)
  of fk_lift:
    if state.kind != jk_lift:
      runtime.fail_runtime("lift has wrong join kind")
    output = owner.flow.construct(values, input)
  of fk_raw, fk_it, fk_model, fk_so:
    runtime.fail_runtime("non-join flow owns join state")

  let output_id = runtime.register_artifact(output)
  runtime.joins.states.del(join_id)
  runtime.invocations[owner.id] = Invocation[A](
    id: owner.id,
    flow: owner.flow.continuation,
    input_id: output_id,
    return_to: owner.return_to,
    phase: ip_ready)
  runtime.enqueue(owner.id)

proc accept_join_result[A](
    runtime: InvocationRuntime[A];
    join_id: JoinID;
    slot: int;
    artifact_id: ArtifactID
) =
  if not runtime.joins.states.hasKey(join_id):
    runtime.fail_runtime("unknown join result")
  let state = runtime.joins.states[join_id]
  discard runtime.lookup_artifact(artifact_id)
  if slot < 0 or slot >= state.slots.len:
    runtime.fail_runtime("invalid join slot")
  if state.slots[slot].isSome:
    runtime.fail_runtime("duplicate join result")
  state.slots[slot] = some(artifact_id)
  dec state.remaining
  if state.remaining == 0:
    runtime.finish_join(join_id)

proc deliver_return[A](
    runtime: InvocationRuntime[A];
    return_to: ReturnTarget[A];
    artifact_id: ArtifactID
) {.nimcall.} =
  if return_to.isNil:
    runtime.fail_runtime("nil return target")
  case return_to.kind
  of rt_continue:
    let next_id = runtime.new_invocation(
      return_to.flow, artifact_id, return_to.next)
    runtime.enqueue(next_id)
  of rt_join:
    runtime.accept_join_result(
      return_to.join_id, return_to.slot, artifact_id)
  of rt_finished:
    runtime.output = some(artifact_id)
    runtime.finished = true

proc suspend_model[A](
    runtime: InvocationRuntime[A];
    invocation: Invocation[A]
) {.nimcall.} =
  inc runtime.next_request_id
  let request_id = runtime.next_request_id
  let output_id = runtime.reserve_artifact_id()
  runtime.invocations[invocation.id] = Invocation[A](
    id: invocation.id,
    flow: invocation.flow,
    input_id: invocation.input_id,
    return_to: invocation.return_to,
    phase: ip_model_waiting,
    request_id: request_id,
    reserved_output_id: output_id)
  runtime.request_to_invocation[request_id] = invocation.id

  let waiting = runtime.invocations[invocation.id]
  let submitter = if not waiting.flow.submit.isNil:
    waiting.flow.submit
  else:
    runtime.submitter
  if submitter.isNil:
    runtime.fail_runtime("no model submitter")
  submitter(
    request_id,
    waiting.input_id,
    runtime.lookup_artifact(waiting.input_id),
    output_id)

proc deliver_model_result[A](
    runtime: InvocationRuntime[A];
    request_id: RequestID;
    value: A
) {.nimcall.} =
  if not runtime.request_to_invocation.hasKey(request_id):
    runtime.fail_runtime("unknown model request")
  let invocation_id = runtime.request_to_invocation[request_id]
  runtime.request_to_invocation.del(request_id)
  if not runtime.invocations.hasKey(invocation_id):
    runtime.fail_runtime("model invocation missing")
  let invocation = runtime.invocations[invocation_id]
  if invocation.phase != ip_model_waiting or
      invocation.request_id != request_id:
    runtime.fail_runtime("model invocation phase mismatch")
  register_artifact_at(runtime, invocation.reserved_output_id, value)
  runtime.invocations[invocation.id] = Invocation[A](
    id: invocation.id,
    flow: invocation.flow.continuation,
    input_id: invocation.reserved_output_id,
    return_to: invocation.return_to,
    phase: ip_ready)
  runtime.enqueue(invocation.id)

proc deliver_model_error[A](
    runtime: InvocationRuntime[A];
    request_id: RequestID
) {.nimcall.} =
  if not runtime.request_to_invocation.hasKey(request_id):
    runtime.fail_runtime("unknown model request")
  let invocation_id = runtime.request_to_invocation[request_id]
  runtime.request_to_invocation.del(request_id)
  if not runtime.invocations.hasKey(invocation_id):
    runtime.fail_runtime("model invocation missing")
  let invocation = runtime.invocations[invocation_id]
  if invocation.phase != ip_model_waiting:
    runtime.fail_runtime("model invocation phase mismatch")
  runtime.invocations.del(invocation_id)
  runtime.failed = true
  runtime.finished = true

proc begin_fanout[A](
    runtime: InvocationRuntime[A];
    invocation: Invocation[A]
) {.nimcall.} =
  let flow = invocation.flow
  let join_id = runtime.create_join(
    invocation.id, jk_fanout, flow.branches.len)
  runtime.invocations[invocation.id] = Invocation[A](
    id: invocation.id,
    flow: invocation.flow,
    input_id: invocation.input_id,
    return_to: invocation.return_to,
    phase: ip_join_waiting,
    join_id: join_id)
  for index, branch in flow.branches:
    let branch_id = runtime.new_invocation(
      branch,
      invocation.input_id,
      join_target[A](join_id, index))
    runtime.enqueue(branch_id)
  if flow.branches.len == 0:
    runtime.finish_join(join_id)

proc begin_lift[A](
    runtime: InvocationRuntime[A];
    invocation: Invocation[A]
) {.nimcall.} =
  let flow = invocation.flow
  let original = runtime.lookup_artifact(invocation.input_id)
  let works = flow.destructure(original)
  var seen = newSeq[bool](works.len)
  for work in works:
    if work.result_index < 0 or work.result_index >= works.len:
      runtime.fail_runtime("lift result index out of range")
    if seen[work.result_index]:
      runtime.fail_runtime("duplicate lift result index")
    seen[work.result_index] = true
  for present in seen:
    if not present:
      runtime.fail_runtime("lift result indexes are not contiguous")

  let join_id = runtime.create_join(
    invocation.id, jk_lift, works.len)
  runtime.invocations[invocation.id] = Invocation[A](
    id: invocation.id,
    flow: invocation.flow,
    input_id: invocation.input_id,
    return_to: invocation.return_to,
    phase: ip_join_waiting,
    join_id: join_id)
  for work in works:
    let work_id = runtime.register_artifact(work.input)
    let branch_id = runtime.new_invocation(
      flow.inner,
      work_id,
      join_target[A](join_id, work.result_index))
    runtime.enqueue(branch_id)
  if works.len == 0:
    runtime.finish_join(join_id)

proc handle_invocation[A](
    runtime: InvocationRuntime[A];
    invocation_id: InvocationID
) {.nimcall.} =
  if not runtime.invocations.hasKey(invocation_id):
    runtime.fail_runtime("ready invocation missing")
  let invocation = runtime.invocations[invocation_id]
  if invocation.phase != ip_ready:
    runtime.fail_runtime("non-ready invocation queued")

  var current = invocation.flow
  var value = runtime.lookup_artifact(invocation.input_id)
  var value_id = invocation.input_id
  while not current.isNil:
    case current.kind
    of fk_raw:
      value = current.value
      value_id = runtime.register_artifact(value)
      current = current.continuation
    of fk_it:
      value = current.projector(value)
      value_id = runtime.register_artifact(value)
      current = current.continuation
    of fk_model:
      invocation.flow = current
      invocation.input_id = value_id
      runtime.suspend_model(invocation)
      return
    of fk_so:
      let child = current.execute(value)
      runtime.invocations.del(invocation_id)
      if child.isNil:
        let next_id = runtime.new_invocation(
          current.continuation, value_id, invocation.return_to)
        runtime.enqueue(next_id)
      else:
        let child_id = runtime.new_invocation(
          child,
          value_id,
          prepend_local(current.continuation, invocation.return_to))
        runtime.enqueue(child_id)
      return
    of fk_fanout:
      invocation.flow = current
      invocation.input_id = value_id
      runtime.begin_fanout(invocation)
      return
    of fk_lift:
      invocation.flow = current
      invocation.input_id = value_id
      runtime.begin_lift(invocation)
      return

  runtime.invocations.del(invocation_id)
  runtime.deliver_return(invocation.return_to, value_id)

proc run_ready[A](runtime: InvocationRuntime[A]) {.nimcall.} =
  while runtime.ready_head < runtime.ready.len and not runtime.finished:
    let invocation_id = runtime.ready[runtime.ready_head]
    inc runtime.ready_head
    runtime.handle_invocation(invocation_id)
  if runtime.ready_head == runtime.ready.len:
    runtime.ready.setLen(0)
    runtime.ready_head = 0

proc start[A](
    runtime: InvocationRuntime[A];
    flow: Flow[A];
    input: A
) {.nimcall.} =
  let input_id: ArtifactID = 0
  runtime.register_artifact_at(input_id, input)
  let invocation_id = runtime.new_invocation(
    flow, input_id, finished_target[A]())
  runtime.enqueue(invocation_id)
  runtime.run_ready()

var submitted_requests: seq[RequestID] = @[]

proc record_submit(
    request_id: RequestID;
    input_id: ArtifactID;
    input: string;
    output_id: ArtifactID
) {.nimcall.} =
  discard input_id
  discard input
  discard output_id
  submitted_requests.add(request_id)

proc add_suffix(value: string): string {.nimcall.} =
  value & "+it"

proc child_value(value: string): Flow[string] {.nimcall.} =
  raw_flow(value & "+child")

proc no_child(value: string): Flow[string] {.nimcall.} =
  discard value
  nil

proc coalesce(values: seq[string]): string {.nimcall.} =
  values[0] & "|" & values[1]

proc split_pair(
    value: string
): seq[tuple[result_index: int, input: string]] {.nimcall.} =
  result.add((result_index: 0, input: value & "+a"))
  result.add((result_index: 1, input: value & "+b"))

proc construct_pair(results: seq[string]; input: string): string {.nimcall.} =
  input & "=" & results[0] & "|" & results[1]

proc assert_equal[T](actual, expected: T; message: string) {.nimcall.} =
  if actual != expected:
    raise newException(AssertionDefect, message)

block:
  ## Model suspends. Same Invocation retains model Flow and advances locally.
  submitted_requests.setLen(0)
  let runtime = new_runtime[string](record_submit)
  let flow = model_flow[string](
    continuation = it_flow[string](add_suffix))
  runtime.start(flow, "seed")
  assert_equal(submitted_requests.len, 1, "model was not submitted")
  runtime.deliver_model_result(submitted_requests[0], "model")
  runtime.run_ready()
  assert_equal(runtime.artifacts[runtime.output.get], "model+it",
    "model continuation failed")
  assert_equal(runtime.request_to_invocation.len, 0,
    "model request route leaked")

block:
  submitted_requests.setLen(0)
  let runtime = new_runtime[string](record_submit)
  runtime.start(model_flow[string](), "seed")
  runtime.deliver_model_error(submitted_requests[0])
  assert_equal(runtime.finished, true, "model error did not finish runtime")
  assert_equal(runtime.failed, true, "model error did not fail runtime")

block:
  ## Dynamic so nil: current local continuation still executes.
  let runtime = new_runtime[string]()
  let flow = so_flow[string](
    no_child,
    it_flow[string](add_suffix))
  runtime.start(flow, "seed")
  assert_equal(runtime.artifacts[runtime.output.get], "seed+it",
    "nil dynamic flow lost continuation")

block:
  ## Dynamic so non-nil: child runs first, parent local continuation runs after.
  let runtime = new_runtime[string]()
  let flow = so_flow[string](
    child_value,
    it_flow[string](add_suffix))
  runtime.start(flow, "seed")
  assert_equal(runtime.artifacts[runtime.output.get], "seed+child+it",
    "dynamic child return failed")

block:
  ## Fanout branches share input but request IDs route replies independently.
  submitted_requests.setLen(0)
  let runtime = new_runtime[string](record_submit)
  let flow = fanout_flow[string](@[
    model_flow[string](),
    model_flow[string]()
  ], coalesce)
  runtime.start(flow, "seed")
  assert_equal(submitted_requests.len, 2, "fanout did not submit both models")
  let first_request = submitted_requests[0]
  let second_request = submitted_requests[1]
  runtime.deliver_model_result(second_request, "second")
  runtime.run_ready()
  assert_equal(runtime.finished, false, "fanout finished too early")
  runtime.deliver_model_result(first_request, "first")
  runtime.run_ready()
  assert_equal(runtime.artifacts[runtime.output.get], "first|second",
    "fanout slot order failed")

block:
  ## Lift preserves original input and indexed slots despite out-of-order replies.
  submitted_requests.setLen(0)
  let runtime = new_runtime[string](record_submit)
  let flow = lift_flow[string](
    model_flow[string](),
    split_pair,
    construct_pair)
  runtime.start(flow, "seed")
  assert_equal(submitted_requests.len, 2, "lift did not submit both models")
  let first_request = submitted_requests[0]
  let second_request = submitted_requests[1]
  runtime.deliver_model_result(second_request, "B*")
  runtime.run_ready()
  assert_equal(runtime.finished, false, "lift finished too early")
  runtime.deliver_model_result(first_request, "A*")
  runtime.run_ready()
  assert_equal(runtime.artifacts[runtime.output.get],
    "seed=A*|B*", "lift original input or slot order failed")
  assert_equal(runtime.joins.states.len, 0, "lift join state leaked")

echo "invocation runtime prototype: PASS"
