# S2-01 — Dependent graph representation decision

Date: 2026-10-13. This is the integrated decision for the S2-01 node. It
selects an abstract graph-resolution boundary; it does not implement a
resolver or claim any new F* theorem is proved.

## Decision

Use one registry-pinned, proof-producing `GraphResolver` backed by canonical,
first-order type and value schemas. The public builder and graph decoder call
the same resolver against the same pinned manifest. It reconstructs transient
typed wiring from descriptor syntax and manifest schemas; proof terms are
never serialized. Resolver completeness is exactly the manifest-declared
`SchemaSupported` graph language. It is not completeness for every arbitrary
F* `Type0` family.

The selected design keeps graph topology unrestricted: any finite DAG shape,
node count, fan-out, join, and occurrence order may be represented. The type
language is explicit and extensible through pinned schema-family entries and
verified schema rules. A family absent from that language is rejected by both
builder and recovery. No system theorem may call this arbitrary-`Type0`
completeness.

The API boundary is registry-wide. Typed-constructor AST is a convenient
builder frontend, not a recovery mechanism. Per-Work resolver methods may be
used internally as registered schema rules, but do not define a second
acceptance path. Proof reflection may generate/check static schema packages
while authoring or verifying F* code; extracted execution and recovery use the
total schema checker, not Meta-F*.

## Type and value schema language

The pinned manifest adds one canonical schema package per relevant Work,
codec, and dependent family. Each package relates its schema denotation to
the exact F* carrier/family. It is identity-bound by P0; it is not a second
per-node signature or a free-standing type-name string.

The core schema syntax is first-order and typed:

```text
Ty ::= Atom(id) | Unit | Bool | Nat | Int
     | Product(Ty,Ty) | Sum(Ty,Ty) | List(Ty) | Option(Ty)
     | Sigma(Ty, Binder, Ty)
     | Family(id, IndexArgs)
     | Refine(Ty, Pred)

Value ::= Root | Port(NodeKey) | Constant(CodecId, CanonicalBytes)
        | UnitVal | BoolLit | NatLit | IntLit
        | Pair(Value,Value) | Fst(Value) | Snd(Value)
        | RegisteredConstructor(id, Args)

Pred ::= True | False | Equal(Value,Value) | And(Pred,Pred)

Index ::= Literal | RootProjection | PortProjection | ConstantProjection
        | PairIndex(Index,Index) | NatAdd(Index,Index)
        | RegisteredTotalIndexFn(id, Args)
```

`Atom` is opaque: only the same pinned schema identity or a pinned, proved
alias law establishes equality. `Family` names a registered indexed family
whose schema denotation is proved to match its exact F* family. Refinement
predicates and index functions must belong to the manifest's executable
schema theory and carry soundness proofs. Arbitrary F* functions, quantified
propositions, closures, and extensional function equality are not reified by
this syntax.

Every schema used to inspect a concrete graph-boundary input or constant must
also provide a total, pinned `quote_value : a -> ValueExpr` with a theorem
that its expression denotes that exact value. Structural schemas quote their
constructors. An opaque schema may quote only an atom plus canonical codec
bytes; the resolver cannot inspect that atom's contents. If a carrier has no
such quotation, it may still be used when no value inspection is needed, but
graphs requiring value-specific schema reduction are outside
`SchemaSupported`.

The checker is total and proof-producing. It normalizes only by terminating,
manifest-pinned rules and returns equality evidence only when it constructs a
derivation. The initial equality core is canonical-normal-form equality,
structural congruence, and explicitly registered proved equations. A later
schema extension may add a decision procedure only with F* proofs of
termination, soundness, and completeness for its named fragment. `Unknown`
means rejection; it never means “assume equal.” No arbitrary SMT success is a
runtime proof rule.

Exact constructors, binder treatment, and the minimal arithmetic/refinement
theory are S2-03 work. That node must give the concrete F* encoding and prove
the schema-denotation, normalization, and checker theorems before the packet
is implementation-ready.

## Graph typing and exact completeness boundary

For descriptor `g`, pinned manifest `m`, and exact graph boundary input `x`,
`SchemaSupported(m,x,g)` holds exactly when there are finite derivation trees
in the manifest-declared schema judgments and all of the following hold.
This is independent of resolver execution:

1. The descriptor is a finite acyclic graph with unique keys, topological
   wire references, exact pinned Work/codec entries, and canonical constants.
2. A derivation of `m;Γ ⊢ wire ⇓ (value_expr,type_expr)` gives a schema value
   and type to each wire, recursively through root, constant, prior-output,
   pair, and projection forms.
3. Every node input schema equals its Work's fixed input schema by a finite
   derivation of `m;Γ ⊢ type_expr ≡ type_expr`, valid for **every legal
   assignment** to prior output ports.
   Prior outputs remain symbolic variables constrained only by their declared
   schemas and registered refinements; the checker does not sample them.
   External-port values range over the full declared output family. Validator
   postconditions cannot narrow this set for graph typing; any desired subset
   restriction belongs in the declared output family itself. The original
   S2-01 alternative allowing validator-postcondition narrowing is superseded
   by the dated S2-03 decision below.
4. The graph output wire has exactly the declared boundary family at `x`, for
   every legal assignment to graph-internal ports.

The equality derivation rules are fixed structural equality/congruence,
literal normalization, assumption use and substitution for the declared
equality-refinement fragment, and finite manifest-pinned family equations
with denotation proofs. An opaque callback cannot add a rule. S2-03 specifies
the concrete AST, binders, inductive rules, and exact admitted extension
language. Boundary-input and constant quotation functions are also pinned
and proved denotation-preserving; no implicit F* type reflection is assumed.

The soundness target is:

```text
resolve_graph(m,x,g) = Some typed
  ==> StructuralDAG(g)
   /\ forall k rho. LegalEnv(m,x,g,k,rho)
        ==> eval_wire(g,k,rho) : WorkInput(m,g,k)
   /\ forall rho. LegalEnv(m,x,g,root,rho)
        ==> eval_wire(g,output,rho) : OutputFamily(m,x)
   /\ typed.syntax = g
```

Resolver completeness is proved over this independently defined derivability
relation:

```text
SchemaSupported(m,x,g)
  <==> resolve_graph(m,x,g) returns Some typed
  <==> public_builder_can_construct(m,x,g) up to typed graph isomorphism
```

The second equivalence includes soundness: a builder cannot bypass the
resolver. P2 proves canonical decode preserves syntax and the same resolver
reconstructs the same typed graph. Thus builder acceptance and recovery
acceptance coincide. `SchemaSupported` is specified by manifest schema forms
and proved checker rules, not defined as “whatever this implementation
happens to accept.” The exact schema grammar and extension package laws are
reviewed at S2-03.

This is a deliberate expressibility boundary, not a weakened edge theorem.
For accepted graphs the equality is universal. No local edge proof is
serialized, and no user callback is trusted without a pinned soundness law.
Every supported finite topology remains constructible. An F* type family
without a schema is outside the declared language, even if an author can
prove a particular equality in a one-off context.

## Root inputs, generated graphs, and runtime values

There are two distinct typing situations:

- For any graph, its root input `x` is the graph's exact typed boundary
  parameter. The schema resolver may instantiate the graph's root schema at
  `x`. For a root graph, `x` is the committed `RunStarted` input. For a
  generated graph, `x` is the generator's reconstructed input; it may itself
  have come from a committed external outcome.
- Outputs of nodes *inside that graph* are always symbolic, universally
  quantified ports during edge checking. An observed local result or
  external reply can never repair an invalid internal edge.

The generated-graph case is safe because `GenerateWork` is a pinned total
function of its exact typed input and allocation. P4 requires its admission
contract to prove, for every legal input and allocation, that the returned
descriptor and plan satisfy `SchemaSupported` at that input. At runtime,
`GraphCommitted` provenance ties bytes to the result for the exact input;
recovery checks the canonical bytes with the same resolver and does not rerun
the generator. A generator may choose graph topology based on its input, but
the admission theorem must cover every possible input, including every value
an external validator may accept.

This preserves the strict rejection example: a static edge from an external
producer with unconstrained `Sigma n. vector n` to `vector 3` rejects. One
reply with `n = 3` is insufficient. An explicit pure generator may accept the
whole sigma value and produce a child graph appropriate for that value, but
its universal admission proof must establish a valid child graph for every
possible sigma input. This is graph generation, not a post-hoc edge cast.

Likewise, a producer `n:nat -> vector n` wired from a canonical constant `3`
can feed `vector 3`; the schema checker substitutes the declared constant
and proves exact equality. A producer of `Prime n` remains expressible when
`Prime` is a registered schema family. Unsupported `Prime` internals can be
opaque while retaining exact family identity and index equality.

## Alternative formulations considered

| Route | Finding | Decision |
|---|---|---|
| Typed-constructor AST | F* authoring can construct a typed witness, but ordinary graph encoding erases it. AST alone cannot recreate a dependent witness after decoding. | Keep as optional builder frontend; it must call the common resolver. |
| Canonical schema/type-expression checker | Provides first-order syntax, symbolic port inference, terminating equality rules, and a checkable completeness boundary. | Selected base mechanism. |
| Meta-F*/proof reflection | Useful to author or verify schemas and proofs; quotation and proof-state inspection are metaprogramming facilities, not a general extracted runtime type reifier. | Optional authoring/verifier tool, not runtime resolver. |
| Per-Work resolver callback | Can prove useful package-specific cases, but arbitrary callback existence does not provide generic completeness and can create Kernel/Graph layering problems. | Allowed only as a pinned, proved schema extension dispatched by registry-wide resolver. |
| Arbitrary `Type0` equality oracle | Would hide the central proof/recovery problem; type identity and a prior author-side witness are not enough to reconstruct erased evidence. | Rejected as an unproved abstraction. A fully general proof-term checker is a separate scope requiring an explicit design. |

The selected route is conservative about expressibility, not about
correctness: unsupported equality is rejected, while every accepted equality
is proved for all legal internal environments. The upstream F* documentation
supports the distinction: its SMT logic need not decide arbitrary formulas,
and Meta-F* exposes quotation/proof construction as metaprogramming rather
than an automatic runtime reifier ([SMT logic](https://fstar-lang.org/tutorial/book/part1/part1_prop_assertions.html),
[Meta-F*](https://fstar-lang.org/tutorial/book/part5/part5_meta.html)).

## Proof obligations assigned downstream

S2-02 must bind canonical schemas, family rules, resolver identity, codecs,
and exact executable packages into one immutable manifest. S2-03 must define
and prove the concrete schema AST, denotation coherence, total normalization,
equality-checker soundness/completeness, wire inference soundness, builder
completeness, and decode/resolver agreement. S2-04 must prove generator
admission for every input/allocation and typed global-DAG substitution. S2-05
and S2-09 preserve the authorization ghost fact and exact committed graph
through replay and every crash cut.

## Independent evidence and review

The design compared raw syntax, current typed witnesses, and existing
registry boundaries. Current source facts: `GraphDesc` stores first-order
syntax; `wire_typing_witness` is proof-side; graph codec round-trip proves
syntax only; generic `resolve_graph` is absent; builder assumptions/admissions
remain. See the S2-00 ledger and the independent reports:

- [schema route](/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-01-schema-route.md)
- [route comparison](/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-01-route-comparison.md)
- [resolver boundary](/Users/alex/areas/temp/fstar_v2_s2_execution_2026-10-13/S2-01-resolver-boundary.md)

These are research evidence, not proof artifacts. S2-01 selects the
constructive boundary; all downstream theorem statements remain targets until
implemented and proved.

## S2-03 policy refinement — 2026-10-13

The original S2-01 text allowed a pinned validator postcondition to narrow
the external-port legal set. S2-03 reviewed this against the stricter project
requirement that graph compatibility be decided from declared types and
static graph syntax, without asking an external operation to prove an edge
relation. The normative policy is therefore stricter: `LegalEnv` ranges over
the full declared output family, and validator postconditions cannot exclude
inhabitants from graph typing. The full family includes every value the
validator can accept. If a subset restriction is required for composition,
encode it in the declared result family and have validation construct the
required evidence. This can reject a graph that would be safe only because a
particular validator accepts a narrower subset; that loss is intentional.

This refines the external-value clause above; it does not change S2-01's
resolver choice, `SchemaSupported` completeness boundary, or DAG dependencies.
S2-03's report and the current [implementation specification](../../schema_era_2026-10-14/implementation_spec.md)
are normative for the resolved policy.

The earlier “S2-03 must define and prove the concrete F* encoding” wording in
this report was also clarified by the active DAG's spec-only scope. S2-03
defines the candidate AST, semantic judgments, exact theorem contracts, and
proof dependency order. The later implementation DAG must write and verify
the F* declarations and proof terms. No source-level theorem is claimed by
the S2-03 specification milestone.
