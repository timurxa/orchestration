# Reading a run in the TUI

Build from the repository root using the command in [AGENTS.md](../../AGENTS.md).
Open one schema-8 database:

```sh
tools/vecherinka-tui path/to/vecherinka.sqlite3
```

The viewer is read-only and refreshes once per second. Press `?` for the
controls.

## DAG

The left pane is a spatial view of actual runtime work. Each character is one
stored occurrence: `M` model, `R` reference, `A` raw value, `I` iterator, `S` SO
block, `F` fanout, `L` lift, or `J` join. Color shows state: green completed,
gold active or running, blue waiting, red failed, gray queued, and dark for
other states. The selected node is reverse video; direct neighbors are bold
and incident edges use the accent color. Names, IDs, and edge labels stay in
the detail pane to keep the topology readable.

Read edges downward. Their paths use `|`, `_`, `/`, and `\\`; `+` is a bend or
a branch/join between edges with a common source or target, `:` is a shared
stroke, and `X` is a crossing without a common endpoint. Long edges pass through
invisible routing points. These marks are a compact map,
not a substitute for the exact relation/position list shown for the selected
node. Ranks are longest-path layers; each persisted edge is routed from its
stored source to target. The canvas clips to the pane, so use uppercase
`H`/`J`/`K`/`L` to pan by a page.

Focus a node to see its full `flow_key`, artifact IDs, exact model request ID,
reference target, SO expansion, join, and slot. The detail list shows each
edge's direction, relation, position, and neighboring work ID. For example,
`branch[1] → #7 F` means this occurrence scheduled work #7 in branch slot 1;
`join_input[1] ← #7 F` means #7 supplied slot 1 to the selected join. IDs are
unique instances, so two `R` rows that call the same name remain separate
calls.

Use lowercase `h`/`l` to move to the nearest node left/right in the same rank;
`j`/`k` move to the nearest node below/above, preferring the closest rank and
then horizontal distance. Arrow keys are aliases. Use `[` for an incoming edge
and `]` for an outgoing edge; repeating a bracket cycles neighbors in stable
relation/position/ID order. Uppercase `H`/`J`/`K`/`L` pans a page. Selecting a
node reveals it; panning leaves focus unchanged. `i` or `Enter` opens related
records. `c` on a model occurrence opens only the conversation for that row's
request ID. `Tab` focuses the detail pane; `j`/`k`, `d`/`u`, and Page Up/Down
scroll it.

The edge direction is causal: references point to fresh callees; SO points to
its dynamic child; fanout/lift point to fresh slot work; branch terminals point
to a later join; and return edges point from completed callee work to a fresh
caller continuation. The IDs strictly increase along every edge, so this
persisted graph is acyclic. See the [formal DAG specification](vecherinka_tui_dag_spec.md).

A schema-7 database predates occurrence capture. Its artifacts, attempts,
events, and conversations remain inspectable, but its missing work DAG is
reported as unavailable rather than reconstructed from flow definitions.

## Model conversations

The transcript groups user messages, agent responses, tool calls, and command
output by stored session/thread/turn/item IDs. It keeps event IDs on each card,
shows developer instructions and the thread goal, and omits routine status
notifications and reasoning. Tool request/results are combined only with an
exact, unambiguous stored association. Enter opens raw event JSON; uppercase
`I` and `O` open the model input and output artifacts.

`j`/`k` selects a card. `d`/`u` or Page Down/Page Up scrolls the text while the
viewer refreshes. `[`/`]` changes worker-session generation. `S` means a direct
session link, `[R?]` request-only, `[T?]` thread-only, and `[!]` conflicting
association. No messages are paired by timestamp or similar text.

## Other screens

- `e`: all recorded protocol and run events.
- `f`: run/checkpoint/worker/attempt failures and uncertain writes.
- `t`: available application tables; Enter inspects a row.
- `g`: return to the DAG; `h`: back; `q`: quit.

For a live WAL database, keep its readable `-wal` and `-shm` files beside it.
