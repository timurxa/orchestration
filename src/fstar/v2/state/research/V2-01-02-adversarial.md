# V2-01 / V2-02 adversarial review

> **Historical snapshot — pre-simplification.** The source description and
> recommendations below predate the current capture-free typed graph API.
> Use `V2-01-02-simplification.md` and the implementation spec for current
> decisions; retain this file as provenance for the original counterexamples.

## Verdict

Current kernel does **not** meet V2-01 or V2-02 acceptance. It only declares indexed codec/code/operation/generator records, work constructors, and a byte-only graph descriptor. No registry, typed DAG, wire language, builder, graph predicate, or P0/P1 theorem exists. This is a gap inventory, not implementation evidence.

References: [`Kernel.fst`](../../src/WorkflowV2/Kernel.fst#L33) lines 33–50 codec laws; 53–70 code/operation refs; 73–78 byte-only `graph_desc`; 88–124 generator/work/reference/package; [`work_dag.md`](../work_dag.md#L47) acceptance.

## V2-01 / P0: exact acceptance gaps

Spec P0 requires identity resolution to exact definitions, exact indexed decoding, and canonical accepted encodings (spec lines 913–914). Kernel currently has only identity-shaped records (`Kernel.fst` 9–31). Those records do not establish identity uniqueness, immutability, or a mapping from key to implementation.

Concrete gaps:

- `codec_id` is a field next to arbitrary `encode`/`decode` fields (`Kernel.fst` 33–40). Two different codec records can carry same identity. No registry or uniqueness lemma rejects this collision.
- `code_ref_id`, `operation_ref_id`, and `generator_ref_id` likewise sit beside executable fields (`Kernel.fst` 53–60, 62–70, 88–97). No resolution theorem connects identity to `run`, validator, or generator function.
- `work_ref` carries an identity, capture bytes, and schema IDs, but no resolver or refinement proof (`Kernel.fst` 110–120). `work_package` permits an arbitrary executable `work` paired with an unrelated durable reference (`Kernel.fst` 122–125). Counterexample: package `LocalWork f` with ref naming `g`; recovery resolves `g`, while current in-memory run executes `f`.
- Codec roundtrip/canonical fields prove laws only for each supplied record (`Kernel.fst` 33–50). They do not prove that a registry-selected codec is the same record as the one named by a durable identity, nor that every accepted reference uses it.
- `digest = bytes` (`Kernel.fst` 6–7). No hash assumptions exist. Avoid digest-equality-as-definition-equality. Exact identity should mean structural key equality plus registry uniqueness, or carry explicit collision-resistance premise if digest is used as semantic equality.
- No pinned graph-codec identity exists yet; `graph_desc` is just payload bytes (`Kernel.fst` 73–78). Thus graph-codec identity and its binding to implementation/schema/canonicalization cannot be shown.
- Identity key/capture serialization laws are absent. `work_ref.canonical_capture` is an unconstrained byte list; no proof says it decodes to the executable package's capture or re-encodes identically.
- No event/action vocabulary exists despite V2-01's separate deliverable (`work_dag.md` 47). Do not mark V2-01 complete on P0 alone.

Minimum proof-friendly P0 design:

1. Define typed pinned refs whose identity, codecs, capture bytes, and semantic value are linked by a refinement, not adjacent fields. E.g. `ResolvedCodec a = { key; implementation: codec a; key_matches: registry_key implementation == key }` (adapt equality to F*'s supported equality/propositional equality).
2. Define immutable registry lookup returning the exact typed package plus an equality witness to the requested key. Prove lookup determinism/uniqueness and reject absent or duplicate keys. State registry version/snapshot as premise for persistence across restart; give premise owner and discharge condition.
3. Define `WorkPackage` so construction requires `resolve(work_ref) == Some executable_work` with equality/refinement evidence. Remove free pairing of unrelated `work` and `work_ref`.
4. Prove indexed decode is confined to `o x`; codec roundtrip and canonicality follow from laws on the *resolved* codec. Prove accepted bytes decode then re-encode identically. Do not cast bytes into a type.
5. Give exact equality meaning for code/operation/generator/graph-codec implementations. If build digest is only key material, registry uniqueness must bind full definition; if digest is treated as equality evidence, explicitly assume/prove collision resistance.

Lemma shape (theorem, not axiom):

```fstar
val resolve_exact : r:Registry -> ref:TypedRef a ->
  Lemma (resolve r ref == Some (p, pf) ==>
         key p == ref.key /\ semantic_definition p == ref.definition)
val decode_canonical_exact : r:Registry -> c:ResolvedCodec a -> b:bytes -> x:a ->
  Lemma (decode c b == Some x ==> b == encode c x)
val work_refines : r:Registry -> p:WorkPackage i o ->
  Lemma (resolve_work r p.durable_work_ref == Some p.executable_work)
```

`semantic_definition` needs concrete equality/refinement definition per package kind; vague “same identity” predicate would merely rename P0. Registry immutability and provider/runtime version availability remain explicit boundary premises, not top-level conclusions.

## V2-02 / P1: exact acceptance gaps

P1 requires explicit finite/unique/typed/topological DAG predicate; start/add/finish and constant laws; soundness for every accepted descriptor; completeness for every such DAG over pinned work refs and codec-backed constants (spec lines 364–400, 438–466, 913–915). Current `graph_desc` is only `{ graph_payload: bytes }`; no interpretation or constructor can establish any part of that contract (`Kernel.fst` 73–78). P1 is wholly unimplemented.

More specifically, source lacks:

- finite occurrence set, unique occurrence keys, total/exact label/input-wire domains, topological permutation, or rank-decreasing edges;
- existentially packed heterogeneous `Work` labels and any typing judgment for wires;
- first-order `Wire` constructors, canonical codec-backed constants, fan-out references, product/dependent-pair wiring, or root/output typing;
- `PortContext`, `PortEnv`, `Wiring`, `PortRef`, `start_graph`, `add_node`, `finish_graph`, `dag_wf`, interpretation, isomorphism, or their laws;
- any accepted-descriptor rule. Arbitrary bytes are not a graph language; a decoder could accept malformed bytes or silently map every payload to one empty graph;
- proof that same `WorkRef` can occur at multiple distinct node keys without merging occurrences.

## Minimal proof-friendly typed construction

Use an indexed dependent telescope as builder state, plus a separate finite DAG model. This matches spec's intended topological construction and makes typing structural.

- Context starts with root port of type `x`.
- `Wiring ctx a` is first-order syntax with typed constructors for root, prior `PortRef`, canonical typed constant, dependent pair, `fst`, `snd`. No closure or arbitrary transform.
- A packed work node is existential: `PackWork (a:Type0) (b:a -> Type0) (w:Work a b)`. Its input wiring must have type `a`; append one *fresh occurrence key* and extend telescope by output type `b (eval wiring env)`.
- `PortRef` identifies occurrence, not work identity. Reuse one ref for fan-out; use different fresh refs for repeated occurrences of same pinned work.
- `finish_graph` accepts only wiring of exact result type `o x` and records it. Descriptor can be canonical sequence of typed node records in telescope order, plus output wiring; persistence encoding later stores refs/bytes only.
- Interpret sequence as vertices plus wires; vertices are unique by fresh-key invariant, construction sequence itself is topological order, and every edge targets prior position. `dag_wf` is a conjunction of these concrete properties and syntax-directed wire typing.

This suffices for arbitrary finite graph **under spec's stated input-wire restriction**: every node input is formed from root, prior outputs, and constants by product construction/projections. To build a given DAG, follow its supplied topological order; maintain a map from old key to new typed `PortRef`; translate each old wire recursively; decode each canonical constant using its exact registry codec; append node; map its old key to returned ref. Translate output wire, then finish. Fan-out works because map entries remain reusable. Unused/disconnected occurrences work too if their inputs are constant-derived; builder preserves all vertices, even if output cannot reach them. If arbitrary source vertices with *no* typed input term are intended, graph model/API must say how such nodes receive inputs; current spec provides constants as source mechanism.

Completeness depends on two nontrivial premises made concrete: a well-formed input DAG contains a finite topological order, and every accepted constant wire has canonical codec evidence. If `FiniteTypedDAG` already stores topological order as spec says, no topological-sort algorithm is needed; prove permutation and rank facts.

Proof lemma shape:

```fstar
val start_exact : x:i -> Lemma (interpret (start_graph x) == root_only_graph x)
val add_exact : b:Builder ctx -> w:Work a family -> iw:Wiring ctx a ->
  Lemma (fresh key ==> interpret (add_node b w iw) == extend_one (interpret b) w iw)
val builder_sound : g:GraphDesc i o x -> Lemma (graph_wf g ==> dag_wf (interpret g))
val build_prefix : dag:FiniteTypedDAG i o x ->
  Lemma (dag_wf dag ==> each topological prefix has typed builder/map preserving exact prior vertices and wires)
val builder_complete : dag:FiniteTypedDAG i o x -> Lemma
  (dag_wf dag ==> exists g. graph_wf g /\ graph_isomorphic (interpret g) dag)
val finish_exact : b:Builder ctx -> out:Wiring ctx (o x) ->
  Lemma (interpret (finish_graph b out) preserves nodes and records out)
```

`build_prefix` is induction on topological order. Main induction invariant: old vertices seen so far map bijectively to builder occurrences; labels and input wires preserved by renaming; all old output types equal mapped port types; no edge reaches unseen vertex. Translate `PairWire`/projections structurally. Then finish proof handles output type exactly. Soundness proof is structural over builder operations; no separate unchecked graph constructor may be accepted.

## Counterexamples to weaker variants

1. **Linear-only builder:** root `Nat`; `A: Nat -> Bool`, `B: Nat -> String`, `C: Bool * String -> Unit`; edges root→A, root→B, A/B→C. A builder exposing only most recent output cannot wire both A and B into C. Fan-out plus old-port map required.
2. **No topological rank check:** `A:Nat->Nat`, `B:Nat->Nat`; A reads B, B reads A. Every local type checks, graph is cyclic. Local wire typing alone does not prove DAG/acyclicity.
3. **No wire typing:** producer `Nat -> Bool`, consumer `Nat -> Unit`, wire producer output into consumer. Key existence and acyclic order pass; input type fails.
4. **No key freshness / key equals work identity:** two occurrences of same pinned `inc:Nat->Nat`, both fed root, output pair of both results. Identity-based keys collapse distinct vertices; occurrences and edges lost.
5. **No output typing:** graph computes `Nat`, but output wire selects `Bool` port while graph index claims `o x = Nat`. Node checks do not imply interface correctness.
6. **List of homogeneous nodes:** cannot express `Nat -> Bool -> String` chain or heterogeneous fan-in without unsafe casts or erasing type evidence. Existential packing plus typed wire witnesses needed.
7. **Opaque payload with permissive decoder:** accept bytes for a graph containing a forward edge/cycle or wrong constant codec; map to a fixed graph. This may satisfy a vacuous “some interpretation” but fails soundness and completeness/isomorphism.
8. **Builder completeness only for reachable nodes:** DAG may include independent valid work node fed a constant, while output uses only root. A builder that prunes dead nodes violates required occurrence-preserving isomorphism.

## Next investigation

Audit root's candidate V2-01/V2-02 source once present, then run verifier. Check (a) every identity has exact resolver witness and no free work/ref pairing; (b) descriptor bytes cannot bypass typed parser; (c) builder proof induction follows arbitrary supplied topological order, retaining dead nodes/fan-out; (d) occurrence keys differ for repeated same work; (e) edge rank and output interface proofs are explicit. Add tiny hand-constructed DAG terms for counterexamples 1–5 as proof obligations, not as a substitute for theorem. Report any `assume`, `admit`, opaque predicate, or unverified graph isomorphism as outstanding acceptance gap.
