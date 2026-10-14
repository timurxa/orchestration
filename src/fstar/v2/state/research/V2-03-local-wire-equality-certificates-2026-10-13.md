# V2-03: local wire-equality certificates

**Status:** design alternative; not implemented or F*-checked.

## Finding

A compatibility row keyed only by producer and consumer Work can reject a
valid graph edge. Let a producer have input `nat` and output family
`fun n -> Prime n`; wire its input to constant `0`; let the consumer input be
`Prime 0`. The required edge fact is
`forall env. Prime (input_wire env) == Prime 0`, which holds. A global row
requiring `forall n. Prime n == Prime 0` is false.

This is the current resolver gap: Work output is input-indexed
([Kernel.fst:110-124](../../src/WorkflowV2.Kernel.fst)); each typed node
currently requires a fixed input carrier
([Graph.fst:606-623](../../src/WorkflowV2.Graph.fst)); and the typed wire
witness retains dependent port families for root, constants, outputs, and
structural pairs/projections ([Graph.fst:304-349](../../src/WorkflowV2.Graph.fst)).
But durable wire syntax stores labels and bytes, not the universal equality
needed at a node boundary ([Kernel.fst:68-87](../../src/WorkflowV2.Kernel.fst)).
Registry lookup establishes exact package membership only
([Identity.fst:106-139](../../src/WorkflowV2.Identity.fst)).

## Alternative: graph-local equality certificate

Store a finite certificate for each node-input type conversion, bound to that
wire and the exact graph prefix. Its terms describe the wire's type as a
family over every legal prior-port environment. A checker validates the
certificate using a pinned manifest of exact type/family packages and lemmas.
The following is F*-shaped notation; AST and dependent-pair bookkeeping are
schematic.

```fstar
type value_term (ctx:schema_context) : Type0 =
  | RootValue
  | PriorPortValue : node_key -> value_term ctx
  | DecodedConstant : codec_identity -> bytes -> value_term ctx
  | PairValue : value_term ctx -> value_term ctx -> value_term ctx
  | FirstValue : value_term ctx -> value_term ctx
  | SecondValue : value_term ctx -> value_term ctx

type type_term (ctx:schema_context) : Type0 =
  | NamedType : schema_identity -> type_term ctx
  | ApplyFamily : family_identity -> value_term ctx -> type_term ctx
  // Dependent binder syntax omitted; manifest checker enforces typing.
  | DepPairType : type_term ctx -> dependent_type_term ctx -> type_term ctx

type equality_certificate (ctx:schema_context)
    : type_term ctx -> type_term ctx -> Type0 =
  | EqRefl : t:type_term ctx -> equality_certificate ctx t t
  | EqSym : left:type_term ctx -> right:type_term ctx
      -> equality_certificate ctx left right
      -> equality_certificate ctx right left
  | EqTrans : left:type_term ctx -> middle:type_term ctx
      -> right:type_term ctx
      -> equality_certificate ctx left middle
      -> equality_certificate ctx middle right
      -> equality_certificate ctx left right
  | EqCongruence : left:type_term ctx -> right:type_term ctx
      -> registered_type_constructor
      -> equality_certificate ctx left right
  | EqFamilyLemma : left:type_term ctx -> right:type_term ctx
      -> lemma_identity -> list (value_term ctx)
      -> equality_certificate ctx left right

val check_type_equality : manifest -> ctx:schema_context
  -> source:type_term ctx -> target:type_term ctx
  -> cert:equality_certificate ctx source target -> Tot bool

val check_type_equality_sound : manifest -> ctx:schema_context
  -> source:type_term ctx -> target:type_term ctx
  -> cert:equality_certificate ctx source target
  -> Lemma (check_type_equality manifest ctx source target cert == true
       ==> forall env:denote_context ctx.
             denote_type manifest source env ==
             denote_type manifest target env)
```

Here `ApplyFamily` expresses dependent output types after substitution of
symbolic wire values. `EqCongruence` and `EqFamilyLemma` payloads must match
the registered constructor/lemma endpoints; checker enforces that. The
checker returns an executable Boolean, so malformed or unsupported
certificates reject after extraction. The manifest binds schema, family,
constructor, and lemma identifiers to exact typed F* packages/proofs. The
certificate is data; the accepted branch obtains the equality proof from the
checker soundness theorem. No Work is executed to discover outputs.

The resolver builds symbolic terms from wire syntax and prior typed packages:
Root uses the fixed root input; constants use the selected codec carrier (or
indexed carrier at the exact root input); Output uses the prior Work's output
family applied to the symbolic term for that node's input wire. Pair/Fst/Snd
are typed structurally, with dependent-pair details checked compositionally;
they need no separate pair-family codec. In the example, the producer input
term is the decoded constant `0`, so the output type reduces to `Prime 0`.
For an arbitrary prior output, the term remains symbolic and the certificate
must prove equality for every legal port environment.

On acceptance, resolver transports the wire typing witness to the exact
selected Work input carrier, appends that typed output family to the port
telescope, and continues. It rejects unknown identities, absent prior ports,
invalid constant decoding, ill-typed terms, or certificates the checker
cannot validate. The accepted certificate is evidence from which resolver
builds the existing `typed_graph_witness`; it is not a runtime hint. For
completeness over every descriptor, certificates must be mandatory in the
descriptor representation and `graph_wf` must require that they check and
resolve. Keeping the current broader semantic `graph_wf` predicate instead
leaves valid but uncertified equalities outside resolver completeness.

## Resolver theorem shape and boundary

Use the spec's existing result-refinement shape, with `certified_graph_desc`
meaning graph syntax plus mandatory edge certificates and `graph_wf` defined
over that certified descriptor. These signatures are schematic, not compiled:

```fstar
val resolve_graph : bundle -> x:i -> g:certified_graph_desc i o x
  -> Tot (option (resolved:certified_graph_desc i o x{
       resolved == g /\ graph_wf bundle x resolved}))

val resolve_graph_complete : bundle -> x:i -> g:certified_graph_desc i o x
  -> graph_wf bundle x g -> Lemma
       (match resolve_graph bundle x g with
        | None -> False
        | Some resolved -> resolved == g)
```

Here `graph_wf` is deliberately redefined over the certified descriptor: it
requires resolver/checker evidence and yields the existing typed graph
witness. The refinement gives soundness; completeness then covers every
descriptor admitted by this *restricted* validity predicate. This does
**not** prove completeness for the current broader meaning of `graph_wf`
(existence of any typed witness for raw `graph_desc`) unless every such
witness has a certificate in this grammar. A typed builder must emit a
certificate for each input edge. Arbitrary F* equality proofs erased from the
descriptor cannot be reconstructed. A finite grammar is complete only for
equalities derivable by its rules plus pinned lemmas; valid edges outside that
language reject. Reifying and checking arbitrary F* proof terms would widen
the language but amounts to a much larger proof-checker project. Thus this
route cannot preserve unrestricted completeness without either narrowing
valid graphs to the certified language or implementing a proof-term checker.

Certificates must be encoded in canonical graph bytes, or stored as a
durable sidecar bound to those bytes. Current graph codec roundtrip and
canonicality cover raw graph syntax only
([GraphCodec.fst:362-390, 635-645](../../src/fstar/v2/src/WorkflowV2.GraphCodec.fst));
adding certificates requires extending encoding, decoding, and those proofs.

## Comparison

- **Work-pair compatibility table:** simplest; proves a global condition for
  every possible producer input. It rejects graph-specific range cases such
  as the fixed `0` above.
- **Schema-token manifest:** necessary to resolve serialized identities to
  exact typed packages, but matching tokens alone cannot prove that a
  dependent family composed with this graph's input wire equals the consumer
  carrier for every prior-port environment.
- **Local equality certificate:** graph-specific and constructive; handles
  the fixed-input example without running Work. It adds a certificate AST,
  checker, builder evidence, and canonical serialization, and is complete
  only relative to its declared equality calculus and pinned lemmas.
