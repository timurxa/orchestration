import std/[options, paths, tables, unittest]
import ../api/vecherinka_runtime
import ../api/vecherinka_checkpoint

proc int_identity(value: int): int = value

proc fixture(): tuple[plan: WorkPlan[int], nodes: seq[Flow[int]]] =
  let finished = Flow[int](flow_key: "finished", kind: fk_it,
    projector: int_identity)
  let after = Flow[int](flow_key: "after", kind: fk_it,
    projector: int_identity)
  let entry = Flow[int](flow_key: "entry", kind: fk_it,
    projector: int_identity)
  let top = Flow[int](flow_key: "top", kind: fk_top,
    root: "main", entry: true, body: entry)
  let model = Flow[int](flow_key: "model", kind: fk_model,
    profile: luna.medium)
  let join = Flow[int](flow_key: "join", kind: fk_fanout,
    branches: @[], coalesce: nil)
  result.nodes = @[top, entry, after, finished, model, join]
  let context = new_runtime_context[int]()
  result.plan = init_work_plan(@[top], context, 10.0,
    @[(name: "default", weight: 1.0), (name: "research", weight: 2.0)])
  result.plan.budget.admit_model(1, 2.0)
  result.plan.pending_ready[1'u64] = Invocation[int](flow: entry,
    input_id: 2,
    destination: Destination[int](kind: dk_join, join_id: 4, slot: 1),
    pool_id: 1, pool_stack: @[0])
  result.plan.next_ready_id = 3
  result.plan.joins[4'u64] = JoinState(id: 4, kind: jk_fanout, remaining: 1,
    slots: @[some(2'u64), none(ArtifactID)])
  result.plan.next_join_id = 5
  result.plan.join_invocations[4'u64] = Invocation[int](flow: join,
    input_id: 2, destination: Destination[int](kind: dk_continue,
      flow: after, next: Destination[int](kind: dk_finished)),
    pool_id: 0, pool_stack: @[])
  result.plan.model_requests["i:0"] = Invocation[int](flow: model,
    input_id: 2, destination: Destination[int](kind: dk_finished),
    pool_id: 1, pool_stack: @[0],
    output_meta: some(ArtifactMeta(id: 5, artifact_dir: Path("/tmp/model-5"),
      predecessor_ids: @[2'u64], operation: "model", flow_kind: "fk_model",
      request_id: "i:0")))
  result.plan.context.next_request_id = 1
  result.plan.context.next_artifact_id = 6

suite "WorkPlan checkpoint adapter":
  test "round trips scheduler tables, destinations, budgets, and counters":
    let original = fixture()
    let checkpoint = snapshot_work_plan(original.plan)
    let payload = encode_checkpoint(checkpoint)
    let restored_context = new_runtime_context[int]()
    let restored = restore_work_plan(checkpoint, @[original.nodes[0]],
      restored_context, original.nodes)
    check encode_checkpoint(snapshot_work_plan(restored)) == payload
    check restored.pending_ready.len == 1
    check restored.joins[4'u64].remaining == 1
    check restored.join_invocations.hasKey(4'u64)
    check restored.model_requests.hasKey("i:0")
    check restored.context.next_artifact_id == 6
    check restored.context.next_request_id == 1
    check restored.budget.global_remaining == 8.0
    check restored.model_requests["i:0"].output_meta.get.artifact_dir == Path("")

  test "rejects absent flow keys and duplicate resolver keys":
    let original = fixture()
    let checkpoint = snapshot_work_plan(original.plan)
    expect ValueError:
      discard restore_work_plan(checkpoint, @[original.nodes[0]],
        new_runtime_context[int](), original.nodes[0 .. 3])
    expect ValueError:
      discard restore_work_plan(checkpoint, @[original.nodes[0]],
        new_runtime_context[int](), original.nodes & @[original.nodes[1]])

  test "dynamic so graph nodes must be reconstructed before restore":
    let original = fixture()
    original.plan.pending_ready[1'u64].flow = Flow[int](
      flow_key: "dynamic-so-child", kind: fk_it, projector: int_identity)
    let checkpoint = snapshot_work_plan(original.plan)
    expect ValueError:
      discard restore_work_plan(checkpoint, @[original.nodes[0]],
        new_runtime_context[int](), original.nodes)
