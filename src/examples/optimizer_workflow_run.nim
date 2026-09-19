import std/os
import ../api/vecherinka
import ../optimizer_workflow

const
  default_original = "local-testing/src/main.cpp"
  optimizer_task =
    "Optimize the constraint model in local-testing/src/main.cpp without " &
    "changing exact output, feasibility, or public behavior. The source root " &
    "is read-only; modify only a fresh copy in the working directory. Build " &
    "with `cmake --build local-testing/build --target autoscheduler` and run " &
    "`local-testing/build/autoscheduler` for deterministic checks. Apply each " &
    "candidate to a fresh copy, compare it with the original and current " &
    "baseline, and report concrete counterexamples for any mismatch. Return " &
    "a unified diff for the accepted candidate. Every compile, harness, and " &
    "solver invocation must use exactly one worker and one CPU core."

when isMainModule:
  let original = if paramCount() == 0: default_original else: paramStr(1)
  if not fileExists(original):
    raise newException(IOError, "original source not found: " & original)
  if original.isAbsolute:
    raise newException(ValueError, "original must be relative to runtime root")

  let log_file = new_log_file_sink("optimizer-workflow.jsonl")
  let logger = new_structured_logger(log_file.sink, run_id = "optimizer-workflow")
  try:
    let result = run_optimizer(
      OptimizerInput(task: optimizer_task, original: Location(original)),
      100.0,
      logger)
    writeFile("optimizer-final.patch", result.final_patch_text)
    echo "iterations=", result.iterations,
      " exhausted=", result.exhausted,
      " counterexamples=", result.counterexamples.len
    echo "patch=optimizer-final.patch"
  finally:
    log_file.close()
