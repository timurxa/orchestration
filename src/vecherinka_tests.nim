{.experimental: "callOperator".}

import std/[deques, json, macros, options, sugar]
import vecherinka
import codex_json

type
  ImplementationRequest = distinct string
  Codebase = distinct Location
  Issues = distinct seq[string]
  Audit = object
    case ok: bool
    of true: discard
    of false: issues: Issues

proc `$`(value: Location): string {.borrow.}
proc `$`(value: Codebase): string {.borrow.}
proc `$`(value: Issues): string {.borrow.}

proc debug_generated_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  echo "test: generated transport called"
  dump request_id
  dump spec.output_kind
  dump spec.tools.len
  dump spec.prompt
  dump spec.materialized_input
  doAssert spec.tools.len == 1
  doAssert spec.tools[0].name == "finish_work"
  doAssert spec.tools[0].input_schema["type"].getStr == "object"
  doAssert not spec.materialize.isNil
  let decoded = spec.materialize(spec.output_kind, LlmOutput(
    tool_name: "finish_work",
    arguments: %*{"message": "generated"}))
  doAssert decoded.ok
  let rejected = spec.materialize(spec.output_kind, LlmOutput(
    tool_name: "finish_work",
    arguments: %*{"message": 42}))
  doAssert not rejected.ok
  let event = RuntimeEvent[A](
    kind: rev_model_artifact,
    request_id: request_id,
    output_kind: spec.output_kind,
    output: LlmOutput(
      tool_name: "finish_work",
      arguments: %*{"message": "generated"}),
    materialize: spec.materialize,
    tool_request_id: none(RequestId),
    output_meta: none(ArtifactMeta))
  enqueue_runtime_event(context, event)

const cheap = "gpt-5.6-luna".minimal

type
  Simple = object
    message: string

expandMacros: vecherinka(solve):
  > basic Simple ~> Simple {.entry.}:
    cheap[Simple, Simple]("Write a welcome message into 'message' field.")
  # > fix (Codebase, Issues) ~> Codebase {.entry.}:
  #   cheap[(Codebase, Issues), Codebase]("Read the issues and fix them in the codebase.")
  #
  # > audit (ImplementationRequest, Codebase) ~> Audit:
  #   cheap[(ImplementationRequest, Codebase), Audit]("Audit the codebase for issues based on the implementation request")
  #
  # > audit_fix_loop (ImplementationRequest, Codebase) ~> Codebase {.entry.}:
  #   fan(it((ImplementationRequest, Codebase)), audit) >>>
  #     (so(((ImplementationRequest, Codebase), Audit), Codebase, input) do:
  #       let ((req, code), audit) = input
  #       if audit.ok: pure(code)
  #       else: (req, (code, audit.issues)) >>>
  #         lift((ImplementationRequest, here))[fix] >>> audit_fix_loop)

let implementation_request = ImplementationRequest("")
let codebase = Codebase(Location(""))
let issues = Issues(@[""])
let simple = Simple(message: "Include 'duck' in your answer!!")

echo "test: calling generated solve"
solve(simple, debug_generated_transport)
echo "test: generated solve returned"
