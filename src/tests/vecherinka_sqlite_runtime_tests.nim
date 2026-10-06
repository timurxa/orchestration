import std/[json, os, options, paths, strutils, tables, tempfiles, unittest]
import ../api/vecherinka_runtime
import ../api/codex_json
import ../api/vecherinka_store
import ../api/vecherinka_checkpoint

proc string_identity(value: string): string = value

proc replayable_so(input: string; budget: BudgetContext): Flow[string] {.nimcall.} =
  if budget.pool_name != "default":
    raise newException(ValueError, "unexpected replay budget")
  Flow[string](flow_key: "child", kind: fk_raw,
    value: input & "-rebuilt")

proc flow_fixture(): tuple[top: Flow[string], entry: Flow[string],
    nodes: seq[Flow[string]]] =
  result.entry = Flow[string](flow_key: "entry", kind: fk_it,
    projector: string_identity)
  result.top = Flow[string](flow_key: "top", kind: fk_top,
    root: "main", entry: true, body: result.entry)
  result.nodes = @[result.top, result.entry]

proc metadata(): StoreMetadata =
  StoreMetadata(workflow_id: "runtime-test",
    workflow_fingerprint: "runtime-test-fingerprint",
    workflow_manifest_json: "{}", codec_version: 1,
    checkpoint_version: checkpoint_format_version)

proc model_output(kind: int; output: LlmOutput):
    ModelMaterialization[string] {.nimcall.} =
  discard kind
  ModelMaterialization[string](ok: true,
    value: output.arguments["value"].getStr)

proc fake_model_submit(context: RuntimeContext[string]; request_id: RequestId;
    input: string; working_dir: Path) {.nimcall.} =
  discard input
  discard working_dir
  context.enqueue_runtime_event(RuntimeEvent[string](
    request_id: request_id, kind: rev_model_artifact, output_kind: 0,
    output: LlmOutput(tool_name: "finish_work",
      arguments: %*{"value": "model-envelope"}),
    materialize: model_output, tool_request_id: none(RequestId),
    tool_binding_id: none(uint64), output_meta: none(ArtifactMeta)))

proc unused_submitter(context: RuntimeContext[string]; request_id: RequestId;
    input: string; working_dir: Path) {.nimcall.} =
  discard context
  discard request_id
  discard input
  discard working_dir

suite "SQLite runtime persistence and resume":
  test "new run commits serialized artifacts and final checkpoint":
    let root = createTempDir("vecherinka-runtime-create-", "", getTempDir())
    defer: removeDir(root)
    let database = Path(root / "run.sqlite3")
    let flows = flow_fixture()
    let result = create_sqlite_run(@[flows.top], "input-envelope", database,
      metadata(), flows.nodes)
    check result.finished
    check result.output.isSome
    check lookup_artifact(result.context, result.output.get).data ==
      "input-envelope"

    let store = open_vecherinka_store(database, metadata())
    defer: store.close()
    let input = store.artifact(0)
    let output = store.artifact(result.output.get)
    let saved = store.checkpoint()
    check input.isSome
    check input.get.payload_text == "input-envelope"
    check output.isSome
    check output.get.payload_text == "input-envelope"
    check output.get.predecessor_ids == @[0'u64]
    check saved.isSome
    check saved.get.status == "finished"
    check store.metadata().run_id.startsWith("sqlite:")

  test "resume hydrates the input lazily and continues the saved ready queue":
    let root = createTempDir("vecherinka-runtime-resume-", "", getTempDir())
    defer: removeDir(root)
    let database = Path(root / "run.sqlite3")
    let flows = flow_fixture()
    var plan = init_work_plan(@[flows.top], new_runtime_context[string]())
    plan.context.next_artifact_id = 0
    plan.pending_ready[1'u64] = Invocation[string](
      flow: flows.entry, input_id: 0,
      destination: Destination[string](kind: dk_finished))
    plan.next_ready_id = 2
    let checkpoint = snapshot_work_plan(plan)
    var persisted_metadata = metadata()
    persisted_metadata.run_id = "runtime-test-run"
    let store = create_vecherinka_store(database, persisted_metadata)
    store.commit_transition(-1,
      @[StoredArtifact(id: 0, codec_id: "vecherinka.artifact.v1",
        codec_version: 1, payload_text: "resumed-envelope")],
      StoreCheckpoint(sequence: 0,
        format_version: checkpoint_format_version,
        status: "interrupted", payload_text: encode_checkpoint(checkpoint)))
    store.close()

    let resumed = resume_sqlite_run(@[flows.top], database, metadata(),
      flows.nodes)
    check resumed.finished
    check resumed.output.isSome
    check lookup_artifact(resumed.context, resumed.output.get).data ==
      "resumed-envelope"
    let reopened = open_vecherinka_store(database, metadata())
    defer: reopened.close()
    let input = reopened.artifact(0)
    let output = reopened.artifact(resumed.output.get)
    let saved = reopened.checkpoint()
    check input.isSome
    check input.get.payload_text == "resumed-envelope"
    check output.isSome
    check output.get.payload_text == "resumed-envelope"
    check output.get.predecessor_ids == @[0'u64]
    check saved.isSome
    check saved.get.status == "finished"
    check saved.get.sequence == 2

  test "resume rebuilds a dynamic so graph from its saved origin":
    let root = createTempDir("vecherinka-runtime-so-resume-", "",
      getTempDir())
    defer: removeDir(root)
    let database = Path(root / "run.sqlite3")
    let soFlow = Flow[string](flow_key: "so-parent", kind: fk_so,
      execute: replayable_so)
    let top = Flow[string](flow_key: "top", kind: fk_top,
      root: "main", entry: true, body: soFlow)
    let checkpoint = WorkPlanCheckpoint(
      version: workplan_checkpoint_version,
      budget: CheckpointBudget(initial: 0.0, global_remaining: 0.0,
        pools: @[CheckpointPool(name: "default", weight: 1.0, spent: 0.0)]),
      ready: @[CheckpointReady(ready_id: 1,
        invocation: CheckpointInvocation(flow_key: "so-1/child",
          input_artifact_id: 0, pool_id: 0,
          destination: @[CheckpointDestinationFrame(kind: cdfFinished)]))],
      next_artifact_id: 1, next_ready_id: 2, next_join_id: 1,
      next_so_expansion_id: 2, entry_flow_key: "so-parent",
      so_expansions: @[CheckpointSoExpansion(id: 1,
        parent_flow_key: "so-parent", input_artifact_id: 0,
        budget: CheckpointBudgetContext(pool_name: "default",
          pool_weight: 1.0, pool_capacity: 0.0, pool_spent: 0.0,
          pool_remaining: 0.0, global_remaining: 0.0),
        flow_keys: @["so-1/child"])])
    var persistedMetadata = metadata()
    persistedMetadata.run_id = "runtime-test-so-resume"
    let store = create_vecherinka_store(database, persistedMetadata)
    store.commit_transition(-1,
      @[StoredArtifact(id: 0, codec_id: "vecherinka.artifact.v1",
        codec_version: 1, payload_text: "seed")],
      StoreCheckpoint(sequence: 0, format_version: checkpoint_format_version,
        status: "interrupted", payload_text: encode_checkpoint(checkpoint)))
    store.close()

    let resumed = resume_sqlite_run(@[top], database, metadata(),
      @[top, soFlow])
    check resumed.finished
    check resumed.output.isSome
    check lookup_artifact(resumed.context, resumed.output.get).data ==
      "seed-rebuilt"
    check resumed.context.so_expansions.len == 1

  test "model result is committed before the plan accepts completion":
    let root = createTempDir("vecherinka-runtime-model-", "", getTempDir())
    defer: removeDir(root)
    let database = Path(root / "run.sqlite3")
    let model = Flow[string](flow_key: "model", kind: fk_model,
      profile: luna.low, submit: fake_model_submit)
    let top = Flow[string](flow_key: "top", kind: fk_top,
      root: "main", entry: true, body: model)
    let plan = create_sqlite_run(@[top], "input-envelope", database,
      metadata(), @[top, model], initial_budget = 10.0,
      submitter = unused_submitter)
    check plan.finished
    check plan.output.isSome

    let store = open_vecherinka_store(database, metadata())
    defer: store.close()
    let checkpoint = store.checkpoint().get
    let saved_plan = decode_checkpoint(checkpoint.payload_text)
    check checkpoint.status == "finished"
    check saved_plan.model_requests.len == 0
    check store.attempt("i:0").get.state == sasCommitted
    check store.artifact(plan.output.get).get.payload_text == "model-envelope"

  test "resume reissues an unacknowledged model request without charging again":
    let root = createTempDir("vecherinka-runtime-model-resume-", "",
      getTempDir())
    defer: removeDir(root)
    let database = Path(root / "run.sqlite3")
    let model = Flow[string](flow_key: "model", kind: fk_model,
      profile: luna.low, submit: fake_model_submit)
    let top = Flow[string](flow_key: "top", kind: fk_top,
      root: "main", entry: true, body: model)
    let context = new_runtime_context[string]()
    var plan = init_work_plan(@[top], context, 10.0)
    let cost = profile_cost(luna, re_low)
    plan.budget.admit_model(0, cost)
    plan.model_requests["i:0"] = Invocation[string](
      flow: model, input_id: 0,
      destination: Destination[string](kind: dk_finished),
      pool_id: 0, pool_stack: @[],
      output_meta: some(ArtifactMeta(id: 1, artifact_dir: Path(""),
        predecessor_ids: @[0'u64], operation: "model",
        flow_kind: "fk_model", request_id: "i:0")))
    context.next_request_id = 1
    context.next_artifact_id = 1
    let saved = snapshot_work_plan(plan)
    var persisted_metadata = metadata()
    persisted_metadata.run_id = "runtime-test-model-resume"
    let store = create_vecherinka_store(database, persisted_metadata)
    store.commit_transition(-1,
      @[StoredArtifact(id: 0, codec_id: "vecherinka.artifact.v1",
        codec_version: 1, payload_text: "model-input")],
      StoreCheckpoint(sequence: 0,
        format_version: checkpoint_format_version,
        status: "interrupted", payload_text: encode_checkpoint(saved)),
      attempts = @[StoreAttempt(request_id: "i:0", state: sasPrepared,
        payload_text: "model intent")])
    store.close()

    let resumed = resume_sqlite_run(@[top], database, metadata(), @[top, model],
      submitter = unused_submitter)
    check resumed.finished
    check resumed.output.isSome
    check resumed.budget.global_remaining == 10.0 - cost
    let reopened = open_vecherinka_store(database, metadata())
    defer: reopened.close()
    check reopened.attempt("i:0").get.state == sasCommitted
    check reopened.artifact(resumed.output.get).get.payload_text ==
      "model-envelope"
    check decode_checkpoint(reopened.checkpoint().get.payload_text).
      model_requests.len == 0
