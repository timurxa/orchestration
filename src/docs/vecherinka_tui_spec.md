# Vecherinka SQLite TUI

## Purpose

The TUI is a read-only C/termbox2 viewer for a Vecherinka SQLite run. It shows
one runtime work DAG, its artifacts and model conversations, run events,
failures, and application records. Its DAG comes only from `work_occurrence`
and `work_edge`; it does not draw reusable workflow definitions.

Build and run at the repository root:

```sh
cc -std=gnu11 -D_DEFAULT_SOURCE -Wall -Wextra -Wpedantic \
  -Itools/vendor tools/vecherinka_tui.c -lsqlite3 -o tools/vecherinka-tui
tools/vecherinka-tui path/to/vecherinka.sqlite3
```

The viewer opens SQLite read-only and refreshes once per second. Live WAL reads
need readable `-wal` and `-shm` sidecars beside the database. Press `?` for
visible controls.

## Runtime DAG

The left pane is an interactive, top-down ASCII node-link canvas. It draws one
single-character kind glyph for each stored occurrence. Names and IDs stay out
of the topology; the right pane identifies the selected occurrence and lists
all of its exact incoming and outgoing edges, including direction, relation,
position, and neighboring occurrence ID. The graph is laid out from the stored
`work_occurrence` and `work_edge` rows; it never reconstructs flow templates or
merges occurrences.

Kind glyphs: `M` model call, `R` reference call, `A` raw value, `I` iterator,
`S` SO block, `F` fanout, `L` lift, `J` join. Node color identifies lifecycle:
green completed, gold active/running, blue waiting, red failed, gray queued,
and dark foreground for other states. Direct neighbors are bold; incident
edges use the accent color. An active model overlay requires its exact request to have a
starting/working session, a nonterminal attempt, a running execution, and a
heartbeat no older than six seconds. For a live model request the detail pane
shows both the `active` overlay and stored scheduler state (often `waiting`
while the model responds).

Rank is longest path from any root. Since stored edges increase in `work_id`,
one increasing-ID pass computes ranks and every edge points down. Three stable
down/up barycenter sweeps order each rank; long edges use private routing
points. Edge paths use `|`, `_`, `/`, and `\\`. `+` marks a bend or branch/join
between edges with a common stored source or target, `:` marks distinct edges
sharing a stroke, and `X` marks strokes crossing without a common endpoint.
Occurrence glyphs are painted over routes. A route collision therefore stays
visible instead of silently replacing another edge.
The selected node is reverse video, its direct neighbors and incident edges
are highlighted, and other node colors indicate lifecycle state. Because
bundled routes can be ambiguous, the right pane remains the exact edge ledger.

Lowercase `h`/`l` move focus to the nearest node left/right in the same rank;
`j`/`k` move to the nearest node below/above, preferring the closest rank and
then horizontal distance. Arrow keys are aliases. `[` follows incoming edges
and `]` follows outgoing edges; repeated presses cycle through stable
relation/position/ID order. Uppercase `H`/`J`/`K`/`L` pan by a viewport page.
Selecting an offscreen node reveals it, while panning leaves focus unchanged.
`i` or `Enter` opens related records. `c` opens the conversation for the
selected model occurrence's exact `request_id`. The detail pane includes its
input and output artifact IDs, request, reference target, SO expansion, join,
and slot. `Tab` focuses details; `j`/`k` scroll details there, and `d`/`u` page
them.

Schema-7 databases remain readable, but they predate occurrence capture and
show an explicit unavailable-DAG message. The viewer does not reconstruct
repeated references, pure work, or causal edges from workflow definitions.
Runs created or resumed by schema 8 record the occurrence DAG.

## Worker conversation

`c` on a model occurrence opens its exact request's latest worker-session
generation. The screen groups stored `conversation_event.raw_json` into one
chronological transcript:

- User cards group `item/started` and `item/completed` by exact item ID.
  `turn/start.params.input` is used only when no user-message item was stored.
- Agent cards join deltas by exact thread, turn, and item IDs. A completed item
  supplies final text; otherwise the card is marked in progress.
- Tool requests and results pair only by exact RPC ID inside the selected
  session. A `dynamicToolCall` joins only on exact call ID and compatible turn.
  Missing or ambiguous matches remain separate.
- Command execution is shown as one command card with its output and status.
  Reasoning and routine status, account, and token notifications are omitted.
  Unknown or malformed messages remain inspectable as unparsed events.

Each card retains its source event IDs. Enter opens a source event's raw JSON.
The heading keeps model input/output artifact IDs visible; `I` and `O` open
those artifacts. Developer instructions and the thread goal appear as context
cards. The model input artifact is not duplicated as a chat message.

Direct session links are marked `S`; unique request-only and thread-only links
are marked `[R?]` and `[T?]`; conflicting associations are marked `[!]` and
excluded from pairing. No association is inferred by timestamp or text
similarity. Parsing happens in memory; stored JSON is unchanged.

`j`/`k` selects transcript cards; `d`/`u` or Page Up/Down scrolls text. Enter
inspects a source event, `[`/`]` switches worker generations, and `I`/`O` opens
the request input/output artifacts. Refresh preserves the selected event and
scroll position as new messages arrive.

## Other screens

- `e` shows the run-wide event stream.
- `f` shows run, checkpoint, worker, attempt, and uncertain-write failures.
- `t` browses available application tables; Enter inspects a row.
- `g` returns to the DAG, `h` returns from a detail screen, and `q` exits.

The viewer writes no run data. It reports database state; a heartbeat does not
prove an operating-system process is alive.
