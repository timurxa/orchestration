# A00 integrated refactor map

**Decision status:** source architecture selected from the normative spec,
implementation packet, source inventory, proof-gap audit, and simplification
audit. This is a migration map, not an implementation. No F* source changed.

## Current verified baseline and its limit

`opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C
src/fstar/v2 verify` passed all seven existing modules with F* 2026.03.24,
Z3 4.13.3, and OCaml 5.3.0. The result establishes that the present source
typechecks in that environment. It does not establish the generic builder
laws: `WorkflowV2.Graph.fst:418-424` and `:523-535` cross `assume` boundaries;
`start_graph_law`, `add_node_appends_exact`, `finish_graph_sound`, and
`graph_complete` use `admit()` at `:908-956`. F* accepts those escape hatches
in a successful check. All future theorem claims must audit transitive trust,
not only report a passing Make target.

## Source disposition

| Current source | Retain as proof substrate | Split or replace | Target DAG owner |
|---|---|---|---|
| `Kernel.fst` | Identity encodings, plain/indexed codec concepts, the `Work` sum, first-order wire/descriptor concepts | Reconcile signatures in one kernel; add manifest schema/artifact syntax and run metric; remove duplicated signature/budget sources. No arbitrary F* AST reflection. | A02 |
| `Identity.fst` | Structural identity comparison and useful exact lookup lemmas | Replace independent editable registry/bundle truth with canonical manifest projection plus a coherent executable bundle. Preserve codec tables only as a derived/proved view or canonical package table. | A03–A04 |
| `Graph.fst` | Dependent port telescope, recursive wire typing, prior-port/scope lemmas, allocation predicates where they match the spec | Split first-order syntax, schema resolver, generator admission, builder, and allocation. Replace assumed builder representation/operations and admitted laws with constructive definitions and proofs. Existential `graph_wf` is not a decoder; recovery needs a resolver that constructs its typed witness from syntax and pinned schema. | A05–A08, A15–A17 |
| `GraphCodec.fst` | Complete-input parser, syntax roundtrip and accepted-byte canonicality proofs | Keep this strictly as syntax codec. Compose it with the shared pinned resolver in a separate layer; do not claim syntax decode is typed reconstruction. | A09–A10 |
| `GenerationExample.fst`, `ChainProof.fst` | Reuse small codec/generator/chain constructions as examples after generic interfaces settle | Do not count a single chain family as builder completeness, universal generator membership, arbitrary topology, P4 splice, or recovery. Rebase examples on public verified API. | A35; possible local proof fixtures for A16–A17 |
| `Journal.fst` | Event and occurrence data ideas | Replace the list-only state/action vocabulary with canonical event payloads, guarded transition, replay, StateWF, and event/journal codecs. Keep semantic authority and controller state in higher layers. | A11–A14, then A24+ |
| `Makefile` | Existing full-module `verify` target and dependency-ordered input list | Extend for all modules; record actual F*/Z3 versions at final verification. Tool versions are not currently pinned. | A01, A36 |

Exact per-module source evidence and P0–P16 mapping: [source inventory](source_inventory.md)
and [proof-gap audit](proof_gap_audit.md).

## Architecture decision and alternatives considered

1. **Split by proof boundary; keep imports acyclic.** Adopt the packet's
   `Kernel → ManifestCore → Schema → GraphResolve` direction, then join
   resolver and executable tables in `Bundle`; keep `GraphCodec` syntactic
   and compose codec plus resolver in `GraphInterpretation`. `GeneratorAdmission`
   precedes and is consumed by `GraphBuilder`; `Generation` then proves
   splice/global preservation. This prevents the resolver/Bundle cycle and
   keeps Journal below Services, provenance, and Controller.

   **Alternative:** keep the current `Graph` and `Identity` monoliths. This
   saves file movement, but the resolver cannot both define bundle coherence
   and import a bundle that already depends on the resolver. It also keeps
   assumptions, schema-free witness existence, builder, allocation, and
   generator admission entangled. Preserve useful lemmas, not current file
   boundaries.

2. **Use one canonical package/manifest source of truth.** Manifest entries
   are an exact projection of pinned executable packages; lookup tables may
   be derived or separately represented only with exact projection proofs.
   Keep serialized `DurableWorkRef` redundancy until P0 proves both identity
   and every repeated field select the same full package.

   **Alternative:** independently editable work, codec, and schema lists.
   Current source demonstrates the drift risk: package-embedded codecs,
   global codec registry, and example registry are separate constructions
   (`Identity.fst:185-207, 288-292`; `GenerationExample.fst:25-74`). A cache is
   acceptable only as a proved derived view, not another authority.

3. **Resolve durable syntax into a typed witness.** P1/P2 need a terminating,
   proof-producing resolver over exactly the manifest-pinned
   `SchemaSupported` language. It must establish universal dependent-edge
   equality from declared signatures and legal static environments. It must
   reject a sigma-indexed vector connected to a fixed-length consumer unless
   the declarations prove the index equality for every legal environment.
   `graph_wf`'s existential witness (`Graph.fst:780-797`) describes a
   proposition; it is not executable reconstruction after decode.

   **Alternative:** reuse `wire_label_isomorphic` as completeness. It compares
   labels and wire syntax only (`Graph.fst:123-148`), so it does not transport
   dependent port environments, resolved work signatures, or indexed
   constants. A08/A10 need a typed correspondence, not this weaker relation.

4. **Treat local/generator proof substrate as data-level facts only.** Local
   work is total and pure, external validators may accept nondeterministic
   replies, generators are total and pure, and all three share recovered
   journal semantics. The chain example is a useful fixture; generic
   generator admission remains a package-bound universal proof over inputs,
   metric, and allocation.

## Design questions to exercise in proofs, not defer as hand-waving

- Can the selected restricted schema syntax express all representative
  workflows while allowing a terminating equality calculus? A05–A07 must
  prove soundness/completeness for the declared language, not arbitrary F*
  type equality.
- Can the graph builder accept exactly the resolver's language and prove
  completeness for every supported finite topology without edge-local proof
  payloads? A08 owns the answer; typed recovery is not complete until A10.
- Can manifest projection and package lookup avoid duplicate authority while
  still supporting constants/root entrypoints? A03–A04 must prove exactness,
  including mismatched duplicate identity counterexamples.
- Does the run-wide charge metric enter all generator/operation/allocation
  paths from one committed source? A02/A15/A16 must align this before P4/P8.
- Does every later theorem depend only on explicit proof-bearing contracts,
  with no hidden `assume`/`admit` or unreviewed solver axiom in its transitive
  dependencies? A36 audits this across the completed build.

## Immediate next work

A00 is complete at the inventory/design level. C0 records this map and the
three research reports in commit `62b5a5f`. A01 defines the actual
interface/build boundaries; A02 implements the single-source kernel
contracts. No downstream module may rely on the current admissions as if they
established P1.
