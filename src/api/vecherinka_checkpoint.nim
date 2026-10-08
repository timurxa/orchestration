## Versioned, canonical, data-only snapshot of a Vecherinka WorkPlan.
## The runtime maps pointer/proc based state to these stable logical keys.

import std/[algorithm, json, math, strutils]

type
  CheckpointPool* = object
    name*: string
    weight*: float64
    spent*: float64

  CheckpointBudget* = object
    initial*: float64
    global_remaining*: float64
    pools*: seq[CheckpointPool]

  CheckpointBudgetContext* = object
    pool_name*: string
    pool_weight*: float64
    pool_capacity*: float64
    pool_spent*: float64
    pool_remaining*: float64
    global_remaining*: float64

  CheckpointSoExpansion* = object
    id*: uint64
    parent_flow_key*: string
    input_artifact_id*: uint64
    budget*: CheckpointBudgetContext
    flow_keys*: seq[string]

  CheckpointOutputMeta* = object
    present*: bool
    id*: uint64
    predecessor_ids*: seq[uint64]
    operation*: string
    flow_kind*: string
    request_id*: string

  CheckpointDestinationFrameKind* = enum
    cdfContinue, cdfJoin, cdfFinished, cdfComplete

  CheckpointDestinationFrame* = object
    kind*: CheckpointDestinationFrameKind
    flow_key*: string
    join_id*: uint64
    slot*: int
    has_return_pool*: bool
    return_pool*: int
    return_pool_stack*: seq[int]
    completion_work_id*: uint64

  CheckpointInvocation* = object
    flow_key*: string
    input_artifact_id*: uint64
    work_id*: uint64
    cause_work_id*: uint64
    cause_relation*: string
    cause_position*: int
    pool_id*: int
    pool_stack*: seq[int]
    output*: CheckpointOutputMeta
    destination*: seq[CheckpointDestinationFrame]

  CheckpointReady* = object
    ready_id*: uint64
    invocation*: CheckpointInvocation

  CheckpointJoin* = object
    id*: uint64
    kind*: string
    remaining*: int
    slots*: seq[tuple[present: bool, artifact_id, work_id: uint64]]

  CheckpointJoinInvocation* = object
    join_id*: uint64
    invocation*: CheckpointInvocation

  CheckpointModelRequest* = object
    request_id*: string
    invocation*: CheckpointInvocation

  WorkPlanCheckpoint* = object
    version*: int
    budget*: CheckpointBudget
    ready*: seq[CheckpointReady]
    joins*: seq[CheckpointJoin]
    join_invocations*: seq[CheckpointJoinInvocation]
    model_requests*: seq[CheckpointModelRequest]
    has_output*: bool
    output_artifact_id*: uint64
    failure_message*: string
    has_failure*: bool
    finished*: bool
    failed*: bool
    next_request_id*: int64
    next_artifact_id*: uint64
    next_ready_id*: uint64
    next_join_id*: uint64
    next_so_expansion_id*: uint64
    next_work_id*: uint64
    entry_flow_key*: string
    so_expansions*: seq[CheckpointSoExpansion]

const workplan_checkpoint_version* = 2

proc juint(value: uint64): JsonNode =
  %($value)

proc as_uint(node: JsonNode; label: string): uint64 =
  if node.kind != JString:
    raise newException(ValueError, label & " must be encoded as a decimal string")
  try:
    result = parseBiggestUInt(node.getStr)
  except ValueError:
    raise newException(ValueError, "invalid " & label)

proc require_kind(node: JsonNode; kind: JsonNodeKind; label: string) =
  if node.kind != kind:
    raise newException(ValueError, "invalid checkpoint field: " & label)

proc field(node: JsonNode; name: string): JsonNode =
  if node.kind != JObject or not node.hasKey(name):
    raise newException(ValueError, "missing checkpoint field: " & name)
  node[name]

proc string_field(node: JsonNode; name: string): string =
  let value = field(node, name)
  require_kind(value, JString, name)
  value.getStr

proc bool_field(node: JsonNode; name: string): bool =
  let value = field(node, name)
  require_kind(value, JBool, name)
  value.getBool

proc int_field(node: JsonNode; name: string): int =
  let value = field(node, name)
  require_kind(value, JInt, name)
  value.getInt

proc int64_field(node: JsonNode; name: string): int64 =
  let value = field(node, name)
  require_kind(value, JInt, name)
  value.getBiggestInt

proc float_field(node: JsonNode; name: string): float64 =
  let value = field(node, name)
  if value.kind notin {JInt, JFloat}:
    raise newException(ValueError, "invalid checkpoint field: " & name)
  value.getFloat

proc uint_field(node: JsonNode; name: string): uint64 =
  as_uint(field(node, name), name)

proc optional_uint_field(node: JsonNode; name: string): uint64 =
  if node.kind == JObject and node.hasKey(name): uint_field(node, name)
  else: 0

proc uint_array(values: openArray[uint64]): JsonNode =
  result = newJArray()
  for value in values: result.add juint(value)

proc int_array(values: openArray[int]): JsonNode =
  result = newJArray()
  for value in values: result.add %value

proc uints(node: JsonNode; label: string): seq[uint64] =
  require_kind(node, JArray, label)
  for item in node: result.add as_uint(item, label)

proc ints(node: JsonNode; label: string): seq[int] =
  require_kind(node, JArray, label)
  for item in node:
    if item.kind != JInt: raise newException(ValueError, "invalid " & label)
    result.add item.getInt

proc validate_invocation(inv: CheckpointInvocation) =
  if inv.flow_key.len == 0: raise newException(ValueError, "empty flow key")
  if inv.pool_id < 0: raise newException(ValueError, "negative pool id")
  if inv.cause_relation.len == 0 and inv.cause_work_id != 0:
    raise newException(ValueError, "work cause has no relation")
  if inv.cause_relation.len > 0 and inv.cause_work_id == 0:
    raise newException(ValueError, "work relation has no cause")
  if inv.cause_position < 0:
    raise newException(ValueError, "negative work cause position")
  for id in inv.pool_stack:
    if id < 0: raise newException(ValueError, "negative pool stack id")
  if not inv.output.present and inv.output.id != 0:
    raise newException(ValueError, "absent output metadata has an artifact id")
  if inv.destination.len == 0:
    raise newException(ValueError, "destination must end in a terminal frame")
  for index, frame in inv.destination:
    case frame.kind
    of cdfContinue:
      if frame.flow_key.len == 0 or index == inv.destination.high:
        raise newException(ValueError, "continue destination needs a flow key and terminal")
    of cdfJoin:
      if index != inv.destination.high or frame.slot < 0:
        raise newException(ValueError, "join destination must be terminal with nonnegative slot")
    of cdfFinished:
      if index != inv.destination.high:
        raise newException(ValueError, "finished destination must be terminal")
    of cdfComplete:
      if index == inv.destination.high or frame.completion_work_id == 0:
        raise newException(ValueError, "completion frame needs a work id and next frame")
    if frame.has_return_pool and frame.return_pool < 0:
      raise newException(ValueError, "negative return pool")
    for id in frame.return_pool_stack:
      if id < 0: raise newException(ValueError, "negative return pool stack id")

proc validate_work_ids(inv: CheckpointInvocation; next_work_id: uint64) =
  if inv.work_id >= next_work_id or inv.cause_work_id >= next_work_id:
    raise newException(ValueError, "invocation work id is outside allocated range")
  for frame in inv.destination:
    if frame.completion_work_id >= next_work_id:
      raise newException(ValueError, "completion work id is outside allocated range")

proc validatePoolReferences(inv: CheckpointInvocation; poolCount: int) =
  for pool in inv.pool_stack:
    if pool >= poolCount:
      raise newException(ValueError, "invocation pool stack id is out of range")
  for frame in inv.destination:
    if frame.has_return_pool and frame.return_pool >= poolCount:
      raise newException(ValueError, "destination return pool is out of range")
    for pool in frame.return_pool_stack:
      if pool >= poolCount:
        raise newException(ValueError, "destination return pool stack id is out of range")

proc validNonnegative(value: float64): bool =
  value >= 0.0 and classify(value) notin {fcNan, fcInf, fcNegInf}

proc validateCheckpoint(checkpoint: WorkPlanCheckpoint) =
  if checkpoint.version != workplan_checkpoint_version:
    raise newException(ValueError, "unsupported checkpoint version")
  if checkpoint.entry_flow_key.len == 0:
    raise newException(ValueError, "empty entry flow key")
  if not validNonnegative(checkpoint.budget.initial) or
      not validNonnegative(checkpoint.budget.global_remaining):
    raise newException(ValueError, "budget values must be finite and nonnegative")
  if checkpoint.budget.pools.len == 0:
    raise newException(ValueError, "checkpoint must contain budget pools")
  var totalWeight = 0.0
  var hasDefaultPool = false
  for index, pool in checkpoint.budget.pools:
    if pool.name.len == 0 or not validNonnegative(pool.weight) or
        not validNonnegative(pool.spent):
      raise newException(ValueError, "invalid checkpoint budget pool")
    totalWeight += pool.weight
    hasDefaultPool = hasDefaultPool or pool.name == "default"
    for prior in 0 ..< index:
      if checkpoint.budget.pools[prior].name == pool.name:
        raise newException(ValueError, "duplicate budget pool name")
  if not hasDefaultPool or not validNonnegative(totalWeight) or totalWeight <= 0:
    raise newException(ValueError, "invalid checkpoint pool weights")

  if checkpoint.next_request_id < 0:
    raise newException(ValueError, "negative next request id")
  let nextWorkId = max(1'u64, checkpoint.next_work_id)

  if checkpoint.has_output:
    if not checkpoint.finished or checkpoint.failed:
      raise newException(ValueError, "inconsistent terminal output state")
  elif checkpoint.output_artifact_id != 0:
    raise newException(ValueError, "output id present without output")
  if checkpoint.has_failure != checkpoint.failed or
      (checkpoint.failed and (not checkpoint.finished or checkpoint.has_output)):
    raise newException(ValueError, "inconsistent terminal failure state")

  var greatestArtifact = checkpoint.output_artifact_id
  var readyItems = checkpoint.ready
  readyItems.sort(proc(a, b: CheckpointReady): int = cmp(a.ready_id, b.ready_id))
  for index, ready in readyItems:
    if ready.ready_id == 0 or ready.ready_id >= checkpoint.next_ready_id:
      raise newException(ValueError, "ready id is outside allocated range")
    if index > 0 and readyItems[index - 1].ready_id == ready.ready_id:
      raise newException(ValueError, "duplicate ready id")
    validate_invocation(ready.invocation)
    validate_work_ids(ready.invocation, nextWorkId)
    validatePoolReferences(ready.invocation, checkpoint.budget.pools.len)
    if ready.invocation.pool_id >= checkpoint.budget.pools.len:
      raise newException(ValueError, "invocation pool id is out of range")
    for pool in ready.invocation.pool_stack:
      if pool >= checkpoint.budget.pools.len:
        raise newException(ValueError, "invocation pool stack id is out of range")
    greatestArtifact = max(greatestArtifact, ready.invocation.input_artifact_id)
    if ready.invocation.output.present:
      greatestArtifact = max(greatestArtifact, ready.invocation.output.id)
    for id in ready.invocation.output.predecessor_ids:
      greatestArtifact = max(greatestArtifact, id)

  var joinItems = checkpoint.joins
  joinItems.sort(proc(a, b: CheckpointJoin): int = cmp(a.id, b.id))
  for index, join in joinItems:
    if join.id == 0 or join.id >= checkpoint.next_join_id:
      raise newException(ValueError, "join id is outside allocated range")
    if index > 0 and joinItems[index - 1].id == join.id:
      raise newException(ValueError, "duplicate join id")
    if join.kind notin ["fanout", "lift"] or join.remaining < 0:
      raise newException(ValueError, "invalid join state")
    var unfilled = 0
    for slot in join.slots:
      if slot.present:
        greatestArtifact = max(greatestArtifact, slot.artifact_id)
        if slot.work_id >= nextWorkId:
          raise newException(ValueError, "join work id is outside allocated range")
      else:
        inc unfilled
        if slot.artifact_id != 0 or slot.work_id != 0:
          raise newException(ValueError, "unfilled join slot has an artifact id")
    if join.remaining != unfilled:
      raise newException(ValueError, "join remaining count does not match slots")

  var invocationItems = checkpoint.join_invocations
  invocationItems.sort(proc(a, b: CheckpointJoinInvocation): int =
    cmp(a.join_id, b.join_id))
  if invocationItems.len != joinItems.len:
    raise newException(ValueError, "join and join invocation sets differ")
  for index, item in invocationItems:
    if item.join_id != joinItems[index].id:
      raise newException(ValueError, "join and join invocation sets differ")
    validate_invocation(item.invocation)
    validate_work_ids(item.invocation, nextWorkId)
    validatePoolReferences(item.invocation, checkpoint.budget.pools.len)
    if item.invocation.pool_id >= checkpoint.budget.pools.len:
      raise newException(ValueError, "join invocation pool id is out of range")
    greatestArtifact = max(greatestArtifact, item.invocation.input_artifact_id)
    if item.invocation.output.present:
      greatestArtifact = max(greatestArtifact, item.invocation.output.id)
    for id in item.invocation.output.predecessor_ids:
      greatestArtifact = max(greatestArtifact, id)

  var requestItems = checkpoint.model_requests
  requestItems.sort(proc(a, b: CheckpointModelRequest): int =
    cmp(a.request_id, b.request_id))
  for index, item in requestItems:
    if item.request_id.len == 0:
      raise newException(ValueError, "empty model request id")
    if index > 0 and requestItems[index - 1].request_id == item.request_id:
      raise newException(ValueError, "duplicate model request id")
    validate_invocation(item.invocation)
    validate_work_ids(item.invocation, nextWorkId)
    validatePoolReferences(item.invocation, checkpoint.budget.pools.len)
    if not item.invocation.output.present or
        item.invocation.output.request_id != item.request_id:
      raise newException(ValueError, "model request and output metadata ids differ")
    if item.invocation.pool_id >= checkpoint.budget.pools.len:
      raise newException(ValueError, "model request pool id is out of range")
    greatestArtifact = max(greatestArtifact, item.invocation.input_artifact_id)
    greatestArtifact = max(greatestArtifact, item.invocation.output.id)
    for id in item.invocation.output.predecessor_ids:
      greatestArtifact = max(greatestArtifact, id)
    if item.request_id.startsWith("i:"):
      var requestNumber: int64
      try:
        requestNumber = parseBiggestInt(item.request_id[2 .. ^1])
      except ValueError:
        raise newException(ValueError, "invalid integer model request id")
      if requestNumber < 0 or requestNumber >= checkpoint.next_request_id:
        raise newException(ValueError, "model request id is outside allocated range")

  if checkpoint.has_output:
    greatestArtifact = max(greatestArtifact, checkpoint.output_artifact_id)
  var lastExpansion = 0'u64
  for expansion in checkpoint.so_expansions:
    if expansion.id == 0 or expansion.id <= lastExpansion or
        expansion.id >= checkpoint.next_so_expansion_id:
      raise newException(ValueError,
        "so expansion id is outside allocated range")
    lastExpansion = expansion.id
    if expansion.parent_flow_key.len == 0 or expansion.flow_keys.len == 0:
      raise newException(ValueError, "so expansion is missing flow identity")
    greatestArtifact = max(greatestArtifact, expansion.input_artifact_id)
    let budget = expansion.budget
    if budget.pool_name.len == 0 or not validNonnegative(budget.pool_weight) or
        not validNonnegative(budget.pool_capacity) or
        not validNonnegative(budget.pool_spent) or
        not validNonnegative(budget.pool_remaining) or
        not validNonnegative(budget.global_remaining) or
        budget.pool_spent > budget.pool_capacity or
        abs((budget.pool_capacity - budget.pool_spent) -
          budget.pool_remaining) > 1e-10 * max(1.0, budget.pool_capacity):
      raise newException(ValueError, "invalid so expansion budget snapshot")
    for index, key in expansion.flow_keys:
      if key.len == 0:
        raise newException(ValueError, "empty so expansion flow key")
      for prior in 0 ..< index:
        if expansion.flow_keys[prior] == key:
          raise newException(ValueError,
            "duplicate so expansion flow key")
  if greatestArtifact > 0 and greatestArtifact >= checkpoint.next_artifact_id:
    raise newException(ValueError, "artifact id is outside allocated range")

proc to_json(inv: CheckpointInvocation): JsonNode =
  validate_invocation(inv)
  result = %*{
    "flow_key": inv.flow_key,
    "input_artifact_id": juint(inv.input_artifact_id),
    "work_id": juint(inv.work_id),
    "cause_work_id": juint(inv.cause_work_id),
    "cause_relation": inv.cause_relation,
    "cause_position": inv.cause_position,
    "pool_id": inv.pool_id,
    "pool_stack": int_array(inv.pool_stack),
    "output": {
      "present": inv.output.present,
      "id": juint(inv.output.id),
      "predecessor_ids": uint_array(inv.output.predecessor_ids),
      "operation": inv.output.operation,
      "flow_kind": inv.output.flow_kind,
      "request_id": inv.output.request_id
    },
    "destination": newJArray()
  }
  for frame in inv.destination:
    let kind = case frame.kind
      of cdfContinue: "continue"
      of cdfJoin: "join"
      of cdfFinished: "finished"
      of cdfComplete: "complete"
    result["destination"].add %*{
      "kind": kind,
      "flow_key": frame.flow_key,
      "join_id": juint(frame.join_id),
      "slot": frame.slot,
      "has_return_pool": frame.has_return_pool,
      "return_pool": frame.return_pool,
      "return_pool_stack": int_array(frame.return_pool_stack),
      "completion_work_id": juint(frame.completion_work_id)
    }

proc parse_invocation(node: JsonNode): CheckpointInvocation =
  result.flow_key = string_field(node, "flow_key")
  result.input_artifact_id = uint_field(node, "input_artifact_id")
  result.work_id = optional_uint_field(node, "work_id")
  result.cause_work_id = optional_uint_field(node, "cause_work_id")
  result.cause_relation = if node.hasKey("cause_relation"):
    string_field(node, "cause_relation") else: ""
  result.cause_position = if node.hasKey("cause_position"):
    int_field(node, "cause_position") else: 0
  result.pool_id = int_field(node, "pool_id")
  result.pool_stack = ints(field(node, "pool_stack"), "pool_stack")
  let output = field(node, "output")
  result.output.present = bool_field(output, "present")
  result.output.id = uint_field(output, "id")
  result.output.predecessor_ids = uints(field(output, "predecessor_ids"), "predecessor_ids")
  result.output.operation = string_field(output, "operation")
  result.output.flow_kind = string_field(output, "flow_kind")
  result.output.request_id = string_field(output, "request_id")
  let dest = field(node, "destination")
  require_kind(dest, JArray, "destination")
  for item in dest:
    let kind = string_field(item, "kind")
    var frame: CheckpointDestinationFrame
    case kind
    of "continue": frame.kind = cdfContinue
    of "join": frame.kind = cdfJoin
    of "finished": frame.kind = cdfFinished
    of "complete": frame.kind = cdfComplete
    else: raise newException(ValueError, "unknown destination frame kind: " & kind)
    frame.flow_key = string_field(item, "flow_key")
    frame.join_id = uint_field(item, "join_id")
    frame.slot = int_field(item, "slot")
    frame.has_return_pool = bool_field(item, "has_return_pool")
    frame.return_pool = int_field(item, "return_pool")
    frame.return_pool_stack = ints(field(item, "return_pool_stack"), "return_pool_stack")
    frame.completion_work_id = optional_uint_field(item, "completion_work_id")
    result.destination.add frame
  validate_invocation(result)

proc to_json*(checkpoint: WorkPlanCheckpoint): JsonNode =
  validateCheckpoint(checkpoint)
  result = %*{
    "version": checkpoint.version,
    "budget": {
      "initial": checkpoint.budget.initial,
      "global_remaining": checkpoint.budget.global_remaining,
      "pools": newJArray()
    },
    "ready": newJArray(),
    "joins": newJArray(),
    "join_invocations": newJArray(),
    "model_requests": newJArray(),
    "has_output": checkpoint.has_output,
    "output_artifact_id": juint(checkpoint.output_artifact_id),
    "failure_message": checkpoint.failure_message,
    "has_failure": checkpoint.has_failure,
    "finished": checkpoint.finished,
    "failed": checkpoint.failed,
    "next_request_id": checkpoint.next_request_id,
    "next_artifact_id": juint(checkpoint.next_artifact_id),
    "next_ready_id": juint(checkpoint.next_ready_id),
    "next_join_id": juint(checkpoint.next_join_id),
    "next_so_expansion_id": juint(checkpoint.next_so_expansion_id),
    "next_work_id": juint(max(1'u64, checkpoint.next_work_id)),
    "entry_flow_key": checkpoint.entry_flow_key
  }
  result["so_expansions"] = newJArray()
  for pool in checkpoint.budget.pools:
    result["budget"]["pools"].add %*{
      "name": pool.name, "weight": pool.weight, "spent": pool.spent}
  for expansion in checkpoint.so_expansions:
    var flowKeys = newJArray()
    for key in expansion.flow_keys: flowKeys.add %key
    result["so_expansions"].add %*{
      "id": juint(expansion.id),
      "parent_flow_key": expansion.parent_flow_key,
      "input_artifact_id": juint(expansion.input_artifact_id),
      "budget": {
        "pool_name": expansion.budget.pool_name,
        "pool_weight": expansion.budget.pool_weight,
        "pool_capacity": expansion.budget.pool_capacity,
        "pool_spent": expansion.budget.pool_spent,
        "pool_remaining": expansion.budget.pool_remaining,
        "global_remaining": expansion.budget.global_remaining},
      "flow_keys": flowKeys}
  var ready_items = checkpoint.ready
  ready_items.sort(proc(a, b: CheckpointReady): int = cmp(a.ready_id, b.ready_id))
  for index in 1 ..< ready_items.len:
    if ready_items[index - 1].ready_id == ready_items[index].ready_id:
      raise newException(ValueError, "duplicate ready id")
  for ready in ready_items:
    result["ready"].add %*{"ready_id": juint(ready.ready_id),
      "invocation": to_json(ready.invocation)}
  var join_items = checkpoint.joins
  join_items.sort(proc(a, b: CheckpointJoin): int = cmp(a.id, b.id))
  for index in 1 ..< join_items.len:
    if join_items[index - 1].id == join_items[index].id:
      raise newException(ValueError, "duplicate join id")
  for join in join_items:
    if join.remaining < 0:
      raise newException(ValueError, "negative join remaining count")
    var slots = newJArray()
    for slot in join.slots:
      slots.add %*{"present": slot.present, "artifact_id": juint(slot.artifact_id),
        "work_id": juint(slot.work_id)}
    result["joins"].add %*{"id": juint(join.id), "kind": join.kind,
      "remaining": join.remaining, "slots": slots}
  var join_invocation_items = checkpoint.join_invocations
  join_invocation_items.sort(proc(a, b: CheckpointJoinInvocation): int =
    cmp(a.join_id, b.join_id))
  for index in 1 ..< join_invocation_items.len:
    if join_invocation_items[index - 1].join_id == join_invocation_items[index].join_id:
      raise newException(ValueError, "duplicate join invocation")
  for item in join_invocation_items:
    result["join_invocations"].add %*{"join_id": juint(item.join_id),
      "invocation": to_json(item.invocation)}
  var model_request_items = checkpoint.model_requests
  model_request_items.sort(proc(a, b: CheckpointModelRequest): int =
    cmp(a.request_id, b.request_id))
  for index in 1 ..< model_request_items.len:
    if model_request_items[index - 1].request_id == model_request_items[index].request_id:
      raise newException(ValueError, "duplicate model request id")
  for item in model_request_items:
    if item.request_id.len == 0:
      raise newException(ValueError, "empty model request id")
    result["model_requests"].add %*{"request_id": item.request_id,
      "invocation": to_json(item.invocation)}

proc parse_checkpoint*(node: JsonNode): WorkPlanCheckpoint =
  result.version = int_field(node, "version")
  if result.version != workplan_checkpoint_version:
    raise newException(ValueError, "unsupported checkpoint version: " & $result.version)
  let budget = field(node, "budget")
  result.budget.initial = float_field(budget, "initial")
  result.budget.global_remaining = float_field(budget, "global_remaining")
  let pools = field(budget, "pools")
  require_kind(pools, JArray, "pools")
  for pool in pools:
    result.budget.pools.add CheckpointPool(name: string_field(pool, "name"),
      weight: float_field(pool, "weight"), spent: float_field(pool, "spent"))
  for item in field(node, "ready"):
    result.ready.add CheckpointReady(ready_id: uint_field(item, "ready_id"),
      invocation: parse_invocation(field(item, "invocation")))
  for item in field(node, "joins"):
    var join = CheckpointJoin(id: uint_field(item, "id"),
      kind: string_field(item, "kind"), remaining: int_field(item, "remaining"))
    let slots = field(item, "slots")
    require_kind(slots, JArray, "slots")
    for slot in slots:
      join.slots.add (present: bool_field(slot, "present"),
        artifact_id: uint_field(slot, "artifact_id"),
        work_id: optional_uint_field(slot, "work_id"))
    result.joins.add join
  for item in field(node, "join_invocations"):
    result.join_invocations.add CheckpointJoinInvocation(
      join_id: uint_field(item, "join_id"),
      invocation: parse_invocation(field(item, "invocation")))
  for item in field(node, "model_requests"):
    result.model_requests.add CheckpointModelRequest(
      request_id: string_field(item, "request_id"),
      invocation: parse_invocation(field(item, "invocation")))
  result.has_output = bool_field(node, "has_output")
  result.output_artifact_id = uint_field(node, "output_artifact_id")
  result.failure_message = string_field(node, "failure_message")
  result.has_failure = bool_field(node, "has_failure")
  result.finished = bool_field(node, "finished")
  result.failed = bool_field(node, "failed")
  result.next_request_id = int64_field(node, "next_request_id")
  result.next_artifact_id = uint_field(node, "next_artifact_id")
  result.next_ready_id = uint_field(node, "next_ready_id")
  result.next_join_id = uint_field(node, "next_join_id")
  result.next_so_expansion_id = uint_field(node, "next_so_expansion_id")
  result.next_work_id = if node.hasKey("next_work_id"):
    uint_field(node, "next_work_id") else: 1
  result.entry_flow_key = string_field(node, "entry_flow_key")
  for item in field(node, "so_expansions"):
    let budget = field(item, "budget")
    var expansion = CheckpointSoExpansion(
      id: uint_field(item, "id"),
      parent_flow_key: string_field(item, "parent_flow_key"),
      input_artifact_id: uint_field(item, "input_artifact_id"),
      budget: CheckpointBudgetContext(
        pool_name: string_field(budget, "pool_name"),
        pool_weight: float_field(budget, "pool_weight"),
        pool_capacity: float_field(budget, "pool_capacity"),
        pool_spent: float_field(budget, "pool_spent"),
        pool_remaining: float_field(budget, "pool_remaining"),
        global_remaining: float_field(budget, "global_remaining")))
    for key in field(item, "flow_keys"):
      require_kind(key, JString, "so expansion flow key")
      expansion.flow_keys.add key.getStr
    result.so_expansions.add expansion
  validateCheckpoint(result)

proc encode_checkpoint*(checkpoint: WorkPlanCheckpoint): string =
  $to_json(checkpoint)

proc decode_checkpoint*(payload: string): WorkPlanCheckpoint =
  parse_checkpoint(parseJson(payload))
