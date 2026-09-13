import std/[deques, json, options, strutils, tables]
import vecherinka
import codex_json

type
  GeneratedInput = object
    value: string

proc `$`(input: GeneratedInput): string = input.value

var observed_context = ""
var observed_tool = ""
var observed_output_kind = -1
var observed_materialized = false

proc inspect_generated_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  observed_context = spec.typed_context
  observed_tool = spec.tools[0].name
  observed_output_kind = spec.output_kind
  observed_materialized = true
  var event: RuntimeEvent[A]
  event.kind = rev_model_artifact
  event.request_id = request_id
  new(event.artifact)
  event.artifact[] = spec.materialize(
    spec.output_kind,
    LlmOutput(tool_name: "debug_return", arguments: newJObject())
  )
  event.has_artifact = true
  addLast(context.events, event)

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

proc debug_submit(
    context: RuntimeContext[string];
    request_id: RequestId;
    spec: ModelCallSpec[string]
) =
  var event: RuntimeEvent[string]
  event.kind = rev_model_artifact
  event.request_id = request_id
  new(event.artifact)
  event.artifact[] = spec.prompt & "(" & spec.input & ")"
  event.has_artifact = true
  addLast(context.events, event)

let fake_submit = ModelSubmitter[string](debug_submit)

block:
  let immediate = raw(
    "replaced",
    Flow[string](kind: fk_it, projector: add_suffix)
  )
  let result = execute_flows(@[top("immediate", immediate, true)], "seed")
  doAssert result.output.get == "replaced+it"
  doAssert result.nodes.len == 0

block:
  let model = Flow[string](
    kind: fk_model,
    prompt: "model",
    continuation: Flow[string](kind: fk_it, projector: add_suffix)
  )
  let result = execute_flows(
    @[top("main", model, true)],
    "seed",
    fake_submit
  )
  doAssert result.finished
  doAssert not result.failed
  doAssert result.output.get == "model(seed)+it"
  doAssert result.nodes.len == 1
  doAssert result.nodes[1].kind == wk_model
  doAssert result.nodes[1].state == ws_done
  doAssert result.nodes[1].input.get == "seed"
  doAssert result.nodes[1].output.get == "model(seed)"

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
  doAssert result.output.get == "seed+it"

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
  doAssert result.output.get == "seed+it|SEED+it2"
  doAssert result.nodes.len == 1
  doAssert result.nodes[1].kind == wk_fanout
  doAssert result.nodes[1].state == ws_done

block:
  let lift = Flow[string](
    kind: fk_lift,
    inner: Flow[string](kind: fk_it, projector: add_suffix),
    destructure: split_input,
    construct: construct_lift
  )
  let result = execute_flows(@[top("lift", lift, true)], "a,b")
  doAssert result.output.get == "a,b=a+it|b+it"
  doAssert result.nodes.len == 1
  doAssert result.nodes[1].kind == wk_lift
  doAssert result.nodes[1].state == ws_done

block:
  let empty_lift = Flow[string](
    kind: fk_lift,
    inner: raw("unused"),
    destructure: empty_split,
    construct: construct_empty
  )
  let result = execute_flows(@[top("empty", empty_lift, true)], "seed")
  doAssert result.output.get == "seed+empty"

block:
  let dynamic = Flow[string](
    kind: fk_so,
    execute: child_recipe,
    continuation: Flow[string](kind: fk_it, projector: add_suffix)
  )
  let result = execute_flows(@[top("dynamic", dynamic, true)], "seed")
  doAssert result.output.get == "seed+child+it"

block:
  generated_solve(
    GeneratedInput(value: "actual"),
    inspect_generated_transport)
  doAssert observed_materialized
  doAssert observed_context == "actual"
  doAssert observed_tool == "return_string"
  doAssert observed_output_kind >= 0

echo "vecherinka runtime execution: PASS"
