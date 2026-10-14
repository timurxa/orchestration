# V2-02 implementation audit

> **Historical snapshot — before the final simplification pass.** Its audit
> findings remain useful gap evidence, but source details may refer to removed
> bounds/helpers or earlier graph declarations. Use the current simplification
> decision and implementation spec for the accepted interface.

**Review date:** 2026-10-12  
**Scope:** independent post-edit review of `WorkflowV2.Graph.fst` against P1;
cross-check of identity and build boundaries.  
**Status:** suitable for the requested human review of a declaration skeleton;
P1 is not proved.

## What the candidate now expresses

- `finite_typed_dag` makes vertices, partial label/input maps, output wire,
  and an explicit topological order first-order data.
- `dag_wf` states vertex uniqueness, order permutation, exact domains,
  prior-only edges, valid output references, and an existential typed witness.
- `wire_typing_witness` is syntax-directed and indexed by exact wire syntax,
  dependent family, and evaluator. Root, ordinary/indexed constants, prior
  output references, dependent pairs, and projections have explicit rules.
- `typed_node_sequence` describes a sequence whose node inputs are typed in
  the prior port context. `typed_graph_witness` relates that sequence exactly
  to the DAG projections.
- Removing `topological_order == [0..n-1]` avoids conflating occurrence keys
  with execution order. The order now independently witnesses acyclicity.

These are meaningful interfaces for the next proof stage. They do not
establish P1 by themselves.

## Proof and abstraction gaps

1. **Port semantics are trusted.** `port_context`, `port_env`, `port_ref`,
   `port_ref_key`, `eval_port_ref`, `root_port`, `extend`, and `prior_env` are
   abstract. There is no proved invariant that a port key is a vertex in the
   current prefix, that its evaluator returns that exact node's output, or
   that context extension preserves earlier ports. P1 soundness and
   completeness depend on these laws.
2. **Builder behavior is trusted.** `graph_builder`, `builder_nodes`,
   `start_graph`, and `add_node` are abstract. `start_graph_law`,
   `add_node_appends_exact`, and `finish_graph_sound` are admitted. The API
   signatures alone do not prove freshness, preservation of old nodes, or
   that output references target prior nodes.
3. **Graph nodes are not linked to the pinned registry.** `dag_wf` accepts a
   registry identity, but its `typed_graph_witness` can carry any
   `work_package`; the registry parameter does not prove that labels or
   constant codecs resolve in that snapshot. Indexed constants correctly
   retain the exact root index in their typing rule, but not registry
   membership/canonical decoding after recovery.
4. **Isomorphism erases the dependent proof state.** `graph_isomorphic`
   compares renamed keys, durable labels, and wire syntax. It does not
   transport dependent port contexts, existential work signatures, codec
   evidence, or typed evaluations. `graph_complete` returns this weaker
   structural relation and is itself admitted. It does not yet state the full
   typed, occurrence-preserving equivalence required by P1.
5. **Completeness and boundedness remain open.** `graph_complete` and
   `graph_complete_bounded` are admitted. `graph_fits_bounds` is assumed and
   belongs to V2-03. There is no checked induction translating an arbitrary
   well-formed DAG along its supplied topological order into builder calls.
6. **P0 still has constructor and host boundaries.** Work/codec registry
   records require uniqueness proof fields, but no closed constructor proves
   them. The same-snapshot bundle ties values within F* but does not prove
   runtime reload selects that bundle after restart.

## Independent review provenance

The graph-design review (`V2-02-graph-design.md`) motivated explicit wire
typing, root-indexed constants, arbitrary topological key order, and a
completeness induction over the stored order. The adversarial review
(`V2-01-02-adversarial.md`) supplied counterexamples for cycles, wrong input
types, duplicate occurrences, malformed encodings, and erased schema types.
The post-edit API audit independently found the remaining port, registry, and
typed-isomorphism gaps above. These reports are design/review evidence, not
proof evidence.

## Decision at the human gate

Accept V2-02 only as a top-down declaration milestone because the current task
explicitly asks to inspect the API and typed kernel before deeper proof work.
The normative P1 burden is unchanged: builder operations must be defined or
refined; assumptions must be discharged or reduced to named low-level
contracts; completeness must cover every admitted typed finite DAG; and typed
isomorphism must preserve dependent semantics and every occurrence. No claim
that those results are proven should be inferred from the successful module
check.
