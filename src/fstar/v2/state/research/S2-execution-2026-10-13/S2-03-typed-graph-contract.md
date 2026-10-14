# S2-03 — Typed graph language, builder, and resolver

**Status:** specification contract complete. No F* module, source-level proof,
test, or verifier run was part of this node. The normative definitions are in
[implementation_spec.md, §2.2](../../../implementation_spec.md#22-dynamic-graph-description-and-construction-api),
its typed-schema subsection, and P1/P2 in the proof table.

## Selected boundary

One registry-pinned schema resolver serves both the public builder and graph
decode/recovery. It accepts exactly the manifest-declared `SchemaSupported`
language. `GraphDesc` is the first-order syntax; its node list is already in
topological order, keys need not encode that order, and the syntax codec
preserves exact list order. A separate `FiniteTypedDAG` representation or a
serialized typing proof is unnecessary. Different topological enumerations
can be typed-isomorphic without being byte-identical.

The schema AST contains primitive atoms, unit/bool/numeric literals, products,
sums, lists, options, locally nameless dependent sigma types, registered
families, refinements, values, constants, prior ports, constructors, and
registered total index functions. Every opaque family/function has one
manifest-pinned denotation and proof laws. Substitution is capture-avoiding.
The checker is syntax-directed over finite wire, type-equality, and predicate
derivations; unknown equality rejects. Equality is sound for every legal
environment and complete only for derivations in this declared calculus.
Arbitrary erased F* `Type0` equality, opaque closure equality, unchecked SMT,
and edge-carried proof payloads are outside the boundary.

## Legal environments and external outputs

`LegalEnv` is inductive over the topological prefix. It fixes the exact root
value and canonical constant decodings. For each prior node it evaluates the
input wire from already assigned ports, then assigns any inhabitant of that
node's exact declared output family at that input. It executes no Work. This
set includes every external validator-accepted result because those results
inhabit the declared family.

S2-01 had left room for a pinned validator postcondition to narrow the set.
S2-03 resolves this in favor of the project's stricter static rule: graph
typing uses only declared types and graph syntax. A validator postcondition
cannot make an otherwise mismatched edge valid. If the possible result range
must be restricted for composition, that restriction and any evidence belong
in the declared output family. This conservative policy may reject an
operation whose validator happens to accept only a compatible subset of a
broader result type; it preserves the requirement that the graph relation is
established by looking at types, without asking the external operation to
prove a graph-specific edge.

The `Sigma n. vector n` to `vector 3` counterexample is therefore rejected
unless the declared type/schema and exact static root/constant/refinement
facts establish the equality for every legal environment. One observed reply
with `n=3` never helps. A generated graph is checked at the generator's exact
input, while its internal ports remain universally quantified; P4 owns the
separate all-input/allocation generator admission proof.

## Builder and resolver contracts

`PrefixSupported` is a separate inductive predicate. The empty prefix has
the exact root schema; a node extension requires a fresh key, prior-only
references, exact manifest Work membership, an inferred wire type equal to
the Work's fixed input type, and the exact dependent output-family extension.
`LegalEnv` and schema derivations quantify over every typed value in that
prefix. `SchemaSupported` adds structural DAG checks and a final output-wire
derivation at `o x`.

The public laws are exact: `start_graph` produces the root-only prefix;
`add_node` returns `None` iff its proposed extension lacks `PrefixSupported`
and, on success, adds only the supplied node/wiring and one output port;
`finish_graph` returns `None` iff the exact descriptor lacks
`SchemaSupported` and, on success, adds only the supplied output wire. The
builder carries a private prefix witness, so callers cannot smuggle in an
edge proof or bypass the resolver.

P1 states builder/resolver soundness and completeness exactly for
`SchemaSupported`, including typed graph isomorphism that preserves vertex
multiplicity, exact Work/schema identities, typed wires and constants, edges,
root index, and output family. P2 states syntax round-trip and accepted-byte
canonicality, then exact resolver reconstruction of signatures, ports,
constants, edges, indices, and derived witness. Root and generated graphs
share this decode-and-resolve path. S2-03 specifies these judgments and proof
targets; a later implementation DAG must construct and verify the F* proof
terms. S2-04 owns the actual generator admission, plan, and substitution
proofs.

## Alternatives retained or rejected

- **Typed-constructor graph alone:** useful as an authoring frontend, but
  cannot reconstruct typed values from durable syntax after restart.
- **Proof reflection / Meta-F* at runtime:** useful for producing static
  schema packages, but unavailable as the extracted runtime resolver.
- **Per-edge certificates or operation-specific graph proofs:** rejected as
  duplicate, context-specific serialized truth; the resolver derives edge
  equality from exact signatures and schema context.
- **Arbitrary resolver callback:** rejected because it has no finite,
  manifest-bound soundness/completeness boundary.
- **Full declared output carrier vs validator subset:** selected the former
  for graph typing. The latter can express more graphs but would make edge
  validity depend on operation behavior beyond its declared result type.

Independent re-review found the formal environment, assumptions, prefix
invariant, builder characterization, and graph-isomorphism boundary
consistent. It flagged the validator-postcondition choice above; the choice is
now explicit and aligned with the stricter graph-typing requirement. No F*
source changed and no verifier or tests ran.
