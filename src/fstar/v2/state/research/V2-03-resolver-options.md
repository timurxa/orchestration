# V2-03 heterogeneous resolver options

**Historical proposal (2026-10-12):** the exact `PairFamilyRef` and per-wire
family-codec lookup proposed below were superseded by the structural
`PairWire` decision in [`V2-03-pairwire-simplification.md`](V2-03-pairwire-simplification.md).
Keep the schema-carrier and universal prior-edge analyses as provenance; do
not treat pair-family package lookup as a current requirement.

## Historical recommendation

Use a **hybrid, proof-carrying registry**. Keep first-order schema/family tokens for durable identity and fast dispatch, but make each resolved package carry the typed endpoint evidence used by the resolver. Build the manifest as a closed finite GADT/table whose constructors package actual `codec`, `indexed_codec`, `work`, and `pair_family_ref` values plus coherence proofs. Thread each returned package once through recursive node and wire resolution. Do not treat `token -> Type0` alone as the proof, and do not compare `noeq` package values.

Small interface delta:

1. Replace `global_registry_unique` / `global_codec_unique` as caller-supplied record fields with closed registry constructors that establish key uniqueness and schema coherence from finite entries.
2. Add schema metadata to the typed registry entries, not graph nodes. For each plain carrier, carry `SchemaMember`; for work input and every indexed output, carry schema functions indexed by the actual input. Carry a family schema for the actual `dtuple2 environment left` input of each pair-family codec.
3. Make `resolve_global_work`, `resolve_global_codec`, and pair-family lookup return the selected existential package and its membership/coherence evidence together. `resolve_graph` must consume that exact result, construct wire typing in topological order, and return the existing `typed_graph_witness` with membership facts for every work, constant codec, and pair-family codec.
4. Make the port telescope concrete and store prior node outputs at their actual dependent types. `OutputWire` resolution returns the prior typed port reference, not a runtime key/value pair erased to `Type0`.

Tokens then prove type transport through manifest coherence. Exact executable identity comes from the returned package itself. This separates two facts that current declarations conflate: *which implementation was selected* and *why its hidden type matches this edge*.

## Options

| Route | What it buys | Main cost / failure mode |
| --- | --- | --- |
| **A. Schema tokens in pinned manifest** | Equal tokens reduce to one carrier; supports constants and cross-node edge checks with a reusable theorem. Works for dependent outputs when output token is a function of the exact input. | A bare `schema_id -> Type0` function-backed manifest is not a constructive finite registry. Need a closed representation and proof that duplicate IDs share one carrier. For arbitrary dependent families, especially `PairWire`'s right family over `(environment, left value)`, tokens need registered family code plus pointwise interpretation. A token name alone does not prove executable codec/work selection or manifest identity. |
| **B. Carry resolved existential schema packages directly** | Avoids global runtime `Type0` equality and makes the exact decoder/codec available. Resolver can return `exists a. codec a` or `exists i,o. work i o` and use that package as the witness. | Separate packages at two ends of an edge still have hidden types `a` and `b`; first-order identity equality does not yield `a == b`. `noeq` prevents using package equality as a shortcut. Must add a shared schema witness/equality to registry entries, which recreates a coherence relation. It also needs package membership in `typed_graph_witness`. |
| **C. Infer token from codec identity / require one codec per type** | Could avoid a new token field if codec identities were canonical carrier IDs. | Conflates implementation identity with carrier identity. Multiple codec implementations/versions for one type become impossible or ambiguous; indexed codecs have input and pointwise output carriers, while plain codecs have one carrier. Pair-family identity additionally names executable dependent code, not merely a carrier. Not viable without imposing a restrictive new global codec policy. |

So A is necessary as a durable *schema identity* mechanism, but insufficient as the proof interface. B is necessary as the source of exact executable witnesses, but insufficient for edge transport. Hybrid is the smallest route that handles both without equality tests on `Type0` or `noeq` values.

## Actual declaration constraints

- `Kernel.fst:55-61` says durable work references carry work identity plus input/output codec identities; `Kernel.fst:68-74` gives first-order `RootWire`, `OutputWire`, `ConstantWire`, `PairWire`, `FstWire`, and `SndWire`. No schema token is present in syntax.
- Codec and work types already expose the required dependent shape: `Kernel.fst:90-108` defines plain and indexed codecs with round-trip/canonical laws; `Kernel.fst:110-117` defines `pair_family_ref` as an indexed codec over `dtuple2 environment left`; `Kernel.fst:119-145` defines work refs and graph codecs; `Kernel.fst:161-180` keeps work output indexed by input and generator output as a graph.
- `Identity.fst:84-90` packages `work i o` existentially. `Identity.fst:100-151` resolves by derived durable key and proves key exactness/uniqueness conditional on a registry record. `Identity.fst:154-222` does the same for plain/indexed codecs in one existential sum. `Identity.fst:224-232` pins identity beside those registries but does not bind identity to contents.
- `Graph.fst:156-170` assumes the port context, environment, references, lookup key, and evaluator. This is a separate trusted gap: a resolver cannot construct prior-output evidence from these declarations.
- `Graph.fst:176-243` has syntax-indexed wire witnesses. `PairWireTyping` (201-220) needs a `pair_family_ref` at the exact environment and left value; Fst/Snd (221-243) preserve its dependent pair family. Parsed `PairWire` carries only codec identity (`Kernel.fst:72`), so decode must recover that exact family package and prove its schema at each relevant value before it can type the right child.
- Builders accept unregistered code today: `Graph.fst:289-320` take raw codecs; `Graph.fst:322-341` takes a raw pair-family ref; `Graph.fst:368-380` takes raw `work`; typed node insertion (around 430-456) stores only `durable_ref_of_work node_work`. `typed_graph_witness` (Graph.fst:485-497) carries a registry parameter but no membership proof. The missing exact-package link is real for both generated and decoded graphs.
- `Graph.fst:499-516` defines `dag_wf` by existence of that witness, so a constructive resolver must return the witness, not just bool validation. `GraphCodec.fst:641-651` proves raw syntax round-trip/canonicality only; it does not recover typed work, codec, family, or port evidence.
- `implementation_spec.md:448-485` sketches schema tokens and requires constructor-proved coherence; `:487-519` requires topological, exact-package resolution and output type `o x`. This report narrows the representation choice: make the manifest closed and proof-carrying, not an abstract type-denotation function. `:566-580` states graph well-formedness and dependent wire rules.

## Prototype evidence and strongest objection

Scratch-only `/tmp/V2ResolveMany.fst` verifies with:

```text
opam exec -- fstar.exe --cache_off --warn_error @285 /tmp/V2ResolveMany.fst
Verified module: V2ResolveMany
All verification conditions discharged successfully
```

It establishes recursive node resolution only for one homogeneous `Nat` schema, with a dependent-shaped output family `nat_family : nat -> Type0`, a finite work registry, root/constant/prior-output wires, and final output resolution. It does not establish heterogeneous transport or `PairWire`.

Attempt to strengthen that scratch witness with `n.work_id == w.wid` failed:

```text
Subtyping check failed
Expected type n.work_id == w.wid got type Prims.unit
The SMT solver could not prove the query.
```

This is not proof that such a theorem is impossible. It is evidence that carrying a `noeq work` selected by a lookup does not automatically produce projection/equality evidence; registry lookup needs a proof-carrying membership/result interface. It reinforces the audit's warning at `V2-03-resolution-audit.md:142-147` that equality of noeq package values is an unsafe interface target.

**Strongest objection to the recommendation:** the hybrid may merely relocate the hard proof into a “closed manifest” constructor. A closed finite registry is practical only when admitted schemas and dependent family codecs are statically enumerable/generated. If users require runtime-open arbitrary F* types or arbitrary closures as `PairWire` families, neither tokens nor existential packages can recover type equality from strings. Must either restrict those registrations to generated schema/family codes or make each registry entry carry explicit, proof-checked type equalities. Do not claim general runtime-open typed resolution.

## Decision test for implementation

Before accepting P2, require a small compiled witness with two heterogeneous nodes whose edge crosses distinct work packages, one decoded constant, and `PairWire` followed by `SndWire` where right type depends on the left value. It must produce `typed_graph_witness` and project exactly to the original `GraphDesc`; malformed/missing family ID and non-prior output must return `None`. The finite registry constructor must be the only way to obtain membership evidence. Current homogeneous scratch prototype does not meet this test.
