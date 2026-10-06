# Vecherinka budgeting contract

`Budget` is a `float64` scheduling unit. `solve(input, initial_budget, ...)`
requires a finite, non-negative initial budget; templates, transport, and
logger are optional. This ledger limits admitted model work using fixed
estimates. It does not measure provider charges, tokens, or transport retries.

## Profiles and fixed costs

Profiles use `ModelProfile = luna | terra | sol | astra` plus a
`ReasoningEffort`. `profile_cost(model, effort)` is the authoritative fixed
cost. One model-node invocation is charged once before dispatch; protocol
turns, tool messages, and retries add no charge. If the fixed cost exceeds
global remaining budget, the plan fails without dispatching the request.

| Profile | none | low | medium | high | xhigh | max |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| luna | 0.41 | 0.33 | 0.61 | 1.18 | 1.22 | 2.32 |
| terra | 4.77 | 4.12 | 5.91 | 9.66 | 10.27 | 36.24 |
| sol | 9.25 | 10.93 | 15.12 | 18.92 | 31.15 | 58.46 |
| astra | invalid | 5.58 | 7.17 | 17.33 | 31.59 | 54.87 |

`minimal` aliases `none`; `astra/none` is invalid. Pure nodes, `it`, `fan`,
`lift`, flow references, and `so` cost zero. Model work returned by `so` is
charged normally.

## Pools

Declare compile-time named `(string, float64)` tuples; `default` is required.
Names must match `[A-Za-z][A-Za-z0-9_]*`; comparison lowercases ASCII and
removes underscores. Canonical duplicates, Nim keywords, and `pool` are
rejected. Weights must be finite and non-negative; their finite sum must be
positive. A zero-weight pool may still use global budget when selected.

```nim
const pools = [
  (name: "default", weight: 3.0),
  (name: "research", weight: 1.0)]

vecherinka(solve, pools = pools):
  ...
```

Runtime tables, objects, and positional tuples are not accepted. Declaration
order has no meaning. An unmarked node uses `default`; switch the linear
continuation with `a >>> pool(research) >>> b`, or scope a body with
`pool research: a >>> b`. Pool names are bare identifiers, not strings.
Scopes restore the caller's pool. Called flows inherit the active pool;
`fan`/`lift` copy it per branch; `so` results inherit it unless switched.
Pool selection never changes model or effort. See the DSL guide for syntax.

## Admission and capacity

For initial budget `N`, total weight `W`, pool weight `w[i]`, spend `S[i]`,
and cumulative charges:

```text
C0[i] = N * w[i] / W                 # nominal capacity, fixed at start
O     = sum(max(0, S[i] - C0[i]))    # total nominal overrun
T     = N - O
C[i]  = T * w[i] / W                 # recalculated capacity
G     = N - sum(S[i])                # global remaining; hard limit
R[i]  = C[i] - S[i]                  # signed pool remaining
```

Overrun reduces every pool's recalculated capacity; unused capacity is
stranded and never transferred. Pool capacity is not a hard limit: an
over-capacity pool may continue while `G` covers the next fixed charge. Only
`G` prevents dispatch. Admission uses exact `cost <= G` with no epsilon.

Ready work receives an increasing enqueue sequence. The coordinator admits it
in sequence order and charges atomically before dispatch; queued work reserves
nothing. Transport may run concurrently. If `G` is exhausted, the plan can
finish only if dispatched work needs no further positive-cost model request.
Budget failure is plan-wide; no later work is admitted.

## `so` budget context

The context-taking `so` overload receives this immutable snapshot immediately
before its callback:

```nim
type BudgetContext = object
  pool_name*: string
  pool_weight*, pool_capacity*, pool_spent*: Budget
  pool_remaining*: Budget   # R[i], may be negative
  global_remaining*: Budget # G, never negative
```

Available forms include:

```nim
so_budget(A, B, input, budget) do: ...
so(A, B, input) do: ...
```

`so` callbacks receive complete typed values and have no filesystem or storage
handle. SQLite resume replays a callback to reconstruct the graph it returned,
so callbacks must be deterministic and side-effect free. `so_budget` receives
the exact immutable snapshot that is saved with the expansion. The returned
flow inherits the current pool unless it switches explicitly. Blob paths exist
only in a temporary model-call workspace.

The snapshot reports the effective pool and current ledger values; no
automatic model downgrade or upgrade occurs. All recursive activations share
one ledger. A zero-cost recursive loop is not detected by budgeting.
