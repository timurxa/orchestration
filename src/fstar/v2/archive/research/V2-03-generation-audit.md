# V2-03 generation and allocation audit

## Conclusion

`GeneratorRef` has correct nominal indices for input and output family, but its
result type does not prove descriptor validity. `GraphDesc i o x` stores an
ordinary finite node list and `Wire i x`; its output family `o` is phantom in
the record. A generator can return a value at exactly the requested indices
whose wires are ill-typed, cyclic, dangling, duplicated, or resolve to work
outside the pinned registry. `graph_wf` is intended to reject these values,
but current source witness omits exact registry membership for work and
constant codecs. The generation commit needs an explicit checked-result
contract before P4/P5/P8 can be stated as source-level facts.

Allocation story is conceptually coherent if one rule stays strict: the
`GenerationAllocation` passed to a generator must be read from the exact
pending occurrence's replayed ledgers, never chosen by a caller. `GraphCommitted`
then records one child allocation plan; replay validates that plan against the
parent allowance and derives both ledgers from it. Keep allocation data out of
`GraphDesc` bytes. No graph-size/depth/encoded-byte bound is needed: finite
`list` gives mathematical finiteness; expansion fuel governs only nested
generator expansion, charge governs external maximum charges.

## Source facts and current gaps

- `WorkflowV2.Kernel.fst:141-158` defines `generation_allocation` as two
  naturals. `generator_ref.generate_graph` accepts any allocation record and
  returns only `graph_desc input output x`. No precondition ties the argument
  to ledger state; no postcondition states `graph_wf` or an allocation plan.
- `WorkflowV2.Kernel.fst:84-87` defines `graph_desc` as a list of first-order
  nodes plus output wire. Its `output` family is absent from the fields. The
  input and `x` indices constrain wire syntax but not whether the output wire
  has type `output x`.
- `WorkflowV2.Graph.fst:469-486` defines `dag_wf`/`graph_wf`. It checks unique
  keys, vertex/order set equality, exact label/input domains, topological
  references, output references, and existence of `typed_graph_witness`.
  Thus graph validity is a meaningful check, not an alias for `True`.
- `WorkflowV2.Graph.fst:455-467` typed witness ties typed node sequence and
  output wiring to the DAG syntax. However, it contains no `WorkMember
  registry node_work` or equality proving a node's durable reference resolves
  to that exact work in this bundle. `ConstantWireTyping` at lines 172-182
  similarly carries a codec/value but no codec-membership witness. The
  comment at 450-454 acknowledges the registry gap. A witness for some work
  with a matching-looking label is insufficient for P0/P2/P4.
- `WorkflowV2.Graph.fst:143-158` leaves port context/environment/ref and
  evaluation as assumptions. `graph_wf` depends on this trusted boundary until
  port membership, lookup, and evaluation laws are proved.
- `WorkflowV2.Kernel.fst:126-136` gives `graph_codec` only roundtrip and
  canonical-byte laws. It does not prove decoded descriptors are `graph_wf`
  under the journal's pinned bundle. A codec may round-trip an invalid graph.
- `WorkflowV2.Identity.fst:228-232` records bundle identity and work/value
  codec registries; current declarations do not establish exact manifest
  binding. Graph-codec registry resolution is also not represented here.
- `WorkflowV2.Journal.fst:30-37,47-60` represents allocation plans as lists of
  `(NodeOccurrence, GenerationAllocation)` and places one list on each
  `RunStarted`/`GraphCommitted`. List type alone does not enforce unique keys,
  exact node domain, or work-kind-specific allocations. Replay is explicitly
  still open at lines 101-109.
- Spec §2.2 lines 345-350 has the same raw generator return. §2.2 lines
  492-526 provides intended `graph_wf`, positive child fuel, charge split,
  exact ledger-derived allocation, and pure total pinned generation. §4.1
  lines 684-693 makes child plan and graph bytes one `GraphCommitted` payload.
  §4.2 lines 760-765 requires validation before commit. P2/P4/P5/P8/P12 are
  theorem targets, not established facts (`implementation_spec.md:1013-1023`).

## Minimal contract

Separate three values: graph descriptor, checked graph evidence, and per-node
allocation plan. Evidence is reconstructed in memory; never serialize proof
objects. Graph bytes contain descriptor only. One event stores descriptor bytes
and child plan exactly once.

A useful F*-shaped contract is:

```fstar
noeq type generated_graph
    (registry:pinned_registry_bundle)
    (input:Type0) (output:input -> Type0) (x:input) = {
  descriptor:graph_desc input output x;
  descriptor_wf:graph_wf registry x descriptor
}

// Exact graph commitment plan for the newly introduced child occurrence.
val allocation_plan_wf :
  registry:pinned_registry_bundle ->
  parent:node_occurrence -> parent_allowance:generation_allocation ->
  graph:graph_desc i o x -> plan:allocation_plan -> Tot prop

noeq type generated_commit
    (registry:pinned_registry_bundle)
    (input:Type0) (output:input -> Type0) (x:input)
    (parent:node_occurrence)
    (parent_allowance:generation_allocation) = {
  generated:generated_graph registry input output x;
  child_plan:allocation_plan;
  child_plan_wf:allocation_plan_wf registry parent_occurrence
    parent_allowance generated.descriptor child_plan
}
```

Then choose one of these equivalent proof interfaces:

1. A registry-bound generator wrapper whose `generate` returns
   `generated_commit registry ...`, with membership evidence showing this
   exact generator and its codecs resolve through that exact bundle; or
2. A raw `GeneratorRef` plus a `GeneratorMember registry generator` proof
   containing the universal theorem that every returned descriptor is
   `graph_wf` under that registry, plus a separately checked plan theorem.

Prefer the registry-bound wrapper at the runner boundary. It prevents a
well-typed descriptor from silently carrying references from another registry.
Keep `GeneratorRef` reusable if desired, but require membership/refinement
proof before calling it for a journal state. Do not use `assume graph_wf`.
Builder-based generation can produce the evidence from `finish_graph_sound`
once P1 is proved; arbitrary hand-built records require a direct `graph_wf`
proof. In either design, witness must establish:

- `descriptor : GraphDesc i o x` at the exact reconstructed `x` and output
  family `o`;
- each node's exact `Work` resolves from the same pinned bundle and its
  durable label is derived from that work;
- every constant codec resolves from that bundle and bytes decode canonically
  at exact root index `x`;
- every wire is typed in the preceding-node port environment; output wire has
  exact type `o x`;
- graph keys are unique, all references resolve, node edges point strictly
  earlier, finite topological order covers exactly the nodes.

Generation theorem should quantify over the exact pinned entry and ledger
allocation:

```fstar
val generate_graph_sound :
  registry:pinned_registry_bundle ->
  generator:generator_ref i o ->
  member:GeneratorMember registry generator ->
  occurrence:node_occurrence ->
  state:State ->
  input:i ->
  input_reconstructed:input == generator_input_at state occurrence ->
  allocation:generation_allocation ->
  allocation_exact:
    allocation == generation_allocation_at state occurrence ->
  Tot (result:generated_commit registry i o input allocation /\
       result.generated.descriptor ==
         generator.generate_graph input allocation)
```

Make `allocation_exact` an action constructor/precondition, not a caller
boolean that is trusted. Better action API derives it internally:

```fstar
val generate_action : state:State -> occurrence:PendingGenerator state
  -> Tot (g:GeneratedCommitFor state occurrence)
```

where `GeneratedCommitFor` carries the state-derived input, generator, exact
fuel/charge lookup, valid graph, and valid plan. This makes over-allocation
unrepresentable at the runner boundary.

## Allocation plan invariant

Define plan semantics as a finite-support map, even if serialized as a list.
Prove list keys unique and domain exactly the new graph's global
`NodeOccurrence`s. Reject duplicate, omitted, stale, parent, or unknown
occurrences. For each node in graph:

- Local work: `(fuel, charge) = (0, 0)`.
- External work: `fuel = 0`; `charge = pinned maximum_charge`.
- Generator work: `fuel >= 1`; its charge field is the child-generator pool
  allowance (possibly zero if fallback-only generation is legal).

For parent allowance `(b, c)`, require:

```text
sum(child generator fuels) < b
sum(direct external maximum_charge + child generator charge pools) <= c
```

The unused charge returns to `free`; fuel difference `b - sum(child fuels)`
is consumed. Root plan has same exact-domain/work-kind checks against total
budget. Every pending generator in every reachable state must have positive
fuel. Every pending external node must have its exact maximum charge reserved
or allocated. These are the concrete premises behind P8 and P12, not optional
shape policies. Generator's total result contract must always produce a valid,
affordable graph and plan; when intended external paths do not fit the
allowance, it must produce a fallback in its declared output family with a
valid plan, or the state can be stuck despite `generate_graph` being `Tot`.

The ledgers are the only authority:

1. `RunStarted` commits root graph bytes, budget, and root allocation plan.
2. Generator action obtains allocation only by lookup in current replayed
   `FuelAllocations` and `ChargeAllocations`.
3. `GraphCommitted` commits generated graph bytes and one child plan.
4. Replay validates exact graph plus plan, removes only parent occurrence's
   allocations, installs unique child entries, and returns unused resources.
5. `CallIntent` reads the exact adapter occurrence charge entry; it never
   accepts a caller-supplied reservation.

Do not put child allocations in `GraphDesc` and repeat them in
`GraphCommitted`. If allocation is selected by a pure planner rather than
returned by generator, pin that policy or commit its output once and validate
it. Open design choice: should valid child plans be deterministic functions of
`(GraphDesc, parent allowance, pinned allocation policy)`, or can runner
choose any legal plan and commit it? Either is sound for replay if the exact
plan is in the event, but deterministic planning simplifies P13 and debugging.

## Required theorem spine

**P2 graph-codec/refinement:** For pinned `registry`, exact codec, input `x`,
and bytes `b`, decoding must yield a raw descriptor at indices `(i,o,x)`;
resolution reconstructs `graph_wf registry x g`. Roundtrip/canonicality alone
is insufficient.

```fstar
val decode_graph_resolved :
  registry:pinned_registry_bundle -> codec:GraphCodec i o ->
  codec_member:GraphCodecMember registry codec -> x:i -> b:bytes ->
  Tot (option (g:graph_desc i o x & graph_wf registry x g))
```

Require accepted bytes re-encode identically. Exact node types, work references,
constant values, root index, and output-family index survive reconstruction.
Proof evidence is recomputed from bytes plus exact registry; it is not stored.

**P4 commit-before-use/global-DAG preservation:** If pending occurrence `k`
resolves to pinned generator `gen`, reconstructed input is `x`, and the
allocation lookup is `a`, then an accepted `GraphCommitted(k, bytes, plan)`
must establish all of:

```text
g = gen.generate_graph x a
bytes = encode_graph(gen.graph_codec, x, g)
graph_wf registry x g
plan_wf registry k a g plan
new child occurrences are exactly namespace(k, g.vertices)
no child action is enabled before this event
GlobalDag(S') and occurrence uniqueness hold
```

The final two clauses need the global substitution lemma: replace one
zero-boundary generator vertex, whose typed output is `o x`, with the child DAG
whose typed interface is the same `(x, o x)`. Preserve cross-boundary wires,
namespace local keys by graph occurrence, and inherit child strict topological
rank. Local acyclicity alone does not prove global DAG preservation.

**P5 exact recovery:** After accepted commit, recovery decodes the exact
committed graph bytes using the codec identity pinned by the parent generator,
reconstructs exact typed/work/constant witnesses, and restores the committed
allocation plan. It does not call `generate_graph`. This depends on P2,
canonical journal decoding, stable registry/codec manifests, and every-cut
store premises.

**P8 ledger safety:** Induct over legal events. For each `GraphCommitted`, prove
plan-domain uniqueness/exactness, parent lookup exists once, each child key is
fresh, child fuel positive, nested fuel sum strictly below parent, charge sum
within parent, and exact per-work-kind allocation equations. `RunStarted`
proves analogous root-plan equations. `CallIntent` and `CallOutcome` preserve
separate finite maps and conservation. Duplicate `AllocationPlan` list entries
must be rejected before conversion to a map.

**P12 progress:** With finite-support fuel map and exact unique plans, let
`G(S) = sum fuel_allocations(S)[k]` for pending generator occurrences. If
parent `b > 0`, every child fuel `b_j > 0`, and `sum b_j < b`, then each
`GraphCommitted` strictly lowers `G`. Finite `GraphDesc` means each commit adds
finitely many nodes; it may add arbitrarily many, so secondary finite node
phase rank `W` can rise by an arbitrary finite amount at a graph commit, while
lexicographic `(G,W)` still decreases. Between graph commits, legal node
transitions strictly decrease `W`. `RunStarted` is excluded.

Do not claim fuel bounds graph size, generator CPU, or encoded bytes. It bounds
only nested graph expansions. F* totality proves logical termination of a
pinned generator; practical memory exhaustion or external execution limits are
separate host liveness premises. No node-count/depth/byte cap is required for
DAG expressibility or P12.

## Countermodels and objections

1. **Raw result has right indices, wrong output type.** Let `i=unit`,
   `o _ = nat`, `x=()`, `graph_nodes=[]`, and `graph_output_wire=RootWire`.
   This is a `GraphDesc unit (fun _ -> nat) ()` because output family is
   phantom. It is not `graph_wf`; a raw `GeneratorRef` can return it.
2. **Bad wire typing.** A node label resolves to a work requiring `nat`, but
   its input wire is `RootWire` at root input `unit`; raw descriptor still
   inhabits `GraphDesc`. `graph_wf` must reject before commit.
3. **Bad registry.** A typed witness carries an executable work whose durable
   ref is absent from the pinned bundle, or a codec with matching identity
   fields but different implementation. Current `typed_graph_witness` has no
   membership premise, so existential witness can validate it unless P0 link
   is added.
4. **Bad topology.** Duplicate keys, forward `OutputWire`, dangling key, or
   self-edge are all representable in `graph_desc`; nominal type does not
   exclude them. `dag_wf` rejects them only if established for every generator
   result and decoded graph.
5. **Duplicated plan keys.** A list contains two allocations for one child
   occurrence. Summing list entries but loading into a map by overwrite can
   produce different accounting. Require uniqueness before sum/map conversion.
6. **Omitted child allocation.** A generated child graph contains a generator
   or external node but plan omits it. It becomes unreachable, underfunded, or
   stalled. Require exact plan domain and work-kind constraints.
7. **Overfunded generation call.** State allocates `(1, 0)` to occurrence `k`,
   but runner calls `generate_graph x (100, 100)`. Raw function type permits
   this; P4/P8 fail unless action obtains allocation only from state.
8. **Zero-fuel expansion.** Pending generator has `b=0`; it emits ordinary
   nodes or a zero-fuel nested generator. Then `sum child fuel < b` cannot hold
   for the latter, and `G` need not decrease for the former. Root and every
   pending generator must have `b>0`.
9. **Unbounded graph size.** Generator returns one million ordinary vertices
   under fuel `1`. This is still a finite graph and does not violate expansion
   accounting; P12 remains mathematical, but real memory/latency is not
   bounded. Adding a shape cap would change expressibility and is outside the
   stated contract.
10. **Codec roundtrip without graph validity.** A graph codec canonically
    encodes/decodes a malformed descriptor. Its current two laws still pass.
    P2 must combine parsing with exact registry resolution and `graph_wf`.

## Unresolved proof/interface questions

1. Will `GeneratorRef` return raw `GraphDesc` with universal `GeneratorMember`
   refinement, or a registry-bound `GeneratedGraph` proof wrapper? Recommend
   wrapper at the generation action boundary; decoded proof is reconstructed.
2. Where does the child allocation plan come from: generator result or pinned
   deterministic allocator? Specify one choice; either way store it once in
   `GraphCommitted` and derive ledgers only from that event.
3. Does `allocation_plan_wf` require an entry for every node (including zero
   allocations), or a sparse map with exact work-kind-dependent domain? Choose
   one canonical representation; do not leave list defaults implicit.
4. Prove `b > 0` for root generator allocations and every live pending
   generator. Does initial budget admission reject roots that cannot satisfy
   this, or represent a valid fallback graph without invoking a generator?
5. Add same-bundle `WorkMember`/`CodecMember` witnesses to `typed_graph_witness`
   and constant typing. Bind `GeneratorIdentity` to input codec, exact output
   family, and exact `GraphCodecIdentity` through registry manifest.
6. Establish codec decode soundness under registry: successful parse must
   reconstruct and prove `graph_wf`, not only re-encode canonical bytes.
7. Formalize graph substitution at the exact typed input/output boundary for
   `global_dag_wf`; local topological order alone is insufficient.
8. State practical host resource/failure assumptions separately from logical
   totality. No graph shape bound is needed, but OS exhaustion can violate
   runtime progress.

## Provenance

All statements above are audit deductions from source/spec, not proved results.
Primary anchors: `src/fstar/v2/src/WorkflowV2.Kernel.fst:126-158`,
`src/fstar/v2/src/WorkflowV2.Graph.fst:143-182,228-235,416-486,508-534`,
`src/fstar/v2/src/WorkflowV2.Identity.fst:100-135,153-232`,
`src/fstar/v2/src/WorkflowV2.Journal.fst:30-60,82-109`, and
`src/fstar/v2/implementation_spec.md:345-356,487-526,684-693,740-765,914-946,1013-1025`.
No source, build, or test changes were made.
