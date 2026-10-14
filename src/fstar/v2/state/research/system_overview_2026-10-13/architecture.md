# Architecture evidence: F* workflow v2

Scope: independent source/doc trace for explanatory guide. Documentation research only; no F* source edited and no implementation DAG executed. Normative claims below come from `implementation_spec.md`; packet is implementation planning; source-status claims describe files currently present, not completion of spec obligations.

## Reading map

- `implementation_spec.md` §§1–6 is semantic authority: typed API (§2, especially §2.2.1), resources (§3), journal/execution (§4), WF/progress (§5), theorem contracts/dependencies (§6). Open representation boundary is §8.
- `implementation_packet.md` §§2–6 translates semantics into module ownership, event shape, proof order, acceptance criteria. It is explicitly a packet, not a substitute for spec (§1, lines 9–39; §3, lines 231–307; §5, lines 344–372).
- `key_correctness_theorems.md` §§1–5 explains dependent types and P0–P16 proof spine; §6 separates abstract theorem status from source status.
- `graph_and_recovery_guide.md` §§1–6 narrates graph construction, generation and recovery; §7 records current source limitations.
- Current source is seven modules in `src/fstar/v2/src/`: `Kernel`, `Identity`, `Graph`, `GraphCodec`, `Journal`, `GenerationExample`, `ChainProof`.

## Objects and their relationships

1. **Typed work package.** A work has fixed input carrier `A` and value-indexed output family `B : A -> Type0`. `LocalWork` carries total `CodeRef.run : x:A -> Tot (B x)`; `ExternalWork` carries request encoding, reply validator returning `option (B x)`, and charge bound; `GenerateWork` carries pure `generate_graph(x, allocation)`. Normative: spec §2.1–2.2, §§2.1 external contract; explainer `key_correctness_theorems.md` §2. Source declarations: `Kernel.fst` lines 99–185.
2. **Durable identity and package lookup.** Graph labels contain first-order `durable_work_ref` (kind plus input/output codec identity), not closures. A pinned immutable registry must recover the exact existential typed package by identity. P0 requires identity uniqueness, package/manifest coherence, codecs, and restart-stable bundle. Normative: spec §2.2 and §6 P0; packet §3. Source: `Kernel.fst` lines 10–62; `Identity.fst` lines 50–188 implements identities/lookups but does not prove exact registry-identity-to-manifest binding (comment `Identity.fst` lines 285–286).
3. **Graph syntax vs typed graph.** `GraphDesc` is ordered node syntax plus output wire; each node has local key, durable work reference, input wire. Wire syntax includes root, prior output, canonical constant bytes, pair, projections. Descriptor stores no executable code, runtime result, or proof. A dependent port telescope and `Wiring` pair syntax/evaluator/type witness; each node's output port type is `B(actual_input)`. `graph_wf` is intended to relate syntax to finite DAG and existential typed witness. Normative: spec §2.2 and §2.2.1; guide §§2–3. Source: `Kernel.fst` lines 63–95; `Graph.fst` lines 150–417 and 600–804.
4. **Allocation and occurrences.** A generated graph has one child allocation per local key; commit lifts them to globally unique path/key node occurrences. Allocation fuels nested generation and reserves charge. Normative: spec §§3–4.3, §5; packet §4. Source: `Kernel.fst` lines 141–165; `Journal.fst` lines 18–38.
5. **Event journal as sole durable authority.** The spec's five events are `RunStarted`, `GraphCommitted`, `NodeCompleted`, `CallIntent`, `CallOutcome`. `S = replay_C(J)`; volatile controller state is not a second state store. Event payloads omit derivable identities/inputs/sequence data where replay reconstructs them. Normative: spec §4.1 lines 1489–1538; packet §4. Source event types: `Journal.fst` lines 47–108. Crucial: present source stops at `journal = list event` and `abstract_state = { state_history }` (`Journal.fst` lines 109–113); no replay/apply/codec exists there.

## Execution, visibility, and recovery lifecycle

1. **Bootstrap:** pinned root entry constructs typed root input, root graph and plan; only after `RunStarted` append commits can node work be claimed. Spec §4.2 lines 2032–2034.
2. **Ready work:** reconstruct each input from root plus committed predecessor outputs, resolve exact pinned Work, use committed occurrence allocation. Local/generator execution is total/pure; external work first gets durable `CallIntent`. Candidate outputs remain volatile and invisible to dependents. Spec §§4.2, 4.3; guide §5.
3. **Authorize and append:** reload/replay latest prefix; recheck occurrence pending and exact identity/input/allocation; build event-specific authorization; one serial append at current head. Only append commit makes `NodeCompleted`, `GraphCommitted`, or `CallOutcome` visible. Stale head invalidates permit and requires reauthorization. Spec §4.2 lines 2053–2074.
4. **Dynamic graph:** pinned generator gets reconstructed input and allocation, returns descriptor plus plan. Commit exact canonical graph bytes and plan before child actions become enabled. Precommit crash may recompute pure generator; postcommit recovery uses committed topology and plan, never regenerates replacement. Spec §4.3 lines 2197–2213.
5. **Recovery:** load latest complete prefix after prior appends settled/fenced, decode canonical events, replay deterministically, resolve graph/work identities, reconstruct typed inputs, indexed-decode saved outputs, and reuse committed results. Precommit local computation may repeat; committed local completion is absorbing. External pending calls resume only using same intent/key/request binding. Spec §§4.1, 4.3–4.4; guide §§5–6.

Semantic provenance is separate from structural replay validity. Canonical bytes/type-correct decode do not establish `y = CodeRef.run(x)`, an outcome's keyed adapter provenance, or that graph bytes came from exact generator result. Spec requires append authorization plus ghost `SemWF`; a trusted genesis and append-only authorized store preserve that fact across cuts. Guide §6, spec §§4.2, 6 P3/P6/P7/P10/P16. Imported/untrusted journals need authentication or provenance checking.

## Concurrency boundary

- One commit coordinator per run in initial model. Bounded local/generator worker claims and several distinct in-flight adapter keys may overlap; workers/adapters cannot commit or expose outputs themselves. Spec §4.2 lines 1886–1916 and 1987–1991.
- Completion order can vary; each result receives separate validation and serial journal append. Multiple journal writes are forbidden by contract. Adapter retries for same key bind to one exact logical effect/receipt; distinct keys can be nondeterministic. Spec §2.1, §4.2; theorem explainer §§6–7.
- Epoch-scoped attempt IDs reject callbacks from revoked workers after restart. The recovery barrier settles/fences old appends before loading, preventing an old append from appearing behind new controller's view. Spec §4.2 lines 2019–2069 and §4.4 lines 2303–2352.
- Multi-coordinator deployment needs shared claim/epoch fencing; a serial journal alone does not give global claim uniqueness. Spec §4.2 lines 1987–1991.
- Durability theorem assumes same store remains available, no disk/device loss, corruption, external edit, or rollback; this is process crash recovery, not disaster recovery. Spec §4.4 lines 2303–2313.

## Theorem map (normative targets, not current proof status)

| Target | Main obligation | Dependency/use |
|---|---|---|
| P0 | Exact pinned identities, package/manifest/codecs | Foundation |
| P1–P2 | Builder/resolver universal typed DAG; canonical graph decode reconstructs typed witness | Graph safety and recovery |
| P3 | Deterministic guarded replay, structural `StateWF`, canonical journal bytes; no provenance inference | Journal foundation |
| P4–P5 | Exact admitted generator result commits before children; recovery reuses exact graph/plan | Dynamic topology |
| P6–P7 | Exact local result and absorbing completion; effect-safe keyed external intent/outcome | Result provenance |
| P8–P9 | Charge/fuel settlement; optional persistent artifact identity | Resource safety; P9 conditional |
| P10 | Every-cut exact durable prefix, monotonicity, settle/fence | Crash boundary |
| P11–P12 | Enabled frontier; well-founded rank/no successful append cycle | Progress foundations |
| P15 | All permitted interleavings preserve authorization, typing, ledger and commit visibility | Abstract safety |
| P16 | Every-cut recovered semantic graph correctness | Composite abstract recovery |
| P13–P14 | Concrete runtime refines abstract contracts; conditional termination under named fairness/liveness | Implementation transfer then liveness |

Authoritative full dependencies and contracts: spec §6; readable spine: `key_correctness_theorems.md` §3 and packet §5. P9 only joins P15/P16 when claiming backing-object identity. P10 proves storage-prefix behavior, not event semantic authorization. P15 covers arbitrary permitted schedules, not concurrent appends. P13 is where real worker pool, adapter, journaler, extraction/host claims must refine explicit contracts.

## Current source status (observed, distinct from normative target)

- **Present foundations:** `Kernel.fst` declares identities, codecs, Work variants, graph syntax, generation allocations/budget. `Identity.fst` has identity equality, durable-ref derivation, packed/global lookup. `Graph.fst` has wire typing, dependent port telescope, graph/DAG predicates, allocation checks, generator membership. `GraphCodec.fst` implements syntax encode/decode and canonical roundtrip lemmas. `Journal.fst` declares event vocabulary only. `GenerationExample.fst` plus `ChainProof.fst` instantiate and prove one input-shaped chain family and generator admission.
- **Known proof holes:** `Graph.fst` has assumed builder type/accessors/start/add at lines 418–525 and `admit()` in builder laws, `finish_graph_sound`, `graph_complete` at lines 908–956. Thus source's graph typing definitions are not generic builder soundness/completeness.
- **Not present:** generic typed graph resolver after decode; `Journal` replay/apply/`StateWF`/append authorization; abstract controller and its interleaving proof; P0 manifest binding; concrete journaler, runner, adapter or P13 refinement. Current `Journal.fst` explicitly calls these V2-04 future work (lines 109–113). `GraphCodec` syntax canonicality alone is not P2 typed reconstruction.
- **Source verification evidence:** guide §7 reports seven modules passed F* verification and accurately limits that to these declarations/examples. It does not mean P0–P16 discharged. The key theorem doc §6 and spec §6 are target contracts.

## Assumptions, strongest caveat, unresolved issue

- **Assumption:** package functions/codecs/generator are total and pinned; adapter and store satisfy proof-bearing contracts. Remote effect semantics and physical host/storage properties require explicit refinement evidence, not inferred from F* model.
- **Strongest caveat:** the present code is a verified typed skeleton plus one chain example, not an executable/recoverable workflow system. In particular, syntax canonicality and a `graph_wf` proposition do not implement graph resolution, replay, authorization, or durable recovery.
- **Unresolved issue:** implement a terminating canonical manifest schema resolver and prove it establishes universal all-legal-environment dependent-edge equality and exact builder completeness for `SchemaSupported`, including after graph decode. This is P0/P1/P2's central representation/proof bottleneck; arbitrary erased F* `Type0` equality is explicitly outside completeness promise (spec §§2.2.1, 6, 8; key theorem doc §2).
