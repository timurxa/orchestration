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

const manual_agent_prompts = AgentPromptTemplates(
  developer_instructions: checked_prompt(
    "Complete task. Call finish_work exactly once when done."),
  turn_prompt: checked_prompt(
    """$task

Complete task. Call finish_work exactly once when done.
You may modify only: $working_dir
Location values are paths relative to: $runtime_dir
Every Location must name an existing file or directory inside the working directory.$input""",
    "task", "input", "working_dir", "runtime_dir"))

type
  Simple = object
    message: string

expandMacros: vecherinka(solve, manual_agent_prompts):
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
let debug_sink: LogSink = proc(line: string) =
  echo "log: " & line
let debug_logger = new_structured_logger(
  debug_sink,
  run_id = "manual-test")

echo "test: calling generated solve"
let debug_value = solve(simple, logger = debug_logger)
echo "test: generated solve returned ", debug_value.message
