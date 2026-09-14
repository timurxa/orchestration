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

const cheap = "gpt-5.6-luna".medium

const manual_agent_prompts = AgentPromptTemplates(
  developer_instructions: checked_prompt(
    "Complete task. Call finish_work exactly once when done. Never narrate."),
  goal: checked_prompt(
    "Complete task. Call `finish_work` exactly once after completion. Put final result in finish_work arguments. Never narrate."),
  turn_prompt: checked_prompt(
    "$task\n\nComplete task. Never narrate. Call finish_work exactly once when done.\nYou may modify only: $working_dir\nLocation values are paths relative to: $runtime_dir\nInput Location values name provided files to read. Output Location values must be required files created inside $working_dir; return their relative filenames, never absolute paths, input paths, or file contents.$input",
    "task", "input", "working_dir", "runtime_dir"),
  finish_work_description: checked_prompt(
    "Submit final structured result. Call exactly once when task is complete."))

type
  Simple = object
    number: int

vecherinka(solve, manual_agent_prompts):
  > decrement Simple ~> Simple:
    cheap[Simple, Simple]("Output a new result with the input number decremented by 1 via the finish work tool call. Do not finish your turn before using the finish work tool.")
  > top_level Simple ~> Simple {.entry.}:
    so(Simple, Simple, input) do:
      if input.number <= 0: pure(input)
      else: input >>> decrement >>> top_level
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
let simple = Simple(number: 4)
let log_file = new_log_file_sink("manual-test.jsonl")
let debug_logger = new_structured_logger(
  log_file.sink,
  run_id = "manual-test")

try:
  echo "test: calling generated solve"
  let debug_value = solve(simple, logger = debug_logger)
  echo "test: generated solve returned ", debug_value.number
finally:
  log_file.close()
