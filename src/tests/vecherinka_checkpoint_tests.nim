import std/[unittest, json]
import ../api/vecherinka_checkpoint

proc sample(): WorkPlanCheckpoint =
  result = WorkPlanCheckpoint(
    version: workplan_checkpoint_version,
    budget: CheckpointBudget(initial: 12.5, global_remaining: 8.5,
      pools: @[
        CheckpointPool(name: "default", weight: 1.0, spent: 2.0),
        CheckpointPool(name: "research", weight: 3.0, spent: 2.0)]),
    next_request_id: 17,
    next_artifact_id: 55,
    next_ready_id: 9,
    next_join_id: 4,
    entry_flow_key: "entry",
    has_output: false,
    output_artifact_id: 0,
    has_failure: false,
    failure_message: "",
    failed: false,
    finished: false)
  let inv = CheckpointInvocation(
    flow_key: "entry/body/branch-1",
    input_artifact_id: 0,
    pool_id: 1,
    pool_stack: @[0, 1],
    output: CheckpointOutputMeta(present: true, id: 50,
      predecessor_ids: @[0, 44], operation: "model", flow_kind: "fk_model",
      request_id: "i:16"),
    destination: @[
      CheckpointDestinationFrame(kind: cdfContinue,
        flow_key: "entry/body/after-ref", has_return_pool: true,
        return_pool: 0, return_pool_stack: @[0]),
      CheckpointDestinationFrame(kind: cdfJoin, join_id: 3, slot: 1)])
  result.ready = @[CheckpointReady(ready_id: 8, invocation: inv)]
  result.joins = @[CheckpointJoin(id: 3, kind: "fanout", remaining: 1,
    slots: @[(present: true, artifact_id: 0), (present: false, artifact_id: 0)])]
  result.join_invocations = @[CheckpointJoinInvocation(join_id: 3,
    invocation: CheckpointInvocation(flow_key: "join/3", input_artifact_id: 50,
      pool_id: 0, destination: @[
        CheckpointDestinationFrame(kind: cdfFinished)]))]
  result.model_requests = @[CheckpointModelRequest(request_id: "i:16",
    invocation: inv)]

suite "WorkPlan checkpoint DTO":
  test "round trips all logical state and emits deterministic JSON":
    let original = sample()
    let encoded = encode_checkpoint(original)
    let decoded = decode_checkpoint(encoded)
    check decoded == original
    check decoded.ready[0].invocation.input_artifact_id == 0
    check decoded.ready[0].invocation.output.predecessor_ids[0] == 0
    check decoded.joins[0].slots[0].present
    check decoded.joins[0].slots[0].artifact_id == 0'u64
    check encode_checkpoint(decoded) == encoded

  test "map-backed collections serialize in key order":
    var left = sample()
    var right = sample()
    let invocation = right.ready[0].invocation
    left.ready.add CheckpointReady(ready_id: 2, invocation: invocation)
    right.ready.insert CheckpointReady(ready_id: 2, invocation: invocation), 0
    left.joins.add CheckpointJoin(id: 1, kind: "lift", remaining: 0)
    right.joins.insert CheckpointJoin(id: 1, kind: "lift", remaining: 0), 0
    let joinInv = CheckpointJoinInvocation(join_id: 1,
      invocation: CheckpointInvocation(flow_key: "join/1",
        input_artifact_id: 50, pool_id: 0, destination: @[
          CheckpointDestinationFrame(kind: cdfFinished)]))
    left.join_invocations.add joinInv
    right.join_invocations.insert joinInv, 0
    var requestInvocation = invocation
    requestInvocation.output.request_id = "req-2"
    let request = CheckpointModelRequest(request_id: "req-2", invocation: requestInvocation)
    left.model_requests.add request
    right.model_requests.insert request, 0
    check encode_checkpoint(left) == encode_checkpoint(right)
    let decoded = decode_checkpoint(encode_checkpoint(right))
    check decoded.ready[0].ready_id == 2
    check decoded.joins[0].id == 1
    check decoded.model_requests[0].request_id == "i:16"

  test "uint64 identifiers retain full precision":
    var value = sample()
    value.next_artifact_id = high(uint64)
    value.ready[0].invocation.input_artifact_id = high(uint64) - 1
    let decoded = decode_checkpoint(encode_checkpoint(value))
    check decoded.next_artifact_id == high(uint64)
    check decoded.ready[0].invocation.input_artifact_id == high(uint64) - 1

  test "round trips terminal output and failure state":
    var completed = sample()
    completed.ready.setLen(0)
    completed.joins.setLen(0)
    completed.join_invocations.setLen(0)
    completed.model_requests.setLen(0)
    completed.finished = true
    completed.has_output = true
    completed.output_artifact_id = 0
    check decode_checkpoint(encode_checkpoint(completed)) == completed
    var failed = sample()
    failed.ready.setLen(0)
    failed.joins.setLen(0)
    failed.join_invocations.setLen(0)
    failed.model_requests.setLen(0)
    failed.finished = true
    failed.failed = true
    failed.has_failure = true
    failed.failure_message = "failed"
    check decode_checkpoint(encode_checkpoint(failed)) == failed

  test "rejects invalid budgets and duplicate pool names":
    var invalid = sample()
    invalid.budget.global_remaining = -1.0
    expect ValueError:
      discard encode_checkpoint(invalid)
    var node = to_json(sample())
    node["budget"]["pools"][1]["name"] = %"default"
    expect ValueError:
      discard parse_checkpoint(node)

  test "rejects inconsistent joins and missing join invocation":
    var node = to_json(sample())
    node["joins"][0]["remaining"] = %0
    expect ValueError:
      discard parse_checkpoint(node)
    node = to_json(sample())
    node["join_invocations"] = newJArray()
    expect ValueError:
      discard parse_checkpoint(node)

  test "rejects duplicate IDs and IDs beyond counters":
    var node = to_json(sample())
    node["ready"].add node["ready"][0]
    expect ValueError:
      discard parse_checkpoint(node)
    node = to_json(sample())
    node["next_artifact_id"] = %"50"
    expect ValueError:
      discard parse_checkpoint(node)

  test "rejects model request metadata mismatch and terminal contradictions":
    var node = to_json(sample())
    node["model_requests"][0]["request_id"] = %"i:15"
    expect ValueError:
      discard parse_checkpoint(node)
    node = to_json(sample())
    node["failed"] = %true
    expect ValueError:
      discard parse_checkpoint(node)

  test "rejects non-finite budget values on encode":
    var invalid = sample()
    invalid.budget.initial = NaN
    expect ValueError:
      discard encode_checkpoint(invalid)

  test "rejects unsupported versions":
    var node = to_json(sample())
    node["version"] = %99
    expect ValueError:
      discard parse_checkpoint(node)

  test "rejects malformed destination stacks":
    var node = to_json(sample())
    var shortDest = newJArray()
    shortDest.add node["ready"][0]["invocation"]["destination"][0]
    node["ready"][0]["invocation"]["destination"] = shortDest
    expect ValueError:
      discard parse_checkpoint(node)

  test "rejects unknown destination frame kinds":
    var node = to_json(sample())
    node["ready"][0]["invocation"]["destination"][1]["kind"] = %"path"
    expect ValueError:
      discard parse_checkpoint(node)

  test "rejects non-decimal uint identifiers":
    var node = to_json(sample())
    node["output_artifact_id"] = %12
    expect ValueError:
      discard parse_checkpoint(node)
