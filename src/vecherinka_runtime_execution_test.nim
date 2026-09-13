import std/[deques, json, options, os, paths, strutils, tables]
import vecherinka
import codex_json

type
  GeneratedInput = object
    value: string

var observed_tool = ""
var observed_output_kind = -1
var observed_materialized = false
var observed_model_working_dirs: seq[Path] = @[]
let expected_source_root = Path(os.expandFilename(os.getCurrentDir()))

proc artifact_value[A](context: RuntimeContext[A]; id: ArtifactID): A =
  lookup_artifact(context, id).data

proc inspect_generated_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  observed_tool = spec.tools[0].name
  observed_output_kind = spec.output_kind
  observed_materialized = true
  doAssert $spec.runtime_dir == $expected_source_root
  doAssert dirExists($spec.working_dir)
  var event: RuntimeEvent[A]
  event.kind = rev_model_artifact
  event.request_id = request_id
  event.output_kind = spec.output_kind
  event.output = LlmOutput(
    tool_name: "debug_return",
    arguments: newJObject()
  )
  event.materialize = spec.materialize
  event.has_output = true
  enqueue_runtime_event(context, event)

vecherinka(generated_solve):
  > generated_entry GeneratedInput ~> string {.entry.}:
    "debug-model".minimal[GeneratedInput, string]("generated prompt")

proc top(
    name: string;
    body: Flow[string];
    entry = false
): Flow[string] =
  Flow[string](
    kind: fk_top,
    root: name,
    entry: entry,
    body: body
  )

proc raw(value: string; continuation: Flow[string] = nil): Flow[string] =
  Flow[string](
    kind: fk_raw,
    value: value,
    continuation: continuation
  )

proc add_suffix(value: string): string = value & "+it"
proc add_suffix_2(value: string): string = value & "+it2"
proc child_recipe(value: string): Flow[string] = raw(value & "+child")
proc no_child(value: string): Flow[string] =
  discard value
  nil
proc upper(value: string): string = value.toUpperAscii

proc join_values(values: seq[string]): string = values.join("|")

proc split_input(
    value: string
): seq[tuple[result_index: int, input: string]] =
  let parts = value.split(",")
  for index in 0 ..< parts.len:
    result.add((index, parts[index]))

proc construct_lift(results: seq[string]; input: string): string =
  input & "=" & results.join("|")

proc empty_split(
    value: string
): seq[tuple[result_index: int, input: string]] =
  discard value

proc construct_empty(results: seq[string]; input: string): string =
  doAssert results.len == 0
  input & "+empty"

proc materialize_debug_string(
    output_kind: int;
    output: LlmOutput
): string =
  discard output_kind
  output.tool_name

proc expect_value_error(action: proc()) =
  var raised = false
  try:
    action()
  except ValueError:
    raised = true
  doAssert raised

proc working_dir_flow_submit(
    context: RuntimeContext[string];
    request_id: RequestId;
    input: string;
    working_dir: Path
) =
  observed_model_working_dirs.add(working_dir)
  doAssert dirExists($working_dir)
  var event: RuntimeEvent[string]
  event.kind = rev_model_artifact
  event.request_id = request_id
  event.output_kind = 0
  event.output = LlmOutput(
    tool_name: "model(" & input & ")",
    arguments: newJObject()
  )
  event.materialize = materialize_debug_string
  event.has_output = true
  enqueue_runtime_event(context, event)

proc debug_submit(
    context: RuntimeContext[string];
    request_id: RequestId;
    input: string;
    working_dir: Path
) =
  discard working_dir
  var event: RuntimeEvent[string]
  event.kind = rev_model_artifact
  event.request_id = request_id
  event.output_kind = 0
  event.output = LlmOutput(
    tool_name: "model(" & input & ")",
    arguments: newJObject()
  )
  event.materialize = materialize_debug_string
  event.has_output = true
  enqueue_runtime_event(context, event)

let fake_submit = ModelSubmitter[string](debug_submit)

block:
  let immediate = raw(
    "replaced",
    Flow[string](kind: fk_it, projector: add_suffix)
  )
  let result = execute_flows(@[top("immediate", immediate, true)], "seed")
  doAssert artifact_value(result.context, result.output.get) == "replaced+it"
  doAssert result.nodes.len == 0
  doAssert result.pending_ready.len == 0
  doAssert result.next_ready_id == 1
  doAssert result.output.get == 2
  doAssert result.context.artifacts.len == 3
  doAssert result.context.artifacts[0].meta.id == 0

block:
  let model = Flow[string](
    kind: fk_model,
    continuation: Flow[string](kind: fk_it, projector: add_suffix)
  )
  let result = execute_flows(
    @[top("main", model, true)],
    "seed",
    fake_submit
  )
  doAssert result.finished
  doAssert not result.failed
  doAssert artifact_value(result.context, result.output.get) == "model(seed)+it"
  doAssert result.nodes.len == 1
  doAssert result.nodes[1].kind == wk_model
  doAssert result.nodes[1].state == ws_done
  doAssert result.nodes[1].input.get == 0
  doAssert result.nodes[1].output.get == 1
  doAssert artifact_value(result.context, result.nodes[1].output.get) == "model(seed)"
  doAssert result.context.artifacts[1].meta.id == 1
  doAssert dirExists($result.context.artifacts[1].meta.artifact_dir)
  doAssert result.output.get == 2
  doAssert result.pending_ready.len == 0
  doAssert result.next_ready_id == 2

block:
  let worker = top(
    "worker",
    Flow[string](kind: fk_it, projector: add_suffix)
  )
  let entry = top(
    "entry",
    Flow[string](kind: fk_ref, name: "worker"),
    true
  )
  let result = execute_flows(@[entry, worker], "seed")
  doAssert artifact_value(result.context, result.output.get) == "seed+it"

block:
  let passthrough = Flow[string](kind: fk_so, execute: no_child)
  let result = execute_flows(@[top("passthrough", passthrough, true)], "seed")
  doAssert result.output.get == 0
  doAssert artifact_value(result.context, result.output.get) == "seed"
  doAssert result.context.artifacts.len == 1

block:
  let branch_a = Flow[string](kind: fk_it, projector: add_suffix)
  let branch_b = Flow[string](kind: fk_it, projector: upper)
  let fan = Flow[string](
    kind: fk_fanout,
    branches: @[branch_a, branch_b],
    coalesce: join_values,
    continuation: Flow[string](kind: fk_it, projector: add_suffix_2)
  )
  let result = execute_flows(@[top("fan", fan, true)], "seed")
  doAssert artifact_value(result.context, result.output.get) == "seed+it|SEED+it2"
  doAssert result.nodes.len == 1
  doAssert result.nodes[1].kind == wk_fanout
  doAssert result.nodes[1].state == ws_done
  doAssert result.nodes[1].output.get == 3
  doAssert $result.context.artifacts[3].meta.artifact_dir != $expected_source_root
  doAssert dirExists($result.context.artifacts[3].meta.artifact_dir)
  doAssert result.output.get == 4

block:
  let lift = Flow[string](
    kind: fk_lift,
    inner: Flow[string](kind: fk_it, projector: add_suffix),
    destructure: split_input,
    construct: construct_lift
  )
  let result = execute_flows(@[top("lift", lift, true)], "a,b")
  doAssert artifact_value(result.context, result.output.get) == "a,b=a+it|b+it"
  doAssert result.nodes.len == 1
  doAssert result.nodes[1].kind == wk_lift
  doAssert result.nodes[1].state == ws_done
  doAssert result.nodes[1].output.get == 5
  doAssert $result.context.artifacts[5].meta.artifact_dir != $expected_source_root
  doAssert dirExists($result.context.artifacts[5].meta.artifact_dir)

block:
  let empty_lift = Flow[string](
    kind: fk_lift,
    inner: raw("unused"),
    destructure: empty_split,
    construct: construct_empty
  )
  let result = execute_flows(@[top("empty", empty_lift, true)], "seed")
  doAssert artifact_value(result.context, result.output.get) == "seed+empty"
  doAssert result.output.get == 1

block:
  let dynamic = Flow[string](
    kind: fk_so,
    execute: child_recipe,
    continuation: Flow[string](kind: fk_it, projector: add_suffix)
  )
  let result = execute_flows(@[top("dynamic", dynamic, true)], "seed")
  doAssert artifact_value(result.context, result.output.get) == "seed+child+it"
  doAssert result.output.get == 2

block:
  observed_model_working_dirs.setLen(0)
  let second = Flow[string](
    kind: fk_model,
    submit: working_dir_flow_submit)
  let first = Flow[string](
    kind: fk_model,
    submit: working_dir_flow_submit,
    continuation: second)
  let result = execute_flows(@[top("metadata", first, true)], "seed")
  doAssert result.finished
  doAssert not result.failed
  doAssert result.nodes.len == 2
  doAssert result.context.run_dir != Path("")
  doAssert dirExists($result.context.run_dir)
  doAssert result.context.next_artifact_id == 2
  doAssert result.context.artifacts.len == 3
  doAssert observed_model_working_dirs.len == 2
  doAssert $observed_model_working_dirs[0] !=
    $observed_model_working_dirs[1]
  doAssert result.nodes[1].input.get == 0
  doAssert result.nodes[1].output.get == 1
  doAssert result.nodes[2].input.get == 1
  doAssert result.nodes[2].output.get == 2
  doAssert result.output.get == 2

proc observed_child_model(value: string): Flow[string] =
  discard value
  Flow[string](kind: fk_model, submit: working_dir_flow_submit)

block:
  observed_model_working_dirs.setLen(0)
  let dynamic_model = Flow[string](
    kind: fk_so,
    execute: observed_child_model)
  let result = execute_flows(@[top("dynamic_model", dynamic_model, true)], "seed")
  doAssert result.finished

block:
  let context = new_runtime_context[string](
    nil, nil, create_run_directory(expected_source_root))
  open_global_events(context)
  let metadata = ArtifactMeta(
    id: 77,
    artifact_dir: context.run_dir / Path("artifact-77"))
  var event: RuntimeEvent[string]
  event.kind = rev_model_artifact
  event.request_id = RequestId(kind: rid_integer, integer_value: 7)
  event.has_output_meta = true
  event.output_meta = metadata
  enqueue_runtime_event(context, event)
  let copied = recv_global_event(context)
  doAssert copied.has_output_meta
  doAssert copied.output_meta.id == 77
  doAssert $copied.output_meta.artifact_dir == $metadata.artifact_dir
  close_global_events(context)

block:
  let run_dir = create_run_directory(expected_source_root)
  let context = new_runtime_context[string](nil, nil, run_dir, expected_source_root)
  let source_meta = ArtifactMeta(id: 0, artifact_dir: expected_source_root)
  doAssert register_artifact(context, "seed", source_meta) == 0
  doAssert lookup_artifact(context, 0).data == "seed"
  doAssert lookup_artifact(context, 0).meta.id == 0
  doAssert $lookup_artifact(context, 0).meta.artifact_dir ==
    $expected_source_root
  expect_value_error(proc() = discard lookup_artifact(context, 1))
  context.artifacts[9] = ArtifactRecord[string](
    data: "bad", meta: ArtifactMeta(id: 8, artifact_dir: run_dir))
  expect_value_error(proc() = discard lookup_artifact(context, 9))

block:
  observed_model_working_dirs.setLen(0)
  let branch_a = Flow[string](kind: fk_model, submit: working_dir_flow_submit)
  let branch_b = Flow[string](kind: fk_model, submit: working_dir_flow_submit)
  let fan = Flow[string](
    kind: fk_fanout,
    branches: @[branch_a, branch_b],
    coalesce: join_values)
  let result = execute_flows(@[top("distinct_roots", fan, true)], "seed")
  doAssert result.finished
  doAssert not result.failed
  doAssert artifact_value(result.context, result.output.get) ==
    "model(seed)|model(seed)"
  doAssert result.output.get == 3
  doAssert dirExists($result.context.artifacts[3].meta.artifact_dir)

block:
  generated_solve(
    GeneratedInput(value: "actual"),
    inspect_generated_transport)
  doAssert observed_materialized
  doAssert observed_tool == "return_string"
  doAssert observed_output_kind >= 0

echo "vecherinka runtime execution: PASS"
