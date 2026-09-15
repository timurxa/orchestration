# Budget implementation state

Goal: implement `src/docs/vecherinka_budgeting_spec.md`.

## Progress windows

### Window 0 — initialized

- State file created.
- Active goal names this file.
- Next: inspect runtime/comptime seams and add budget/profile primitives.

### Window 1 — budget/profile primitives

- Added `Budget`, `ModelProfile`, fixed `profile_cost`, pool ledger, and
  model profile metadata.
- Replaced source/test model strings with enum profiles.
- Added runtime pool state propagation through continuations, refs, joins,
  `fan`, `lift`, and recursive activation paths.
- Compile checkpoint: `vecherinka_comptime_inclusion_test.nim` compiles.

### Window 2 — pool syntax and runtime API

- Added typed `pool(name)` markers and `pool name:` scoped lowering.
- Added inherited pool state, restoration across refs/recursion, and branch-local
  propagation through fan/lift/so.
- Added fixed model admission before dispatch and generated
  `solve(input, initial_budget, prompt_templates, ...)` parameters.
- Compile checkpoint: budget surface and existing stepping-stone source compile.

### Window 3 — local budget context and focused tests

- Added `BudgetContext` to runtime `so` execution and `so_budget` helpers.
- Added finite/non-negative pool validation and signed local pool remainder.
- Added focused ledger tests covering fixed costs, weighted capacities, overrun,
  hard global admission, and invalid configuration.
- Next: compile/run focused tests, review generated/runtime paths with subagents,
  then simplify any issues found.

### Window 4 — review fixes

- Subagent verification passed the focused surface, inclusion, stepping-stone,
  provenance, manual, and parallel compile checks; stepping runtime passed.
- Subagent review found shared mutable pool stacks, discarded legacy prompt
  defaults, weak runtime pool validation, and float-overflow validation gaps.
- Fixed all four: invocation-owned stack copies, preserved prompt defaults,
  canonical runtime pool validation, and explicit finite checks via `classify`.
- Final focused runtime test passes all cases; final compile sweep follows.

### Window 5 — overrun semantics

- Fresh review identified that pool overruns must reduce the current budget
  size and affect every pool's recalculated capacity.
- Added nominal capacities, cumulative overrun tracking, and weighted capacity
  recalculation after each admission; updated assertions and formal equations.
- Added runtime rejection for Nim-keyword pool names.
- Focused runtime suite passes all four tests; fresh subagent verification is
  the final gate.

### Window 6 — completed

- Fresh subagent test pass: budget runtime, budget surface, inclusion, and
  stepping-stone compile checks all exit successfully.
- Fresh simplification review found no safe reductions; explicit seq cloning is
  required by Nim mutability and retained.
- `git diff --check` passes. Generated binaries removed/restored.
- Canonical pool configuration remains compile-time; default-only callers use
  the existing prompt-template form or an explicit default pool tuple.
- Implementation complete.

### Window 7 — recursive arena demonstrations

- Added `src/tests/budget_recursive_arena_tests.nim` with deterministic fake
  model transport, 1:2 pool weights, and recursive `so_budget` stopping at
  local pool exhaustion.
- Sequence run: 3 default-pool calls then 6 wide-pool calls (budget 4.0,
  Luna/none cost 0.41).
- Parallel run: same 3/6 split, interleaved admissions, shared global budget.
- Rendered structured logs with `tools/artifact_graph.py` into
  `artifacts/budget_sequence.svg` and `artifacts/budget_parallel.svg`.

## Required verification

- Compile focused budget/profile tests.
- Compile and run existing relevant tests.
- Have subagents test the new surface and review simplification.
