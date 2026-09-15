{.experimental: "callOperator".}

import std/[json, macros, options, os]
import ../api/vecherinka
import ../api/codex_json

type BudgetItem = object
  ticks: int

const
  one_step = luna.none
  arena_weights = [
    (name: "default", weight: 1.0),
    (name: "wide", weight: 2.0)]

proc immediate_transport[A](
    context: RuntimeContext[A];
    request_id: RequestId;
    spec: LlmCallSpec[A]
) =
  ## Deterministic model substitute: every reached model returns one value.
  enqueue_runtime_event(context, RuntimeEvent[A](
    request_id: request_id,
    kind: rev_model_artifact,
    output_kind: spec.output_kind,
    output: LlmOutput(
      tool_name: "finish_work",
      arguments: %*{"ticks": 0}),
    materialize: spec.materialize,
    tool_request_id: none(RequestId),
    tool_binding_id: none(uint64),
    output_meta: none(ArtifactMeta)))

expandMacros: vecherinka(solve_sequence, pools = arena_weights):
  > work_sequence BudgetItem ~> BudgetItem:
    one_step[BudgetItem, BudgetItem]("consume one budget unit")
  > loop_sequence BudgetItem ~> BudgetItem:
    so_budget(BudgetItem, BudgetItem, input, budget) do:
      if budget.pool_remaining >= profile_cost(luna, one_step.effort):
        input >>> work_sequence >>> loop_sequence
      else:
        pure(input)
  > sequence_entry BudgetItem ~> BudgetItem {.entry.}:
    pool(default) >>> loop_sequence >>> pool(wide) >>> loop_sequence

expandMacros: vecherinka(solve_parallel, pools = arena_weights):
  > work_parallel BudgetItem ~> BudgetItem:
    one_step[BudgetItem, BudgetItem]("consume one budget unit")
  > loop_parallel BudgetItem ~> BudgetItem:
    so_budget(BudgetItem, BudgetItem, input, budget) do:
      if budget.pool_remaining >= profile_cost(luna, one_step.effort):
        input >>> work_parallel >>> loop_parallel
      else:
        pure(input)
  > parallel_entry BudgetItem ~> (BudgetItem, BudgetItem) {.entry.}:
    fan(
      pool(default) >>> loop_parallel,
      pool(wide) >>> loop_parallel)

proc run_case(mode, log_path: string) =
  let sink = new_log_file_sink(log_path)
  let logger = new_structured_logger(sink.sink, run_id = mode)
  try:
    if mode == "sequence":
      discard solve_sequence(BudgetItem(ticks: 0), 4.0,
        default_agent_prompt_templates,
        transport = immediate_transport, logger = logger)
    elif mode == "parallel":
      discard solve_parallel(BudgetItem(ticks: 0), 4.0,
        default_agent_prompt_templates,
        transport = immediate_transport, logger = logger)
    else:
      raise newException(ValueError, "mode must be sequence or parallel")
  finally:
    sink.close()

if paramCount() != 2:
  raise newException(ValueError, "usage: budget_recursive_arena_tests MODE LOG")
run_case(paramStr(1), paramStr(2))
