{.experimental: "callOperator".}

import std/macros
import vecherinka

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

const cheap = "gpt-5.6-luna".minimal

type
  Simple = object
    message: string

expandMacros: vecherinka(solve):
  > basic Simple ~> Simple {.entry.}:
    cheap[Simple, Simple]("Write a welcome message into 'message' field.")
  # > fix (Codebase, Issues) ~> Codebase:
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
let debug_value = solve(simple)
echo "test: generated solve returned ", debug_value.message
