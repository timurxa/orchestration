# V2-03 alternative: registered edge-proof handlers

**Status:** constructive design route; not implemented or F*-checked.

## Why raw syntax is insufficient

`Graph.fst:304-349` gives typed witnesses for root, constants, prior outputs,
and structural pairs/projections. `typed_node_sequence` then requires each
wire family to equal the selected Work's fixed input carrier
(`Graph.fst:606-623`). Yet `Kernel.fst:68-87` serializes only wire labels and
bytes. `GraphCodec.fst:362-390, 635-645` round-trips that raw syntax, not its
erased equality proofs. Current `wiring.wiring_typed` and
`typed_graph_witness` therefore cannot be recovered from graph bytes alone.

This is P2's explicit obligation: reconstruct universal input typing from
syntax and registered packages, without running Work
([implementation_spec.md, lines 470-526](../../implementation_spec.md)). P1
also asks completeness for every typed DAG (line 1166). These are stronger
than identity lookup or successful decoding.

## Executable route: Work-pinned input proof handler

Add per-node `input_evidence:bytes`. Each pinned Work package supplies a pure
F* handler for its fixed input type. Handler decodes evidence using its pinned
evidence codec, examines exact graph prefix and wire, and returns typed
`wiring` or rejects. It may use any F* lemma in its implementation; no
serialized F* proof term or general-purpose type-term language is needed.

```fstar
type input_resolver (registry:pinned_registry_bundle)
    (target:Type0) (evidence:Type0) = {
  evidence_codec:codec evidence;
  resolve_input:
    #root:Type0 -> #x:root -> #ports:port_context root x
    -> #nodes:list (graph_node root x)
    -> prefix:typed_node_sequence registry root x ports nodes
    -> syntax:wire root x
    -> evidence:evidence
    -> Tot (option (w:wiring registry root x ports (fun _ -> target){
         w.wiring_syntax == syntax}))
}
```

Package this resolver with each `CodeRef`, `OpRef`, or `GeneratorRef` at
that Work's fixed request/input type. Work identity plus pinned registry
manifest must resolve same resolver code after restart.

The schematic result type is the key contract: `Some w` already proves that
the exact wire has the Work's fixed input type for every legal port
environment. Resolver first reconstructs the typed prefix, then invokes the
resolved Work package's handler. It does not execute local or external Work.
Root is fixed at `x`; constants decode through pinned codecs (indexed codecs
at exact `x`); output types use prior Work signatures plus the exact symbolic
input wiring; Pair/Fst/Snd remain structural. A dependent-family lemma in the
handler can establish graph-local facts such as `Prime 0 == Prime 0`.

Pin handler code and evidence codec through the exact Work package/registry
manifest. Store only evidence bytes on each graph node; do not duplicate
source or target schema as a second truth. Include evidence bytes in graph
canonical encoding. Existing graph codec roundtrip/canonicality proofs must
cover them.

Resolver theorem spine stays close to spec. Add evidence bytes to
`GraphNode`; resolver obtains typed input from the selected Work handler,
then extends current `typed_node_sequence`:

```fstar
val resolve_graph : bundle -> x:i -> g:CertifiedGraphDesc i o x
  -> Tot (option (resolved:CertifiedGraphDesc i o x{
       resolved == g /\ graph_wf bundle x resolved}))

val resolve_graph_complete : bundle -> x:i -> g:CertifiedGraphDesc i o x
  -> graph_wf bundle x g -> Lemma
       (match resolve_graph bundle x g with
        | None -> False
        | Some resolved -> resolved == g)
```

For this theorem, `graph_wf`'s typed clause must carry/recover successful
handler results for every stored evidence blob, alongside existing finite,
unique, topological, and output-wiring conditions. Builder completeness then
inducts over any such certified node sequence and preserves its exact evidence.

## Guarantees and exact boundary

- **Sound executable fragment:** F* result type gives soundness: every
  returned `Some w` supplies required universal edge equality. Registry and
  codec identity resolution plus evidence validation are pre-execution. A
  failed handler rejects graph before any node runs.
- **Certified completeness:** require builder `add_node` to receive evidence
  whose pinned handler returns the supplied typed wiring. Define
  `graph_wf` over this certified descriptor. Then `resolve_graph` can be
  complete for every `graph_wf` graph; graph topology remains arbitrary finite
  DAG, while every edge has replayable evidence.
- **Raw typed-DAG completeness:** not established. Current `graph_wf` means
  some `typed_graph_witness` exists; its erased proof may have no handler
  evidence. No generic executable resolver can recover arbitrary equality
  proofs from raw syntax. Keeping current P1/P2 wording therefore requires a
  stronger completeness theorem: every raw typed edge must have evidence
  accepted by its Work handler. Proving that for arbitrary F* equality
  proofs is equivalent to reifying/checking general F* proofs or restricting
  type equality to a decidable schema language.

Smallest honest spec change: make edge evidence mandatory in graph syntax;
define `graph_wf` as the existing finite/unique/DAG conditions plus successful
typed resolution of every evidence-bearing edge. Restate P1 completeness over
these certified DAGs. If P1 must include every raw semantically well-typed DAG,
retain certificate completeness as an explicit open research problem; do not
claim it from this route.

## Comparison to syntax certificates

Prior note `V2-03-local-wire-equality-certificates-2026-10-13.md` used a
first-order equality AST with a small checker. That checker is simpler to
audit and portable across Work packages, but its completeness is limited to
its equality rules and pinned lemmas. A Work-pinned handler is more
expressive: ordinary total F* code can implement specialized symbolic
reasoning and invoke arbitrary named theorems. It is harder to audit as a
shared kernel component and completeness still requires per-handler
evidence. Both routes require evidence-bound canonical graph bytes and both
must narrow `graph_wf` or prove evidence existence for every raw typed graph.
