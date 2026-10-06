proc require_flow_key[A](flow: Flow[A]): string =
  if flow.isNil:
    raise newException(ValueError, "cannot checkpoint a nil flow")
  if flow.flow_key.len == 0:
    raise newException(ValueError, "flow has no stable flow_key")
  flow.flow_key

proc index_flow_nodes[A](flow_nodes: openArray[Flow[A]]): Table[string, Flow[A]] =
  result = initTable[string, Flow[A]]()
  for flow in flow_nodes:
    let key = require_flow_key(flow)
    if result.hasKey(key):
      raise newException(ValueError, "duplicate flow_key: " & key)
    result[key] = flow

proc resolve_flow[A](flows: Table[string, Flow[A]]; key: string): Flow[A] =
  if key.len == 0 or not flows.hasKey(key):
    raise newException(ValueError,
      "checkpoint flow_key is missing from resolver: " & key &
      " (dynamic so nodes must be reconstructed before restore)")
  result = flows[key]
  if result.isNil or result.flow_key != key:
    raise newException(ValueError, "flow resolver key does not match Flow.flow_key: " & key)

proc snapshot_destination[A](
    destination: Destination[A]
): seq[CheckpointDestinationFrame] =
  if destination.isNil:
    raise newException(ValueError, "cannot checkpoint a nil destination")
  var current = destination
  var visited = initHashSet[pointer]()
  while true:
    let address = cast[pointer](current)
    if address in visited:
      raise newException(ValueError, "destination chain contains a cycle")
    visited.incl(address)
    var frame = CheckpointDestinationFrame(
      has_return_pool: current.return_pool.isSome,
      return_pool: if current.return_pool.isSome: current.return_pool.get else: 0,
      return_pool_stack: if current.return_pool_stack.isSome:
        current.return_pool_stack.get else: @[])
    case current.kind
    of dk_continue:
      frame.kind = cdfContinue
      frame.flow_key = require_flow_key(current.flow)
      result.add frame
      current = current.next
      if current.isNil:
        raise newException(ValueError, "continue destination has no next frame")
    of dk_join:
      frame.kind = cdfJoin
      frame.join_id = current.join_id
      frame.slot = current.slot
      result.add frame
      break
    of dk_finished:
      frame.kind = cdfFinished
      result.add frame
      break

proc restore_destination[A](
    frames: openArray[CheckpointDestinationFrame];
    flows: Table[string, Flow[A]]
): Destination[A] =
  if frames.len == 0:
    raise newException(ValueError, "checkpoint destination is empty")
  var tail: Destination[A]
  for index in countdown(frames.high, 0):
    let frame = frames[index]
    let return_pool = if frame.has_return_pool:
      some(frame.return_pool) else: none(int)
    let return_stack = if frame.has_return_pool:
      some(frame.return_pool_stack) else: none(seq[int])
    case frame.kind
    of cdfContinue:
      if index == frames.high:
        raise newException(ValueError, "continue destination has no terminal frame")
      tail = Destination[A](kind: dk_continue,
        flow: resolve_flow(flows, frame.flow_key), next: tail,
        return_pool: return_pool, return_pool_stack: return_stack)
    of cdfJoin:
      if index != frames.high:
        raise newException(ValueError, "join destination must be terminal")
      tail = Destination[A](kind: dk_join, join_id: frame.join_id,
        slot: frame.slot, return_pool: return_pool,
        return_pool_stack: return_stack)
    of cdfFinished:
      if index != frames.high:
        raise newException(ValueError, "finished destination must be terminal")
      tail = Destination[A](kind: dk_finished,
        return_pool: return_pool, return_pool_stack: return_stack)
  tail

proc snapshot_invocation[A](invocation: Invocation[A]): CheckpointInvocation =
  if invocation.isNil:
    raise newException(ValueError, "cannot checkpoint a nil invocation")
  result.flow_key = require_flow_key(invocation.flow)
  result.input_artifact_id = invocation.input_id
  result.pool_id = invocation.pool_id
  result.pool_stack = invocation.pool_stack
  result.destination = snapshot_destination(invocation.destination)
  if invocation.output_meta.isSome:
    let meta = invocation.output_meta.get
    result.output = CheckpointOutputMeta(present: true, id: meta.id,
      predecessor_ids: meta.predecessor_ids, operation: meta.operation,
      flow_kind: meta.flow_kind, request_id: meta.request_id)

proc restore_invocation[A](invocation: CheckpointInvocation;
    flows: Table[string, Flow[A]]): Invocation[A] =
  result = Invocation[A](flow: resolve_flow(flows, invocation.flow_key),
    input_id: invocation.input_artifact_id,
    destination: restore_destination(invocation.destination, flows),
    pool_id: invocation.pool_id, pool_stack: invocation.pool_stack,
    output_meta: none(ArtifactMeta))
  if invocation.output.present:
    # Artifact directories are transient model workspaces. Restored execution
    # must materialize them from SQLite at the model boundary.
    result.output_meta = some(ArtifactMeta(id: invocation.output.id,
      artifact_dir: Path(""),
      predecessor_ids: invocation.output.predecessor_ids,
      operation: invocation.output.operation,
      flow_kind: invocation.output.flow_kind,
      request_id: invocation.output.request_id))

proc snapshot_budget(ledger: BudgetLedger): CheckpointBudget =
  if ledger.isNil or ledger.pools.len == 0 or
      ledger.pools.len != ledger.spent.len:
    raise newException(ValueError, "work plan has an invalid budget ledger")
  result.initial = ledger.initial_budget
  result.global_remaining = ledger.global_remaining
  for index, pool in ledger.pools:
    result.pools.add CheckpointPool(name: pool.name, weight: pool.weight,
      spent: ledger.spent[index])

proc restore_budget(budget: CheckpointBudget): BudgetLedger =
  var weights = newSeq[PoolWeight](budget.pools.len)
  for index, pool in budget.pools:
    weights[index] = (name: pool.name, weight: pool.weight)
  result = new_budget_ledger(budget.initial, weights)
  for index, pool in budget.pools:
    if pool.spent > 0:
      result.admit_model(index, pool.spent, "checkpoint restore")
  let scale = max(1.0, max(abs(budget.initial), abs(budget.global_remaining)))
  if abs(result.global_remaining - budget.global_remaining) > 1e-10 * scale:
    raise newException(ValueError,
      "checkpoint budget remaining does not match pool spend")
  # Preserve the canonical persisted float after validating its consistency.
  result.global_remaining = budget.global_remaining

proc snapshot_work_plan*[A](plan: WorkPlan[A]): WorkPlanCheckpoint =
  if plan.context.isNil:
    raise newException(ValueError, "work plan has no runtime context")
  result = WorkPlanCheckpoint(version: workplan_checkpoint_version,
    budget: snapshot_budget(plan.budget),
    has_output: plan.output.isSome,
    output_artifact_id: if plan.output.isSome: plan.output.get else: 0,
    failure_message: if plan.failure_message.isSome:
      plan.failure_message.get else: "",
    has_failure: plan.failure_message.isSome,
    finished: plan.finished, failed: plan.failed,
    next_request_id: plan.context.next_request_id,
    # Runtime stores the last artifact/ready IDs; the checkpoint stores the
    # exclusive next value so range validation can reject unallocated IDs.
    next_artifact_id: plan.context.next_artifact_id + 1,
    next_ready_id: plan.next_ready_id + 1,
    next_join_id: plan.next_join_id,
    next_so_expansion_id: plan.context.next_so_expansion_id,
    entry_flow_key: require_flow_key(plan.entry))
  for expansion in plan.context.so_expansions:
    result.so_expansions.add CheckpointSoExpansion(
      id: expansion.id,
      parent_flow_key: expansion.parent_flow_key,
      input_artifact_id: expansion.input_artifact_id,
      budget: checkpoint_budget(expansion.budget),
      flow_keys: expansion.flow_keys)
  for id, invocation in plan.pending_ready.pairs:
    result.ready.add CheckpointReady(ready_id: id,
      invocation: snapshot_invocation(invocation))
  for id, join in plan.joins.pairs:
    var item = CheckpointJoin(id: id,
      kind: if join.kind == jk_fanout: "fanout" else: "lift",
      remaining: join.remaining)
    for slot in join.slots:
      item.slots.add (present: slot.isSome,
        artifact_id: if slot.isSome: slot.get else: 0)
    result.joins.add item
  for id, invocation in plan.join_invocations.pairs:
    result.join_invocations.add CheckpointJoinInvocation(join_id: id,
      invocation: snapshot_invocation(invocation))
  for request_id, invocation in plan.model_requests.pairs:
    result.model_requests.add CheckpointModelRequest(request_id: request_id,
      invocation: snapshot_invocation(invocation))
  # Run the DTO's complete structural validation before returning.
  discard to_json(result)

proc restore_work_plan*[A](
    checkpoint: WorkPlanCheckpoint;
    top_level_flows: seq[Flow[A]];
    context: RuntimeContext[A];
    flow_nodes: openArray[Flow[A]]
): WorkPlan[A] =
  ## Restore scheduler state after the caller has loaded all referenced
  ## artifacts into `context`. `flow_nodes` must include static nodes and any
  ## dynamic `so` nodes reconstructed from their origin callbacks.
  discard to_json(checkpoint)
  if context.isNil:
    raise newException(ValueError, "cannot restore without runtime context")
  let flows = index_flow_nodes(flow_nodes)
  let pool_weights = block:
    var values = newSeq[PoolWeight](checkpoint.budget.pools.len)
    for index, pool in checkpoint.budget.pools:
      values[index] = (name: pool.name, weight: pool.weight)
    values
  result = init_work_plan(top_level_flows, context,
    checkpoint.budget.initial, pool_weights)
  if require_flow_key(result.entry) != checkpoint.entry_flow_key:
    raise newException(ValueError, "checkpoint entry flow_key does not match workflow")
  if not flows.hasKey(checkpoint.entry_flow_key):
    raise newException(ValueError, "entry flow_key is missing from resolver")
  result.budget = restore_budget(checkpoint.budget)
  result.pending_ready.clear()
  for item in checkpoint.ready:
    result.pending_ready[item.ready_id] = restore_invocation(item.invocation, flows)
  result.joins.clear()
  for item in checkpoint.joins:
    var state = JoinState(id: item.id,
      kind: if item.kind == "fanout": jk_fanout else: jk_lift,
      remaining: item.remaining, slots: @[])
    for slot in item.slots:
      state.slots.add(if slot.present: some(slot.artifact_id)
        else: none(ArtifactID))
    result.joins[item.id] = state
  result.join_invocations.clear()
  for item in checkpoint.join_invocations:
    result.join_invocations[item.join_id] =
      restore_invocation(item.invocation, flows)
  result.model_requests.clear()
  for item in checkpoint.model_requests:
    result.model_requests[item.request_id] =
      restore_invocation(item.invocation, flows)
  result.output = if checkpoint.has_output:
    some(checkpoint.output_artifact_id) else: none(ArtifactID)
  result.finished = checkpoint.finished
  result.failed = checkpoint.failed
  result.failure_message = if checkpoint.has_failure:
    some(checkpoint.failure_message) else: none(string)
  result.next_ready_id = checkpoint.next_ready_id - 1
  result.next_join_id = checkpoint.next_join_id
  context.next_request_id = checkpoint.next_request_id
  context.next_artifact_id = checkpoint.next_artifact_id - 1
  context.next_so_expansion_id = checkpoint.next_so_expansion_id
