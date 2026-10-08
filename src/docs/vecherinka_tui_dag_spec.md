# Runtime work DAG

## Intention

Show the work that actually ran or is currently scheduled in one run, and let
the operator follow its causal edges. A vertex is one runtime occurrence. The
graph does not represent reusable flow definitions, and two calls to the same
reference target are two different vertices.

## Formal model

Let `V` be rows in `work_occurrence` and `E` rows in `work_edge`.

`v ∈ V` has a unique positive `work_id`, a descriptive `flow_key`, a work
`kind`, a lifecycle `state`, input and optional output artifact IDs, plus the
applicable model request, reference name, SO expansion, join, and slot IDs.
`flow_key` never identifies or merges vertices. Vertices are created only when
a meaningful work step is scheduled: reference, model call, raw value,
iterator, SO block, fanout, lift, or join. Top wrappers and pool bookkeeping
are omitted.

`e = (u, v, relation, position) ∈ E` means that occurrence `u` caused or
supplied occurrence `v`. Relations are `continue`, `reference_call`,
`so_child`, `branch`, `lift_item`, `join_input`, `return`, and `empty_join`.
`position` preserves branch and join-slot order. References point to fresh callee
occurrences. A return points forward from completed callee work to a fresh
caller continuation; it never points back to the caller's reference vertex.

Fanout and lift each have a start occurrence and a distinct join occurrence.
The start points to ordered child occurrences; each child terminal points to
the later join by `join_input`; the join points to the continuation. Empty
joins have an explicit `empty_join` edge from start to join. An SO occurrence
points to the dynamic child's first occurrence. The child terminal returns to
the fresh continuation and completes the SO occurrence.

## Acyclicity

IDs are allocated in causal creation order. Every edge must satisfy
`source_work_id < target_work_id`; both the runtime and SQLite check this. For
any directed path `v₀ → … → vₙ`, IDs strictly increase, so `vₙ` cannot equal
`v₀`. Therefore the persisted graph is a DAG, including recursive references
and every finite prefix of an interrupted run.

Work rows, edges, artifacts, model attempts, and the matching checkpoint are
committed in one SQLite transaction. The checkpoint saves the next ID and the
IDs needed by live invocations, returns, and join slots. Resume therefore
continues the same occurrence graph. An uncommitted transition leaves no rows
and reuses its IDs. A legacy database without these tables has no reliable
history of pure work or repeated reference instances; the viewer must say so
instead of reconstructing edges from flow definitions.

## TUI interpretation

There is one graph: `work_occurrence` joined to `work_edge`. Do not load
`workflow_node` or `workflow_edge` to create vertices, merge occurrences by
`flow_key`, infer joins from flow definitions, or show WORK/DATA/STRUCTURE
projections.

Render an interactive, top-down ASCII node-link canvas in the left pane. Each
stored `work_id` appears exactly once as one kind glyph: `M` model, `R`
reference, `A` raw, `I` iterator, `S` SO, `F` fanout, `L` lift, or `J` join.
Names and IDs stay in the selected-work pane so labels do not crowd topology.
Node color identifies lifecycle state; reverse video identifies focus. Direct
neighbors are bold and incident routes use the accent color.

Assign each vertex its longest-path rank:

`rank(v) = 0` for a root; otherwise `1 + max(rank(u) : (u,v) ∈ E)`.

Since every stored edge increases `work_id`, ranks are computed in one
increasing-ID pass and every edge points down. Initial order within a rank is
increasing `work_id`. Apply three deterministic downward/upward barycenter
sweeps; break equal scores by a stable key derived from the stored edge order.
Center each rank and place its points four columns apart. Separate ranks by six
rows. For an edge spanning ranks, insert one private, invisible routing point
in each skipped rank. These points are not vertices and cannot be selected.
Each stored edge therefore becomes a continuous path through adjacent ranks.

Use only single-cell ASCII node and stroke marks. Edge strokes are `|`, `_`,
`/`, and `\\`. A bend or branch/join between edges with a common stored source
or target is `+`; different edges sharing the same stroke are `:`; strokes
crossing without a common endpoint are `X`. Paint node glyphs last so a route cannot hide a vertex. Focus highlights the selected
vertex, its direct neighbors, and every incident edge. GraphTerm-style shared
routes can still be ambiguous in the overview; the selected-work pane remains
the exact edge ledger and lists every stored relation, position, direction,
and neighboring `work_id`.

The canvas is clipped to its pane, not to the terminal edge. Lowercase `h`/`l`
move to the nearest real node left/right in the same rank; `j`/`k` move to the
nearest real node below/above, preferring the closest rank, then horizontal
distance, then lower `work_id`. Arrow keys do the same. `[` follows incoming
edges and `]` follows outgoing edges; repeated presses cycle in stable
`(relation, position, neighboring work_id)` order. `H/J/K/L` pan by one
viewport page. Selecting an offscreen node pans just enough to reveal it;
panning does not change focus or graph membership. A too-small canvas displays a
resize hint while navigation still works. The canvas is recomputed from each
read snapshot, so live additions appear without changing the selected
`work_id`.

The detail pane shows full stored values, including `flow_key`, artifact IDs,
request ID, root name, expansion, join, and slot. `i`/`Enter` inspect related
records; `c` opens the conversation for the exact `request_id` on a model
occurrence. `Tab` focuses details; `j`/`k` scroll them there.

## Required behavior

1. Every persisted vertex appears once in the layout; equal `flow_key` values
   remain distinct.
2. Every stored edge has a continuous top-down route. Raster overlaps remain
   visible as `+`, `:`, or `X`; no route silently overwrites another route.
3. The selected-work pane lists every stored edge with its direction, relation,
   position, and endpoint identity.
4. Active, queued, waiting, completed, and failed occurrences are distinguishable.
5. A partial/interrupted run shows the rows committed with its latest checkpoint.
6. Each model occurrence opens only the conversation linked by its own request ID.
7. Missing legacy occurrence data is shown as unavailable, never inferred from
   static flow structure.
