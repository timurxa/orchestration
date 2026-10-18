# A00 source/build inventory

**Inspection date:** 2026-10-13. **Scope:** read-only inspection of all current `WorkflowV2.*.fst`, Makefile, A00–C6 plan and theorem targets. No F* source changed. **Baseline result:** full Makefile verification passed with the opam-managed F* toolchain. Existing `assume`/`admit` declarations remain trust gaps; a successful check is not evidence that their conclusions were proved.

## Findings at a glance

The seven source modules form a useful typed substrate and one chain example. The full Makefile target typechecked all seven modules. `Graph.fst` still contains explicit `assume` declarations and admitted builder laws, so this result does not discharge those claims. Major missing components: manifest/schema resolver, generic graph interpretation from bytes, replay and event codec, semantic event authorization, controller/interleaving model, journal durability theorem, recovery composition and concrete refinement. The active DAG assigns these to later proof nodes; C0–C6 are commit checkpoints.

## Build/tool inventory

- Makefile: `src/fstar/v2/Makefile:1-12`. Defaults `FSTAR ?= fstar.exe`, `BUILD_DIR ?= /tmp/fstar-v2-check`, `FSTAR_FLAGS ?= --cache_off --warn_error @285`. `verify` creates build dir and invokes seven modules with `--include src`, build include, `--odir` (`:10-12`). Source order: Kernel, GraphCodec, Identity, Graph, GenerationExample, ChainProof, Journal (`:5-6`).
- Exact bounded baseline command run: `opam exec -- gtimeout --signal=TERM --kill-after=5s 10m make -C src/fstar/v2 verify`.
- Exact emitted F* command: `fstar.exe --cache_off --warn_error @285 --include "src" --include "/tmp/fstar-v2-check" --odir "/tmp/fstar-v2-check" src/WorkflowV2.Kernel.fst src/WorkflowV2.GraphCodec.fst src/WorkflowV2.Identity.fst src/WorkflowV2.Graph.fst src/WorkflowV2.GenerationExample.fst src/WorkflowV2.ChainProof.fst src/WorkflowV2.Journal.fst`.
- Result: exit 0; `All verification conditions discharged successfully`. All seven modules were reported verified. This is a typechecker result for the source as written, including F*'s accepted `assume` and `admit` escape hatches; it does not close those trust gaps.
- Tool versions: F* 2026.03.24 (`70671ffb81fa30aba09b9d6e2af275dfbccaa8f8`), OCaml 5.3.0, Z3 4.13.3 (64-bit), GNU Make 3.81, macOS Darwin 25.5.0 arm64. The Makefile pins neither F* nor Z3, so these versions are evidence for this run, not a repository-enforced toolchain.
- `gtimeout` was `/opt/homebrew/bin/gtimeout`; the 10-minute limit was not reached. The Makefile's `/tmp/fstar-v2-check` is the declared build output.

## Source module-by-module

| Module | What exists, with direct evidence | Proof/trust status and gap |
|---|---|---|
| `WorkflowV2.Kernel` | First-order IDs and references (`WorkflowV2.Kernel.fst:10-62`); wire/node/graph syntax (`:63-88`); codec contracts (`:90-108`); local/op/generator signatures and `Work` sum (`:110-185`); generation/budget records (`:141-165`). | Mostly declarations and proof-bearing record fields, not implementations of codecs/services. `roundtrip`, `canonical`, validator, and graph-codec laws are obligations carried as fields (`:90-138`). No custom schema AST, resolver, manifest, root entry, opaque typed artifact schema, or single run charge metric. `generator_ref.generate_graph` takes `generation_allocation` only (`:167-175`); compare normative metric parameter in spec §2.2 / DAG A02. `op_ref` has `maximum_charge` (`:117-124`). |
| `WorkflowV2.Identity` | Boolean identity equality plus soundness lemmas (`Identity.fst:6-87`); packed/global work and codec tables/lookups (`:84-283`); input encode/decode selection and canonicality (`:294-318`). | Lookup lemmas rely on uniqueness proof fields in registry records (work registry around `:100-115`, codec registry `:203-216`), so result is uniqueness of a matching package in supplied tables, not proof tables are exact projection of a manifest. `pinned_registry_bundle` only holds identity + work/codec tables (`:284-292`); comments explicitly reserve identity-to-content and host reload binding for P0 (`:285-287`). No registry manifest/root entry/schema/resolver. Proof bodies typecheck in the recorded baseline, subject to the source trust boundary. |
| `WorkflowV2.Graph` | Finite graph representation and syntax interpretation (`Graph.fst:10-150`); dependent port context/references (`:153-303`); wire typing and Wiring (`:304-417`); builder reachability and typed node sequence (`:418-765`); existential typed graph witness and graph/DAG predicates (`:766-798`); allocation predicates and generator admission interface (`:799-905`). | Explicit trust holes: `assume type graph_builder` and `assume val builder_nodes` (`:418-422`); assumed `start_graph`, `add_node` (`:523-525`); `start_graph_law`, `add_node_appends_exact`, `finish_graph_sound`, `graph_complete` end in `admit()` (`:908-956`). `generator_admission` has a universal callback-validity proof field (`:881-895`), but generic proof constructor is absent; not generic P4. `graph_wf` existentially asserts some witness (`:780-797`), which is not executable resolution. `wire_label_isomorphic` is raw label/wire relation (definition `:123-150`); not required typed dependent isomorphism. |
| `WorkflowV2.GraphCodec` | First-order encoders/decoders for IDs, work refs, wires, nodes, graph syntax (`GraphCodec.fst:11-477`); parser requires complete input/EOF (`:461-482`); structural wire/node/list/graph roundtrip and accepted-byte canonicality lemmas (`:488-645`). | This is syntax serialization only. `decode_graph_syntax` returns `graph_desc`, not resolved typed witness (`:477-482`); no bundle resolver or graph-witness reconstruction. Its proof bodies typecheck in the recorded baseline. It covers A09 portion only, not P2/A10. |
| `WorkflowV2.GenerationExample` | Concrete Nat codec/indexed codec, increment local Work, graph codec and chain generator/table (`GenerationExample.fst:12-58`, `:76-203`); recursions and lemmas for chain lengths/keys/plan validity/roundtrip (`:207-319`). | Example-specific data and proof bodies. Codec laws are populated with proof terms in the example, while generic Kernel records only state contracts. Chain's static graph codec can roundtrip syntax but does not resolve arbitrary decoded graphs. Example's input-shaped chain is not universal generator admission for all packages nor arbitrary topology. |
| `WorkflowV2.ChainProof` | Builds a chain in typed builder vocabulary (`ChainProof.fst:10-99`), defines typed witness/topology and proves `graph_wf` for chain (`:100-276`), plus exact chain allocation properties and generator admission (`:277-323`). | Concrete chain-family proof body, not generic builder completeness/P1, schema resolver/P2, global splice/P4, or journal recovery. Depends on Graph's type definitions; the hand-built descriptor proof does not use the assumed builder constructors. Proof terms typecheck in the recorded baseline. |
| `WorkflowV2.Journal` | Run/event/occurrence/allocation/artifact payload records (`Journal.fst:7-80`); five event constructors, action vocabulary (`:82-105`); `journal=list event`, state holding history (`:107-113`). | No replay, `apply`, StateWF, terminal projection, event/journal codec, append authorization, controller, or durable store. Source comment says later work defines replay and vocabulary grants no transition authority (`:107-108`). These are declarations only; P3 and P10 are absent. |

### Ordinary proof terms vs claims of verification

Source has many terms whose types are `Lemma`, including identity equality/lookup proofs, graph structural lemmas, codec reconstruction/canonicality, and chain proofs. `GraphCodec.fst:637-645` is the clearest generic syntax roundtrip/canonicality endpoint; `ChainProof.fst:252-275` derives chain `graph_wf`; `:317-323` packages chain generator admission. These proof terms typecheck in the recorded baseline. Kernel codec/Work laws and `generator_admission.generator_result_valid` are declarations/proof fields supplied by package values, not theorem bodies that prove the whole system. `Graph.fst` visibly contains `assume`/`admit()`; therefore successful typechecking is not proof that all source theorem paths are closed.

## Current module imports and cycle/refactor risks

Observed imports:

- Kernel: no project imports.
- GraphCodec: Kernel (`GraphCodec.fst:3-7`).
- Identity: Kernel (`Identity.fst:1-3`).
- Graph: Kernel + Identity (`Graph.fst:1-4`).
- GenerationExample: Kernel + Graph + GraphCodec + Identity (`GenerationExample.fst:1-7`).
- ChainProof: Kernel + Graph + Identity + GenerationExample (`ChainProof.fst:1-8`).
- Journal: Kernel + Identity (`Journal.fst:1-4`).

This current graph is acyclic in Makefile order. Planned architecture must avoid collapsing `GraphResolver` into a Bundle that imports resolver while resolver imports bundle; packet explicitly puts ManifestCore/Schema/GraphResolve below Bundle (`implementation_packet.md:242-250, 271-290`). `GeneratorAdmission` must be below GraphBuilder; GraphInterpretation composes codec/resolver/bundle after resolver; Journal consumes typed interpretation but not Services/EventAuthority (`:249-259, 271-290`). Current `Graph.fst` combines syntax interpretation, schema-free typed witnesses, builder, allocation and generator admission (`:1-956`); `Identity.fst` combines equality, package tables, lookup and bundle (`:1-322`). Split along packet boundaries; preserve API laws, not current file boundaries. Journal can stay below services and authority; do not import controller/services back into it.

## Mapping existing artifacts to planned A00–C6 and P0–P16

A00–C6 status and definitions are in `state/work_dag.md:187-232`; high-level edges in `:104-175`. Existing source is input evidence, not completion of nodes. A00 records this inventory; C0 checkpoints it in Git.

| Existing artifact | Closest planned owner(s) | What it contributes / does not discharge |
|---|---|---|
| `Kernel.fst` | A02; portions may be retained during A03/A09/A11 | Signatures and syntax starting point. Needs schema AST, artifact syntax, run charge metric and alignment; codecs need actual implementation/proof boundary. |
| `Identity.fst` | A02/A03/A04 (P0) | Typed package lookup/equality starting point. Needs manifest projection, disjoint canonical identity domains, linked tables/root resolver exactness, restart-stable bundle. No P0. |
| `Graph.fst` | A07/A08 (P1), A15/A16, A17; some graph types for A10 | Port telescope/wire witness concepts and allocation predicates reusable selectively. Builder laws admitted; no schema-edge resolver or exact completeness. No P1/P4. Split per packet. |
| `GraphCodec.fst` | A09 (syntax part of P2) | Real syntax codec and proof-body evidence. No typed graph interpretation/A10; no full P2. |
| `GenerationExample.fst`, `ChainProof.fst` | A35 example seeds; possibly A16/A17 design examples | One chain construction and generator-validity proof. No generic universal generator membership/admission, typed splice, all shapes, or P4. Do not count example as theorem owner completion. |
| `Journal.fst` | A11 data seed | Five-event/occurrence data shape. Replay and payload bytes are not yet enough for A11; no A12/P3/A14/A24/P10. |
| Makefile | A00 build evidence; A36 full-check command seed | Seven-module command exists and passed in this run. A36 must rerun the full check after implementation, inspect trust dependencies, and record tool versions. |

Planned milestones needing new/reworked source, not current modules:

- **A01–A04 / C1 (P0):** module/API boundary, kernel contracts, canonical ManifestCore, exact bundle. Existing Kernel/Identity pieces seed A02/A04 only. Spec §2 and §6 P0; packet §3.
- **A05–A10 / C2 (P1–P2):** schema/LegalEnv, terminating equality calculus, universal edge resolver, builder completeness, canonical syntax codec, and typed decode. Existing Graph/GraphCodec only seed disconnected parts; resolver and sound complete builder are absent.
- **A15–A16 (prerequisites to A08/C2):** exact allocation/occurrence model and universal package-bound generator admission. These are separate DAG branches after resolver foundations; A08 depends on A16, so C2 cannot checkpoint until builder, codec, typed decode, allocation, and generator admission are complete. Work DAG `:198-204`.
- **A11–A13 / C3 (P3):** canonical event transitions, event/journal codec, replay/StateWF. Journal has event skeleton only. Work DAG `:205-208`.
- **A14–A26 / C4 (P4–P10):** ghost authority/SemWF, typed splice and exact graph commit, local provenance, keyed adapter, ledgers, optional artifact identity, serial journaler contract/every-cut durability, exact generated recovery. No implementation modules currently. Work DAG `:209-220`.
- **A27–A31 / C5 (P15/P11/P12):** services/controller, ready-input/claim lemmas, all-schedule safety, frontier, well-founded rank. Entirely absent. Work DAG `:221-226`.
- **A32–A36 / C6 (P16/P13/P14):** recovered semantic graph theorem, generic concrete-refinement schema (not concrete runtime instance), conditional termination, proof-bearing examples, integrated trust/full-check audit. Entirely absent. Work DAG `:227-232`.

The specification's required targets and dependencies are authoritative at `implementation_spec.md:2621-2685` (P0–P16); scope is abstract system plus generic P13 transfer, not SQLite/filesystem/network implementation. P9 is conditional on persistent backing identity. Active node status is maintained in `work_dag.md` and `state.md`; historical S2 records do not represent current execution.

## Duplicated sources of truth / mismatches to resolve

1. **Identity to bundle:** `pinned_registry_bundle` pairs registry identity with work/codec registries but no manifest relation (`Identity.fst:284-292`). P0 cannot follow from member lookup alone. Spec §2.2 / P0; A03/A04.
2. **Charge metric:** source has per-work maximum and allocation numbers but no pinned run-wide metric in `run_budget` or `generator_ref` (`Kernel.fst:117-124, 141-175`); spec's unified metric and generator arguments feed P0/P4/P8, DAG A02/A15 (`work_dag.md:192,199`). Align once in Kernel, avoid parallel budget sources.
3. **Graph definition duplication:** source `finite_typed_dag` uses label/input partial maps and topological order (`Graph.fst:10-17`), while durable `GraphDesc` is ordered node list (`Kernel.fst:76-88`). `interpret_graph` bridges them (`Graph.fst:64-90`), but raw `wire_label_isomorphic` is insufficient for typed dependent contexts. A10 must fix one canonical syntax/typed interpretation.
4. **Registry/work membership:** package tables and durable-ref lookup in Identity, `graph_wf` resolver using them in Graph, and example-specific tables in GenerationExample create multiple registry constructions (`Identity.fst:84-283`, `Graph.fst:795-797`, `GenerationExample.fst:168-203`). Manifest/bundle must be one source of identity and schema denotation.
5. **Proof boundary:** codec and graph-codec records in Kernel make laws fields; example supplies Nat proofs. Later contracts must preserve these as explicit proven package properties, not allow a hidden `assume` or duplicate codec law sources (`implementation_spec.md:27-31`; `work_dag.md:192`).

## Strongest caveat and unresolved follow-up

**Strongest caveat:** the successful build accepts explicit admitted/assumed generic builder operations. It checks the remaining proof terms but cannot establish P0–P16 because the manifest resolver, replay, semantic authorization, controller, durability, recovery, and refinement layers are absent.

**Next proof focus:** preserve only useful foundations after trust-auditing transitive dependencies. Central technical bottleneck remains A05–A10: implement a terminating manifest-schema equality/resolution calculus proving universal dependent edge compatibility and builder/typed-decode completeness for `SchemaSupported`. The verified baseline and tool versions are recorded above; the toolchain is not pinned by the Makefile.
