# Vecherinka budgeting specification

This is the complete budgeting contract for the first implementation.

## 1. Budget and profile types

`Budget` is `float64` budget units. The generated procedure has this exact
signature shape:

```nim
proc solve(
  input: EntryDomain;
  initial_budget: Budget;
  prompt_templates: AgentPromptTemplates = macro_default_templates;
  transport: LlmTransport[Artifact] = nil;
  logger: StructuredLogger = nil
): EntryCodomain
```

`initial_budget` is required, finite, and non-negative. Invalid values are
rejected before execution starts.

`ProfileSpec.model` is an enum, not a string:

```nim
type ModelProfile = enum
  luna, terra, sol, astra
```

The existing effort value remains part of `ProfileSpec`. A model request has a
fixed cost determined only by `(ModelProfile, ReasoningEffort)` through this
authoritative procedure:

```nim
proc profile_cost(model: ModelProfile; effort: ReasoningEffort): Budget
```

The cost must be finite and non-negative. One model-node invocation incurs one
charge. Protocol turns, tool messages, and transport retries incur no
additional Vecherinka charge.

Current cost table (`none`, `low`, `medium`, `high`, `xhigh`, `max`):

```text
             none  low    medium  high   xhigh  max
luna         0.41  0.33   0.61    1.18   1.22   2.32
terra        4.77  4.12   5.91    9.66   10.27  36.24
sol          9.25  10.93  15.12   18.92  31.15  58.46
astra        --    5.58   7.17    17.33  31.59  54.87
```

`astra/none` is invalid. `minimal` is compatibility alias for `none`.

Before dispatching a model request, the runtime charges its fixed cost. If the
cost is greater than global remaining budget, the entire plan fails and the
request is not dispatched.

Pure nodes, `it`, `fan`, `lift`, flow references, and `so` itself have zero
budget cost. `so` may choose whether to create model work; each resulting model
request is charged normally.

## 2. Pool declaration

Pools are declared as a compile-time array of named `(string, float64)` tuples
and passed to `vecherinka`:

```nim
const pool_weights = [
  (name: "default", weight: 3.0),
  (name: "planning", weight: 1.0),
  (name: "implementation", weight: 2.0),
  (name: "verification", weight: 1.0)
]

vecherinka(solve, pools = pool_weights):
  ...
```

The exact declaration type is:

```nim
type PoolWeight = tuple
  name: string
  weight: float64
```

The value must be compile-time data. Runtime `Table`, `OrderedTable`, arbitrary
objects, and positional tuples are rejected. Pool declaration order has no
semantic meaning.

The macro forms are:

```nim
vecherinka(solve, pools = pool_weights)
```

Pool weights are compile-time configuration. Prompt templates are supplied at
runtime through `solve`; Vecherinka passes the same templates to every model
request in that invocation. A single default pool is expressed with
`[(name: "default", weight: 1.0)]`.

Pool names must be non-empty ASCII identifiers matching
`[A-Za-z][A-Za-z0-9_]*`. Canonical comparison lowercases ASCII letters and
removes underscores. Therefore `Implementation`, `implementation`, and
`implement_ation` are duplicates. Duplicate canonical names, Nim keywords,
and `pool` are compile-time errors. `default` is mandatory.

Weights must be finite `float64` values greater than or equal to zero. The
total weight must be finite and greater than zero. Zero-weight pools are valid:
they have zero nominal capacity but may run when explicitly selected.

## 3. Pool switching

Every executable flow node belongs to exactly one pool.

Unmarked nodes belong to `default`. Pool selection is an explicit zero-cost
flow node:

```nim
a >>> pool(implementation) >>> b
```

`pool(name)` accepts one bare identifier. The identifier is normalized using
the pool-name rules above; unknown names are compile-time errors. String
markers, such as `pool("implementation")`, are rejected.

The selected pool applies to the current linear continuation until another
`pool(name)` marker appears. A scoped form avoids repeated resets:

```nim
pool implementation:
  prepare >>> inspect >>> summarize
```

The scoped form restores the previous pool after its body. It is equivalent to
an implicit pool switch at entry and restoration at exit. Its body is one flow
expression; compose multiple steps with `>>>`.

Every dynamic invocation carries an effective pool. A called flow inherits the
caller's pool; callees never select a pool themselves. A pool switch inside a
callee affects only that activation and restoration through the continuation
returns to the caller's pool. Recursion repeats these rules.

`fan` and `lift` copy the active pool independently into every branch. A
switch in one branch cannot affect siblings. A switch before a composite node
affects all of that node's branches. `so`-returned flows inherit the active
pool unless they contain an explicit switch.

Pool selection does not select or replace a model profile. Application code
retains full control of profile and effort choices. Ordinary procedures have no
pool semantics.

## 4. Capacity accounting

Let:

```text
N       = initial_budget
W       = sum of all declared pool weights
C0[i]   = N * weight[i] / W       # nominal capacity
S[i]    = cumulative charged cost for pool i
O       = sum(max(0, S[i] - C0[i]))
T       = N - O                    # current budget size
C[i]    = T * weight[i] / W       # recalculated capacity
G       = N - sum(S[i])
R[i]    = C[i] - S[i]
```

`C0[i]` is calculated once at plan start. If a pool exceeds `C0[i]`, its
overrun reduces `T`, and all current capacities `C[i]` are recalculated from
the declared weights. Early completion never increases `T`; unused capacity is
stranded. There is no pool-to-pool credit transfer.

`R[i]` is signed. A negative value means that pool has exceeded its nominal
capacity. Pool capacity is not an independent hard limit: an over-capacity
pool may continue using global budget while `G` remains sufficient. Its extra
charges reduce `G`, thereby reducing what every other pool can still execute.
Zero-weight pools have zero nominal capacity but may still spend global budget.
Admission uses exact `cost <= G` comparison; no epsilon is applied.

Global budget is the only hard limit. The runtime must serialize budget
admission and charge a model request atomically before dispatch. Every ready
invocation receives a monotonically increasing sequence number when enqueued;
admission processes ready work by that sequence. Queued work reserves no
budget. Transport execution may remain parallel, but admission cannot
overspend and is deterministic.

If `G == 0`, the plan succeeds only if all already-dispatched work can finish
without another positive-cost request. Any later positive-cost request fails.

## 5. `so` budget context

The context-taking `so` overload receives an immutable `BudgetContext` snapshot
immediately before its callback executes:

```nim
type BudgetContext = object
  pool_name*: string
  pool_weight*: float64
  pool_capacity*: Budget
  pool_spent*: Budget
  pool_remaining*: Budget  # R[i], may be negative
  global_remaining*: Budget # G, never negative
```

The context is a snapshot taken when that `so` node executes. It describes the
node's effective inherited pool. Code may branch on it and explicitly choose
any `ModelProfile` and effort. No automatic profile downgrade or upgrade is
performed by Vecherinka.

No budget context is passed to zero-cost nodes unless the node explicitly uses
the context-taking `so` overload.

The context-taking helpers are:

```nim
so_budget(Domain, Codomain, input, budget_context) do:
  ...

so_budget(Domain, Codomain, input, working_dir, budget_context) do:
  ...
```

The existing `so` overloads remain available with only `input`, or with
`input, working_dir`, and do not receive budget context.
The flow returned by the callback inherits the current pool unless its
body contains an explicit `pool(name)` switch.

The ledger belongs to one `WorkPlan` and is created by `init_work_plan` before
ready work starts. `execute_flows` passes `initial_budget` and pool weights into
that ledger. Model admission calls `profile_cost`, checks global remaining
budget, then updates pool spent, global remaining, and recalculated capacities
before dispatch. Admission failure marks plan terminal; transport is never
called for rejected request.

## 6. Runtime invariants

The runtime must preserve these invariants:

1. `sum(S[i])` equals the cost of every model request admitted so far.
2. `G == N - sum(S[i])` and `G >= 0` after every admission.
3. Every dynamic invocation has exactly one inherited pool.
4. Nested flow activations restore the caller's pool after return.
5. Recursion shares the same global ledger and the relevant pool accounts.
6. A failed budget admission produces one plan-wide failure; no later work is
   dispatched.

After failure, the plan is terminal. Already-running transport work may report
completion, but those completions are ignored and no new work is admitted.

Ready invocations carry owner-thread state in `pending_ready`; event channel
transports only ready IDs. `next_ready_id` assigns increasing IDs at enqueue.
The coordinator consumes IDs and performs admission, so budget mutation is
serialized even when transport work runs concurrently. Invocation pool stacks
are copied when stored and when restored, preventing branch or recursion aliasing.

Budget accounting belongs to one `solve` invocation. Recursive activations do
not receive fresh budgets. A zero-cost recursive loop remains a normal
nontermination and is not detected by budgeting.

The generated `solve` result reports the existing failure mechanism with a
budget-exceeded message identifying the pool, model, effort, requested cost,
nominal capacity, and global remaining budget.
