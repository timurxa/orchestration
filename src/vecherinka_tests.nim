{.experimental: "callOperator".}

import std/[deques, json, macros, sugar]
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
  dump spec.typed_context
  dump spec.tools.len
  doAssert spec.tools.len > 0
  doAssert not spec.materialize.isNil

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
  addLast(context.events, event)

const cheap = "gpt-5.6-luna".minimal

expandMacros: vecherinka(solve):
  > fix (Codebase, Issues) ~> Codebase {.entry.}:
    cheap[(Codebase, Issues), Codebase]("Read the issues and fix them in the codebase.")
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

echo "test: calling generated solve"
solve((codebase, issues), debug_generated_transport)
echo "test: generated solve returned"
