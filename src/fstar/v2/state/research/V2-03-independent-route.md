# V2-03 independent route audit

Date: 2026-10-12

**Historical proposal:** this route predates the structural `PairWire`
decision. Its PairWire family-codec entries and proof obligations are
superseded by [`V2-03-pairwire-simplification.md`](V2-03-pairwire-simplification.md).
Its analysis of work/schema compatibility and universal prior-edge typing
remains useful; do not implement its PairFamily lookup.

## Question and verdict

Can current V2-03 meet `state/work_dag.md` V2-03 acceptance and
`implementation_spec.md` P0/P2, including typed root/generated resolution and
generator admission? **No.** Executable syntax codec is verified; a shaped
chain generator and its ordered local allocation plan are verified. No
executable `resolve_graph` exists, so neither root nor generated descriptors
can be converted into exact typed witnesses. The example also does not build
`graph_wf` or `generator_admission` evidence. No current route closes all
criteria.

This audit proposes one materially different route from the schema-token
manifest sketch: a closed, generated compatibility algebra that stores typed
edge evidence per registered producer/consumer pair. It avoids a general
`schema_id -> Type0` carrier map, at cost of a closed work catalog and a
potentially quadratic compatibility table. It is a design candidate, not a
verified implementation.

## Acceptance-by-acceptance evidence

### Syntax codec: met, subject to one source-comment correction

`WorkflowV2.GraphCodec.fst:362-485` defines prefix-tagged wires, length-framed
identity/build/string fields and graph node counts, rejects unknown tags,
requires complete input at line 475, and re-encodes parsed descriptors at
480-485. Thus accepted bytes equal the encoder output by an explicit guard.
The inverse-parser proof is at `:71-105, 509-650`; it establishes
`decode_graph_syntax (encode_graph_syntax g) == Some g` and accepted-byte
canonicality. `graph_decode_canonical` at `:648-651` is guard-derived after
unfolding `decode_graph_syntax`, not a standalone injectivity theorem for
`parse_graph_syntax`.

`dec_chars` at `:45-61` deliberately rejects code point `0xd7ff`; current
F* library confirms that this is its stated `FStar.Char.char_code` invariant
(`FStar.Char.fsti:35-38,57`), so the earlier Unicode-boundary concern does
not apply to this toolchain. Comment at `GraphCodec.fst:51-52` says the
invariant excludes `0xd7ff` “as well as the surrogate range”; more precise:
the valid range is `< 0xd7ff`, excluding `0xd7ff` itself, `0xd800..0xdfff`,
and values above `0x10ffff`. Keep encoder and decoder aligned if F* char
semantics change.

### Exact typed resolver: not met

V2-03 acceptance in `work_dag.md:52` separately requires executable
`resolve_graph` that rejects or constructs `graph_wf` from exact manifest
entries for work, constants, and PairWire family codecs, on both root and
generated paths. `implementation_spec.md:487-519, 634-655` specifies the
same requirement. Current source has no `resolve_graph` declaration or
implementation in `GraphCodec.fst`, `Graph.fst`, or `Identity.fst`.

`Identity.fst:84-151, 153-222` has existential package lookup, uniqueness
proof fields, and key-exactness lemmas. These establish which key matched,
not equality of hidden F* type indices between two separately packaged
entries. `Identity.fst:224-232` bundles arbitrary registry identity and
contents without a manifest-content relation. `Graph.fst:485-497` carries a
bundle in `typed_graph_witness`, but constructor has no membership evidence
that its node works or codecs are the exact resolved packages. The builder
API in `Graph.fst:348-366` also accepts raw work, not spec-required
`WorkMember` (`implementation_spec.md:389-406`).

Concrete counterexample: two registered `packed_work` values can carry
different input types but be assigned equal-looking first-order keys if
registry construction fails to enforce uniqueness across the complete
reference. Even with uniqueness, a successful lookup returns an existential
package but no proof connecting its hidden input type to the root type or a
previous node's output type. A string/key equality test cannot construct that
transport. Likewise, a canonical `ConstantWire` can name a codec ID that is
unknown, has the wrong plain/indexed constructor, or decodes only at a
different root index; syntax decoding alone must not accept it as typed.

### Root and generated paths: not met

Codec functions are indexed at exact `x` and `o` (`Kernel.fst:126-136`), but
there is no root entrypoint type/resolver tying `RunStarted`'s root graph codec
identity to an exact typed package; see `implementation_spec.md:106-115` and
`V2-03-resolution-audit.md` “Graph codec and root entry point.” Generator
records embed a graph codec (`Kernel.fst:151-159`), but no bundle resolver
binds that embedded implementation to the manifest. A single proposed
`resolve_graph bundle x g` for both call sites would be the simplest closure;
neither call site currently invokes one.

### Shape and plan: partly met; admission not met

`GenerationExample.fst:104-173` emits `count` local nodes, keys increasing
from zero, each after the first referencing `key - 1`, and output points to
last node or root for the empty case. `:207-234` proves key range exclusion
and uniqueness. `:116-123, 194-205` constructs matching allocation keys in
node order. `:236-273` proves local-node `(0,0)` validity, zero nested fuel,
zero charge pool, and `allocation_plan_wf` under `chain_registry`. This meets
the ordered-plan and resource-accounting portion for the example.

It does **not** establish the example generator's admission contract:
`chain_generator` at `:165-174` returns the graph/plan, while no theorem
constructs `generator_admission chain_registry chain_generator`. That record
requires both `graph_wf` and `allocation_plan_wf` for every `x` and parent
(`Graph.fst:600-609`). Existing example proofs cover only the latter. `Graph.fst`
typed witness/port constructors remain partly abstract and contain no exact
registry membership (`:143-158, 485-497`); `finish_graph_sound` and
`graph_complete` are admitted at `:513-534`. Thus shape is demonstrated, but
“admission before commit” is open.

Plan/source mismatch: spec requires one allocation entry per node **in the
same order** (`implementation_spec.md:614-627`); source `allocation_plan_wf`
now checks exact list equality plus node-validity, uniqueness, and budget
laws (`Graph.fst:528-594`). The example's `chain_plan_keys_equal` plus plan
validity is appropriate for this local-only case, but does not replace graph
typing proof.

## Independent route: generated typed compatibility algebra

The schema-token proposal in `V2-03-schema-bridge.md` gives each first-order
schema token one manifest-owned carrier type. Alternative: keep a finite,
closed schema/work catalog generated from admitted F* declarations, but
encode compatibility as typed constructors for each legal endpoint class:

```fstar
noeq type edge_compat : source:packed_work -> target:packed_work -> Type =
  | RootToInput: root_entry -> target_work -> (root_input == target_input)
      -> edge_compat (PackedWork root_entry) (PackedWork target_work)
  | OutputToInput: source_work -> target_work ->
      (forall x. source_output x == target_input_for x) ->
      edge_compat (PackedWork source_work) (PackedWork target_work)
```

This is schematic: use an actual dependent equality witness and erase the
proof at runtime. Generate a finite lookup table indexed by the two durable
work identities (plus root-entry identity). Each table entry is constructed
while both work signatures are statically available, so type equality comes
from a typed constructor/proof, not an identity-to-carrier map. Parser remains
first-order. Resolver walks nodes topologically, obtains exact producer and
consumer packages once, selects `edge_compat`, then constructs port typing
using its equality witness. Repeated/fan-out edges reuse the producer package.
Root edges use a root-to-input witness. Constants resolve through an exact
codec package, and PairWire resolves a family-codec package whose own typed
family drives construction of both child wires. The same traversal runs on
root and generated descriptors.

Required constructor invariants: every table key is unique; every emitted
entry's endpoint references are the exact packages returned by the same
closed catalog; omitted pairs reject; and all admitted typed edges are
represented. For dependent outputs, compatibility witness must quantify over
the exact source input and provide equality at that value. Pair-family
compatibility must use environment and left value exactly, as required by
`implementation_spec.md:643-648`.

This is materially different in proof organization: the bridge is a
closed-world relation of typed links, rather than a global token interpretation
that recovers a carrier from each token. It may be easier if workflow node
types are fixed at build time and catalog generation is acceptable. It is
strictly worse for open plugin registries: a new node type requires regenerating
the catalog and every relevant compatibility pair; worst-case table is
quadratic in work entries. It does not eliminate proof burden: table
completeness is effectively a finite proof of schema compatibility, and
arbitrary dependent type equality cannot be decided from names. If dynamic
open registration or an arbitrary `Type0` family is required, this route
fails the target and the schema-token manifest remains more scalable.

## Proof sketch and obligations for this route

1. Define closed generated catalog `Catalog`, whose constructors carry exact
   `work i o`, codecs, generator and graph codec. Derive first-order refs from
   constructors; prove `resolve_ref` returns that constructor exactly and
   rejects absent refs. Make duplicate refs impossible by catalog generation,
   or prove key uniqueness by finite induction.
2. Define typed edge relation over catalog constructors. Build each legal
   compatibility witness from definitional equality or an explicitly supplied
   equality theorem. Soundness: every witness endpoint types agree. Coverage:
   every edge accepted by the typed builder has a generated witness.
3. For constants, resolve exact plain/indexed codec package. Its own result
   type constructs the constant typing witness; indexed decode is applied at
   exact root `x`. For PairWire, exact family package constructs the dependent
   pair result; recurse under that package's environment/left-indexed family.
4. Resolver state stores a concrete snoc list of typed port packages. For each
   node, use node key lookup into prior packages, edge witness to transport
   endpoint type, then append exact output family `o input`. Reject absent or
   forward keys. At finish, require output wire type `o x`. Return
   `(g, graph_wf bundle x g)` only after projecting exact descriptor syntax.
5. Root and generated entrypoints both parse with `decode_graph_syntax`, then
   call this resolver. Root entrypoint and generator catalog constructors
   pin their graph codec to the catalog. Prove generation result uses the
   resolved generator and exact supplied allocation; pair its graph proof
   with ordered `allocation_plan_wf` to construct `generator_admission`.
6. Prove registry identity commits to catalog content, or explicitly leave
   host binary/catalog reload as a P0/P13 premise named by the spec. This route
   cannot prove a build hash denotes actual extracted code without that host
   refinement premise.

## Limitations and next experiment

No current route meets full acceptance. The typed compatibility algebra is
plausible only for a generated, closed catalog and still requires a prototype;
it cannot represent unrestricted open-ended `Type0` registration without
reintroducing a schema universe or explicit type equality metadata. The
existing schema-token sketch better supports broad registries but has its own
unimplemented manifest constructor and PairWire family proof.

Next experiment: implement a scratch-only tiny closed catalog with two
different work types, one root input, a prior-output edge, one indexed
constant, and one PairWire family; parse a hand-built descriptor and have
the compatibility-table resolver return a typed witness. Check F* with no
new `assume`/`admit`. This discriminates whether the route avoids a global
token map in practice, or merely relocates the same type-coherence proof.

## Source anchors

- `state/work_dag.md:52-54` — V2-03 and simplification acceptance.
- `implementation_spec.md:448-519, 614-655, 1148-1155` — schema evidence,
  resolver, plan, exact codec/generator binding, P0/P2/P4.
- `WorkflowV2.GraphCodec.fst:45-69, 362-485, 509-651` — string parser,
  structural syntax codec and laws.
- `WorkflowV2.Identity.fst:84-151, 153-232` — existential lookup and bundle.
- `WorkflowV2.Graph.fst:143-158, 485-516, 528-609` — abstract ports,
  typed witness, plan predicate and generator admission.
- `WorkflowV2.GenerationExample.fst:104-173, 207-286` — shaped chain,
  uniqueness, allocation proof, and shape theorem.
- `state/research/V2-03-schema-bridge.md` — current token-manifest route and
  restricted resolver prototype results.
