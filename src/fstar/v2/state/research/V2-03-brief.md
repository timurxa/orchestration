# V2-03 investigation brief

## Question

What is the smallest F* implementation that makes first-order dynamic graph
descriptors durable and recoverable, with provable canonical graph bytes,
typed node/constant resolution, and allocation-aware generation?

## Normative inputs

- [`implementation_spec.md`](../../implementation_spec.md), especially P0, P2,
  the graph codec clauses, allocation clauses, and graph expressibility target.
- Current kernel modules under `../../src/` and the project `verify` target.
- V2-01/02 simplification decisions in `V2-01-02-simplification.md`.

## Acceptance criteria

1. For every supported descriptor `g`, prove `decode (encode g) == Some g`.
2. For any bytes `b` accepted as `g`, prove `b == encode g`; decoder must
   reject malformed/noncanonical encodings rather than normalize them.
3. Decoding bytes must reconstruct first-order labels/wires, then resolve each
   `DurableWorkRef` and constant codec against the exact pinned manifest. The
   result must preserve existential input type and dependent output family;
   equal labels alone are insufficient. For every node, prove its input wire
   has the selected Work's exact input type for every legal prior-port
   environment. Do not execute a Work or check one sample environment to
   obtain that proof. Resolve `PairWire` recursively from its children and
   construct the dependent pair directly; it has no separate family codec.
4. Root and generated graph paths use the same codec and resolution contracts.
   A generated descriptor is indexed at the generator's exact input and
   workflow output family, is checked as a finite typed DAG, and is committed
   with the exact occurrence allocation plan from the journal model.
5. No node-count, graph-depth, or encoded-size bounds are added. Fuel and
   charge remain occurrence allocations, not graph-shape caps.
6. No new `assume`/`admit` is accepted as a substitute for the codec,
   resolution, or generation theorem. Any remaining boundary must be named in
   the spec and explained in the final report.
7. Full project F* verification passes after integration.

## Competing mechanisms to retain until evidence

- Direct structural graph serialization versus a generic `codec (GraphDesc)`
  assembled from codecs for graph components.
- Decode first-order bytes then resolve references versus a single typed
  registry-driven decoder.
- Prove codec laws by inverse-parser lemmas versus package a codec with
  individually proved constructor laws.
- Treat generation validity as a generator refinement contract versus return
  a descriptor paired with explicit `graph_wf` evidence.

No approach wins solely by having fewer lines: compare proof strength, number
of independent sources of truth, dependent-index preservation, and reuse for
root and generated graphs.

## Current evidence and state

`WorkflowV2.GraphCodec` now provides a concrete encoder/parser over the
unbounded `bytes = list nat` syntax. F* proves round-trip for every descriptor
and exact re-encoding for every accepted byte string. The integrated
input-shaped chain example proves graph size/topology facts and its ordered
local allocation plan against a concrete work registry. Full project F* check
passes.

This does not yet complete V2-03. `Identity.fst` lookup now carries exact
package membership and key-match evidence, but the schema bridge and
bundle-manifest binding remain open. `Graph.fst` has a concrete dependent
port telescope and typed wire constructors; the builder remains abstract, and
no executable `resolve_graph` reconstructs those witnesses from first-order
descriptor syntax. A scratch recursive resolver verifies for a closed Nat
schema, but does not supply general heterogeneous transport or universal
prior-edge compatibility. `PairWire` family lookup is no longer a
requirement. No general root/generated `resolve_graph : GraphDesc -> option
graph_wf` or `GeneratorAdmission` theorem is claimed.

The exact missing type bridge and construction alternatives are recorded in
[`V2-03-schema-bridge.md`](V2-03-schema-bridge.md). A schema-indexed pinned
manifest is a candidate route, not an established solution. Independent
audits found that first-order registry lemmas establish key equality but not
carrier-type equality. Port contexts and references are now concrete; the
remaining obstacle is reconstructing matching dependent types from descriptor
syntax. A further obligation is pointwise compatibility: a source output
type may depend on the value in the port environment, while a consumer Work
has one fixed input type. The selected schema representation must derive that
equality for every legal environment without executing work or adding new
`assume`/`admit` holes. If it cannot, the API/encoding bridge must be revised
before V2-03 completes. See the independent codec, resolution, and generation
audits linked from `registry.md`.

## Assignments

See `registry.md` for worker identities, artifacts, findings, and reviewer
status. Root owns integration and source changes. Subagent artifacts are
read-only proposals until checked against source and F*.
